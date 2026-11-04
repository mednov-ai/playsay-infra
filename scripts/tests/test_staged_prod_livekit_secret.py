"""Check the staged production pull credential has no plaintext Secret data."""

import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
STAGED = ROOT / "migrations/ax41/staged/stack-upgrade/livekit-prod-registry-sealedsecret.json"


class StagedProdLiveKitSecretTest(unittest.TestCase):
    def test_scoped_encrypted_registry_secret(self):
        value = json.loads(STAGED.read_text())
        self.assertEqual(value["kind"], "SealedSecret")
        self.assertEqual(value["metadata"]["name"], "ghcr-pull-secret")
        self.assertEqual(value["metadata"]["namespace"], "livekit")
        spec = value["spec"]
        self.assertEqual(spec["template"]["type"], "kubernetes.io/dockerconfigjson")
        self.assertEqual(set(spec["encryptedData"]), {".dockerconfigjson"})
        self.assertRegex(spec["encryptedData"][".dockerconfigjson"], r"^Ag[A-Za-z0-9+/]{100,}={0,2}$")
        self.assertNotIn("data", value)
        self.assertNotIn("data", spec)
        self.assertNotIn("data", spec["template"])


if __name__ == "__main__":
    unittest.main()
