"""Check the staged production identity import fails closed before activation."""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
CHART = ROOT / "helm-charts/keycloak-postgres-prod-import"


@unittest.skipUnless(shutil.which("helm"), "helm is required")
class ProdIdentityImportChartTest(unittest.TestCase):
    def render(self, *args):
        return subprocess.run(
            ["helm", "template", "prod-import", str(CHART), *args],
            capture_output=True,
            text=True,
            timeout=30,
        )

    def test_disabled_by_default(self):
        result = self.render("--namespace", "keycloak")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(result.stdout.strip())

    def test_namespace_and_production_credential_are_required(self):
        result = self.render("--namespace", "other", "--set", "enabled=true")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("keycloak namespace", result.stderr)
        result = self.render("--namespace", "keycloak", "--set", "enabled=true")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("sealed username", result.stderr)
        result = self.render("--namespace", "keycloak", "--set", "enabled=true",
                             "--set", "encryptedData.username=plaintext",
                             "--set", "encryptedData.password=plaintext")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("sealed ciphertext", result.stderr)

    def test_source_uses_existing_owner_credential(self):
        result = self.render(
            "--namespace", "keycloak", "--set", "enabled=true",
            "--set", "encryptedData.username=" + "Ag" + "A" * 128,
            "--set", "encryptedData.password=" + "Ag" + "A" * 128,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        for expected in ("kind: Cluster", "kind: SealedSecret", "user: bn_keycloak",
                         "key: password", 'size: "20Gi"', "Prune=false"):
            self.assertIn(expected, result.stdout)
        self.assertNotIn("postgres-password", result.stdout)


if __name__ == "__main__":
    unittest.main()
