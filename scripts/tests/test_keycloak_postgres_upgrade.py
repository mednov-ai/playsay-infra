"""Safety contracts for the DEV-only Keycloak PostgreSQL import chart."""
import pathlib
import subprocess
import unittest

import yaml

ROOT = pathlib.Path(__file__).resolve().parents[2]
CHART = ROOT / "helm-charts/keycloak-postgres-upgrade"


class KeycloakPostgresUpgradeChartTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        rendered = subprocess.run(
            ["helm", "template", "keycloak-postgres-upgrade", str(CHART), "--namespace", "keycloak"],
            check=True, capture_output=True, text=True,
        ).stdout
        cls.resources = {item["kind"]: item for item in yaml.safe_load_all(rendered) if item}

    def test_import_preserves_database_identity_and_limits(self):
        cluster = self.resources["Cluster"]
        self.assertEqual(cluster["metadata"]["namespace"], "keycloak")
        self.assertEqual(cluster["metadata"]["annotations"]["argocd.argoproj.io/sync-options"], "Prune=false")
        spec = cluster["spec"]
        self.assertEqual(spec["imageName"], "ghcr.io/cloudnative-pg/postgresql:17.11-system-trixie")
        self.assertEqual(spec["instances"], 1)
        init = spec["bootstrap"]["initdb"]
        self.assertEqual((init["database"], init["owner"]), ("bitnami_keycloak", "bn_keycloak"))
        self.assertEqual((init["localeCollate"], init["localeCType"]), ("en_US.UTF-8", "en_US.UTF-8"))
        self.assertEqual(init["secret"]["name"], "keycloak-postgres-upgrade-app")
        self.assertEqual(init["import"]["type"], "microservice")
        self.assertEqual(init["import"]["databases"], ["bitnami_keycloak"])
        source = spec["externalClusters"][0]
        self.assertEqual(init["import"]["source"]["externalCluster"], source["name"])
        self.assertEqual(source["connectionParameters"], {"host": "keycloak-postgresql", "dbname": "postgres", "user": "postgres"})
        self.assertEqual(source["password"], {"name": "keycloak-postgresql", "key": "postgres-password"})
        self.assertEqual(spec["postgresql"]["shared_preload_libraries"], ["pgaudit"])
        self.assertEqual(spec["resources"]["limits"], {"cpu": "500m", "memory": "384Mi"})
        self.assertEqual(spec["storage"]["size"], "4Gi")

    def test_credential_is_dev_scoped_encrypted_and_retained(self):
        sealed = self.resources["SealedSecret"]
        self.assertEqual((sealed["metadata"]["name"], sealed["metadata"]["namespace"]), ("keycloak-postgres-upgrade-app", "keycloak"))
        self.assertEqual(sealed["metadata"]["annotations"]["argocd.argoproj.io/sync-options"], "Prune=false")
        self.assertEqual(sealed["spec"]["template"]["type"], "kubernetes.io/basic-auth")
        self.assertEqual(set(sealed["spec"]["encryptedData"]), {"username", "password"})
        self.assertNotIn("data", sealed["spec"]["template"])
        self.assertNotIn("stringData", sealed["spec"]["template"])

    def test_only_dev_registers_the_new_application(self):
        app = yaml.safe_load((ROOT / "argocd-apps/dev/apps/keycloak-postgres-upgrade.yaml").read_text())
        self.assertEqual(app["spec"]["source"]["targetRevision"], "develop")
        self.assertEqual(app["spec"]["source"]["path"], "helm-charts/keycloak-postgres-upgrade")
        self.assertEqual(app["spec"]["destination"]["namespace"], "keycloak")
        self.assertFalse((ROOT / "argocd-apps/prod/apps/keycloak-postgres-upgrade.yaml").exists())


if __name__ == "__main__":
    unittest.main()
