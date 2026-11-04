"""Check the synthetic acceptance chart's deployment boundary without a cluster."""

import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from urllib.parse import urlparse

import yaml

CHART = Path(__file__).resolve().parent
DIGEST = "sha256:" + "a" * 64


def render(namespace="playsay-dev", enabled=True, api_digest=DIGEST, probe_only=False):
    args = [
        "helm", "template", "acceptance", str(CHART), "--namespace", namespace,
        "--set", "enabled=" + str(enabled).lower(),
        "--set", "probeOnly=" + str(probe_only).lower(),
        "--set-string", "images.apiDigest=" + api_digest,
        "--set-string", "images.webDigest=" + DIGEST,
        "--set-string", "images.collaborationDigest=" + DIGEST,
    ]
    return subprocess.run(args, text=True, capture_output=True, check=False)


class IsolatedAcceptanceBoundaryTest(unittest.TestCase):
    def test_disabled_chart_creates_nothing(self):
        result = render(enabled=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(result.stdout.strip())

    def test_production_and_unpinned_images_are_refused(self):
        self.assertNotEqual(render(namespace="playsay-prod").returncode, 0)
        self.assertNotEqual(render(api_digest="latest").returncode, 0)

    def test_probe_stage_contains_no_application_or_secrets(self):
        result = render(probe_only=True, api_digest="")
        self.assertEqual(result.returncode, 0, result.stderr)
        objects = [obj for obj in yaml.safe_load_all(result.stdout) if obj]
        self.assertEqual({obj["kind"] for obj in objects}, {"Job", "NetworkPolicy"})
        spec = next(obj for obj in objects if obj["kind"] == "Job")["spec"]["template"]["spec"]
        self.assertFalse(spec["automountServiceAccountToken"])
        self.assertEqual([item["name"] for item in spec["containers"]], ["probe"])
        self.assertNotIn("secretKeyRef", json.dumps(spec))

    def test_fixture_cannot_reach_shared_databases_or_production(self):
        result = render()
        self.assertEqual(result.returncode, 0, result.stderr)
        objects = [obj for obj in yaml.safe_load_all(result.stdout) if obj]
        self.assertEqual({obj["kind"] for obj in objects}, {"Deployment", "NetworkPolicy"})
        policy = next(obj for obj in objects if obj["kind"] == "NetworkPolicy")["spec"]
        self.assertEqual(policy["ingress"], [])
        namespaces = {
            dest["namespaceSelector"]["matchLabels"]["kubernetes.io/metadata.name"]
            for rule in policy["egress"] for dest in rule["to"]
        }
        self.assertEqual(namespaces, {"keycloak", "kube-system"})
        identity_rule = next(rule for rule in policy["egress"] if rule["to"][0]["namespaceSelector"]["matchLabels"]["kubernetes.io/metadata.name"] == "keycloak")
        self.assertEqual(identity_rule["to"][0]["podSelector"]["matchLabels"], {
            "app.kubernetes.io/name": "keycloak", "app.kubernetes.io/component": "keycloak",
        })
        self.assertEqual({port["port"] for port in identity_rule["ports"]}, {80, 8080})
        spec = next(obj for obj in objects if obj["kind"] == "Deployment")["spec"]["template"]["spec"]
        self.assertFalse(spec["automountServiceAccountToken"])
        self.assertNotIn("hostNetwork", spec)
        containers = {container["name"]: container for container in spec["containers"]}
        self.assertEqual(set(containers), {"postgres", "api", "collaboration", "web"})
        api = {item["name"]: item.get("value") for item in containers["api"]["env"]}
        self.assertEqual(api["PLAYSAY_DB_JDBC_URL"], "jdbc:postgresql://127.0.0.1:5432/playsay")
        self.assertEqual(api["PLAYSAY_STORAGE_PROVIDER"], "memory")
        self.assertEqual(api["PLAYSAY_PUBLIC_APP_URL"], "https://dev.online.honey.school")
        for value in api.values():
            if value and value.startswith(("http://", "https://", "ws://", "wss://")):
                host = urlparse(value).hostname
                self.assertIn(host, {
                    "127.0.0.1", "dev.online.honey.school", "dev.online.honeyschool.ru",
                    "dev.ops.honey.school", "keycloak.keycloak.svc.cluster.local",
                })
        self.assertNotIn("volumes", spec)
        self.assertNotIn("persistentVolumeClaim", json.dumps(spec))

    def test_smoke_adapter_refuses_changed_source_and_existing_output(self):
        source_text = '''import path from "node:path";
const authClientId = process.env.PLAY_SAY_SMOKE_AUTH_CLIENT_ID ?? "playsay-web";
const sshJumpHost = process.env.PLAY_SAY_SMOKE_SSH_JUMP_HOST ?? "root@65.109.55.110";
async function session(nextBrowser) {
  const context = await nextBrowser.newContext({
    ignoreHTTPSErrors: false,
  });
  if (fakeMedia) {
    await context.grantPermissions([]);
  }
  const formUrl = new URL(form.action);
}
'''
        with tempfile.TemporaryDirectory(prefix="stack-acceptance-test-") as directory:
            root = Path(directory)
            source, output = root / "source.mjs", root / "output.mjs"
            source.write_text(source_text)
            command = ["python3", str(CHART / "prepare_smoke.py"), str(source), str(output)]
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(subprocess.run(["node", "--check", str(output)], capture_output=True).returncode, 0)
            self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)
            source.write_text("unrecognized source")
            self.assertNotEqual(subprocess.run(["python3", str(CHART / "prepare_smoke.py"), str(source), str(root / "other.mjs")], capture_output=True).returncode, 0)


if __name__ == "__main__":
    unittest.main()
