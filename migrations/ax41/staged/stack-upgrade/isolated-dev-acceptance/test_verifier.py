"""Exercise fixture verification with synthetic Kubernetes responses only."""

import ast
import copy
import io
import json
from pathlib import Path
import subprocess
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import yaml

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[4]
REVISION = "a" * 40


class FixtureVerifierTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        app = yaml.safe_load((REPO / "argocd-apps/dev/apps/stack-candidate-acceptance.yaml").read_text())
        cls.values = app["spec"]["source"]["helm"]["valuesObject"]
        rendered = subprocess.run(
            ["helm", "template", "acceptance", str(ROOT), "-n", "playsay-dev", "-f", "-"],
            input=json.dumps(cls.values), text=True, capture_output=True, check=True,
        )
        objects = [item for item in yaml.safe_load_all(rendered.stdout) if item]
        cls.policy = next(item for item in objects if item["kind"] == "NetworkPolicy")["spec"]
        cls.deployment = next(item for item in objects if item["kind"] == "Deployment")["spec"]
        tree = ast.parse((ROOT / "verify_dev_fixture.py").read_text())
        cls.remote = next(ast.literal_eval(node.value) for node in tree.body if isinstance(node, ast.Assign) and any(isinstance(target, ast.Name) and target.id == "remote" for target in node.targets))

    def invoke(self, mutation=None):
        source = {"targetRevision": "develop", "path": "migrations/ax41/staged/stack-upgrade/isolated-dev-acceptance", "helm": {"valuesObject": self.values}}
        app = {"spec": {"destination": {"namespace": "playsay-dev"}, "source": source}, "status": {"sync": {"status": "Synced", "revision": REVISION}}}
        root = {"status": {"sync": {"status": "Synced", "revision": REVISION}}}
        spec = copy.deepcopy(self.deployment["template"]["spec"])
        pod = {"metadata": {"name": "stack-candidate-acceptance-test", "uid": "pod-uid", "labels": {"app": "stack-candidate-acceptance"}, "ownerReferences": [{"kind": "ReplicaSet", "name": "fixture-rs", "uid": "rs-uid", "controller": True}]}, "spec": spec, "status": {"containerStatuses": [{"name": item["name"], "ready": True, "imageID": item["image"]} for item in spec["containers"]]}}
        deployment = {"metadata": {"uid": "deployment-uid", "generation": 1}, "spec": {"replicas": 1}, "status": {"observedGeneration": 1, "updatedReplicas": 1, "readyReplicas": 1, "availableReplicas": 1}}
        replicaset = {"metadata": {"uid": "rs-uid", "ownerReferences": [{"kind": "Deployment", "uid": "deployment-uid"}]}}
        policy = {"metadata": {"name": "stack-candidate-acceptance"}, "spec": copy.deepcopy(self.policy)}
        data = {"root": root, "app": app, "deployment": deployment, "pod": pod, "replicaset": replicaset, "policy": policy, "extraPolicies": []}
        if mutation:
            mutation(data)

        def fake_run(args, **_kwargs):
            command = args[args.index("kubectl") + 1:]
            if "get" in command:
                kind = command[command.index("get") + 1]
                name = command[command.index("get") + 2] if len(command) > command.index("get") + 2 else ""
                if kind == "application": result = data["root"] if name == "playsay-dev-root" else data["app"]
                elif kind == "networkpolicy": result = data["policy"]
                elif kind == "networkpolicies": result = {"items": [data["policy"], *data["extraPolicies"]]}
                elif kind == "deployment": result = data["deployment"]
                elif kind == "pods": result = {"items": [data["pod"]]}
                elif kind == "pod": result = data["pod"]
                elif kind == "replicaset": result = data["replicaset"]
                elif kind == "endpoints": result = {"subsets": [{"addresses": [{"ip": "127.0.0.1"}]}]}
                else: raise AssertionError("Unexpected synthetic Kubernetes request")
                return SimpleNamespace(returncode=0, stdout=json.dumps(result))
            if "exec" in command and "psql" in command:
                return SimpleNamespace(returncode=0, stdout="ready\n")
            if "exec" in command and "python3" in command:
                return SimpleNamespace(returncode=0, stdout=json.dumps({"devIdentity": "reachable", "sharedDatabase": "unreachable", "sharedCollaboration": "unreachable"}))
            raise AssertionError("Unexpected synthetic command")

        payload = {"revision": REVISION, "values": self.values, "policy": self.policy, "deployment": self.deployment, "probe": "synthetic"}
        output = io.StringIO()
        with patch("subprocess.run", side_effect=fake_run), patch("sys.stdin", io.StringIO(json.dumps(payload))), patch("sys.stdout", output):
            exec(compile(self.remote, "<remote verifier>", "exec"), {"__name__": "synthetic_test"})
        return json.loads(output.getvalue())

    def test_accepts_only_a_fully_matching_isolated_fixture(self):
        result = self.invoke()
        self.assertTrue(result["imagesVerified"] and result["networkBoundaryVerified"] and result["syntheticDatabase"])

    def test_rejects_a_different_running_image(self):
        def mutate(data):
            data["pod"]["status"]["containerStatuses"][0]["imageID"] = "sha256:" + "0" * 64
        with self.assertRaises(RuntimeError):
            self.invoke(mutate)

    def test_rejects_weakened_network_policy(self):
        def mutate(data):
            data["policy"]["spec"]["egress"] = [{}]
        with self.assertRaises(RuntimeError):
            self.invoke(mutate)

    def test_rejects_an_additive_policy_that_selects_the_pod(self):
        def mutate(data):
            data["extraPolicies"].append({"metadata": {"name": "broad-egress"}, "spec": {"podSelector": {}, "egress": [{}]}})
        with self.assertRaises(RuntimeError):
            self.invoke(mutate)

    def test_rejects_an_unexpected_container_environment(self):
        def mutate(data):
            data["pod"]["spec"]["containers"][1]["env"].append({"name": "PLAYSAY_DB_JDBC_URL", "value": "jdbc:unexpected"})
        with self.assertRaises(RuntimeError):
            self.invoke(mutate)


if __name__ == "__main__":
    unittest.main()
