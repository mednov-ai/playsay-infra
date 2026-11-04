"""Keep the staged PROD LiveKit image and credential isolated from DEV."""

import json
import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
CHART = ROOT / "helm-charts/livekit"
STAGED = ROOT / "migrations/ax41/staged/stack-upgrade/livekit-prod-values.yaml"


@unittest.skipUnless(shutil.which("helm"), "helm is required")
class StagedProdLiveKitValuesTest(unittest.TestCase):
    def render(self, *args):
        return subprocess.run(["helm", "template", "livekit", str(CHART), *args],
                              capture_output=True, text=True, timeout=30)

    def test_current_prod_does_not_render_staged_credential(self):
        result = self.render("--namespace", "livekit", "-f", str(CHART / "values-prod.yaml"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("kind: SealedSecret", result.stdout)
        self.assertIn("livekit/livekit-server:v1.11.0", result.stdout)

    def test_staged_prod_uses_pinned_image_and_prod_routes(self):
        result = self.render("--namespace", "livekit", "-f", str(CHART / "values-prod.yaml"), "-f", str(STAGED))
        self.assertEqual(result.returncode, 0, result.stderr)
        for value in ("kind: SealedSecret", "api-gateway.playsay-prod.svc.cluster.local", "online.honey.school",
                      "ghcr.io/mednov-ai/playsay-livekit-server@sha256:5bd1c9b8248dd70583d63fa1462104efd41f5d077d9cc7f16135cbb83932e6fe"):
            self.assertIn(value, result.stdout)

    def test_staged_override_uses_the_validated_prod_ciphertext(self):
        sealed = json.loads((STAGED.parent / "livekit-prod-registry-sealedsecret.json").read_text())
        lines = [line for line in STAGED.read_text().splitlines() if line.strip().startswith("encryptedDockerConfig:")]
        self.assertEqual(len(lines), 1)
        ciphertext = json.loads(lines[0].split(":", 1)[1].strip())
        self.assertEqual(ciphertext, sealed["spec"]["encryptedData"][".dockerconfigjson"])

    def test_refuses_dev_mix_or_wrong_namespace(self):
        dev = self.render("--namespace", "livekit", "-f", str(CHART / "values-dev.yaml"), "-f", str(STAGED))
        self.assertNotEqual(dev.returncode, 0)
        self.assertIn("DEV and production", dev.stderr)
        wrong = self.render("--namespace", "other", "-f", str(CHART / "values-prod.yaml"), "-f", str(STAGED))
        self.assertNotEqual(wrong.returncode, 0)
        self.assertIn("livekit namespace", wrong.stderr)


if __name__ == "__main__":
    unittest.main()
