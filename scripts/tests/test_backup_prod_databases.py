"""Verify the PROD backup refuses ambiguous identity database selection."""
import os
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/backup-prod-databases.sh"
FAKE_KUBECTL = r'''#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
scenario = os.environ['BACKUP_TEST_SCENARIO']
old = 'jdbc:postgresql://keycloak-postgresql:5432/bitnami_keycloak'
new = 'jdbc:postgresql://keycloak-postgres-upgrade-rw:5432/bitnami_keycloak'
prod = 'jdbc:postgresql://keycloak-postgres-prod-import-rw:5432/bitnami_keycloak'
url = prod if scenario.startswith('prod_') else 'jdbc:postgresql://unknown:5432/bitnami_keycloak' if scenario == 'unknown_endpoint' else new if scenario == 'target_stopped' else old
replicas = 0 if scenario in ('target_stopped','prod_stopped') else 1
if '--raw=/readyz' in args:
 print('ok')
elif 'cluster' in args:
 if scenario == 'prod_running' and 'playsay-postgres' not in args and 'keycloak-postgres-prod-import' not in args:
  raise SystemExit('wrong production identity cluster')
 print(json.dumps({'status': {'currentPrimary': 'fixture-primary'}}))
elif 'statefulset' in args:
 print(json.dumps({'metadata': {'generation': 2}, 'status': {'observedGeneration': 1 if scenario == 'stale' else 2, 'readyReplicas': replicas}, 'spec': {'replicas': replicas, 'template': {'spec': {'containers': [{'name':'keycloak','env':[{'name':'KC_DB_URL','value':url}]}]}}}}))
elif 'pods' in args:
 pod_url = new if scenario == 'pod_mismatch' else url
 pod = {'metadata': {'ownerReferences':[{'kind':'StatefulSet','name':'keycloak'}]}, 'status': {'phase':'Running','containerStatuses':[{'name':'keycloak','ready':True}]}, 'spec': {'containers':[{'name':'keycloak','env':[{'name':'KC_DB_URL','value':pod_url}]}]}}
 postgres = {'metadata': {'name':'fixture-postgres','ownerReferences':[]}, 'status': {'phase':'Running'}, 'spec': {'containers':[{'name':'postgresql'}]}}
 print(json.dumps({'items': ([pod] if replicas else []) + [postgres]}))
else:
 raise SystemExit('unexpected fixture kubectl command')
'''


class ProdBackupSelectionTest(unittest.TestCase):
    def test_ambiguous_or_unready_identity_never_creates_a_backup_directory(self):
        for scenario, expected in (("unknown_endpoint", "active identity database does not match"), ("stale", "identity workload has not converged"), ("pod_mismatch", "identity pods do not match"), ("target_stopped", "new identity database backup requires"), ("wrong_host", "unexpected guest"), ("ok", "unsafe"), ("prod_stopped", "new identity database backup requires"), ("prod_running", "unsafe")):
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as tmp:
                bindir = pathlib.Path(tmp) / "bin"
                bindir.mkdir()
                for name, content in {
                    "hostname": "#!/bin/sh\nprintf '%s\\n' " + ("playsay-dev" if scenario == "wrong_host" else "playsay-prod") + "\n",
                    "kubectl": FAKE_KUBECTL,
                    "timeout": "#!/bin/sh\nexec \"$@\"\n",
                    "mkdir": "#!/bin/sh\nprintf '%s\\n' unsafe > \"$BACKUP_TEST_SENTINEL\"\nexit 99\n",
                }.items():
                    file = bindir / name
                    file.write_text(content)
                    file.chmod(0o755)
                sentinel = pathlib.Path(tmp) / "backup-directory-attempted"
                env = dict(os.environ, PATH=f"{bindir}:{os.environ['PATH']}", BACKUP_TEST_SCENARIO=scenario, BACKUP_TEST_SENTINEL=str(sentinel))
                result = subprocess.run(["bash", str(SCRIPT)], env=env, capture_output=True, text=True, timeout=20)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertEqual(sentinel.exists(), scenario in ("ok", "prod_running"), result.stderr)
                if scenario not in ("ok", "prod_running"):
                    self.assertIn(expected, result.stderr)


if __name__ == "__main__":
    unittest.main()
