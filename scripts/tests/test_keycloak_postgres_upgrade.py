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
        self.assertEqual(
            spec["imageName"],
            "ghcr.io/cloudnative-pg/postgresql:17.11-system-trixie@sha256:"
            "03a1c6a62b27e8ad31cae5c085131b5ac706b09403d6fcb6c58d16c8daa257cd",
        )
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

    def test_import_application_is_staged_outside_the_live_gitops_tree(self):
        app = yaml.safe_load(
            (ROOT / "migrations/ax41/staged/stack-upgrade/keycloak-postgres-upgrade.application.yaml").read_text(),
        )
        self.assertEqual(app["spec"]["source"]["targetRevision"], "develop")
        self.assertEqual(app["spec"]["source"]["path"], "helm-charts/keycloak-postgres-upgrade")
        self.assertEqual(app["spec"]["destination"]["namespace"], "keycloak")
        self.assertFalse((ROOT / "argocd-apps/dev/apps/keycloak-postgres-upgrade.yaml").exists())
        self.assertFalse((ROOT / "argocd-apps/prod/apps/keycloak-postgres-upgrade.yaml").exists())

    def test_application_database_upgrade_is_staged_not_active(self):
        path = ROOT / "migrations/ax41/staged/stack-upgrade/app-postgres-values-dev.yaml"
        staged = yaml.safe_load(path.read_text())["cluster"]["imageName"]
        active = yaml.safe_load((ROOT / "helm-charts/app-postgres/values-dev.yaml").read_text())
        self.assertEqual(staged, self.resources["Cluster"]["spec"]["imageName"])
        self.assertNotEqual(active["cluster"]["imageName"], staged)

    def test_operator_candidate_cannot_be_reconciled_by_active_applications(self):
        staged = ROOT / "migrations/ax41/staged/stack-upgrade/cloudnative-pg-operator-1.30.1/kustomization.yaml"
        candidate = yaml.safe_load(staged.read_text())
        self.assertEqual(candidate["images"][0]["newTag"], "1.30.1")
        digest = candidate["images"][0]["digest"]
        self.assertEqual(digest, "sha256:923c267ec29636db3bee20f993d0ec4973fa22998e1adad37da79e4d32b5bc07")
        self.assertIn("2a35abb4628f209d149825ef3c38011e0701ff2f", candidate["resources"][0])
        self.assertIn(digest, candidate["patches"][0]["patch"])
        for environment in ("dev", "prod"):
            app = yaml.safe_load((ROOT / f"argocd-apps/{environment}/apps/cloudnative-pg.yaml").read_text())
            self.assertEqual(app["spec"]["source"]["path"], "kustomize/cloudnative-pg-operator")
        active = yaml.safe_load((ROOT / "kustomize/cloudnative-pg-operator/kustomization.yaml").read_text())
        self.assertEqual(active["images"][0]["newTag"], "1.29.1")


if __name__ == "__main__":
    unittest.main()
