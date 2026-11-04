"""Verify the DEV backup refuses ambiguous identity database selection."""
import os
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/backup-dev-databases.sh"
FAKE_KUBECTL = r'''#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
scenario = os.environ['BACKUP_TEST_SCENARIO']
old = 'jdbc:postgresql://keycloak-postgresql:5432/bitnami_keycloak'
new = 'jdbc:postgresql://keycloak-postgres-upgrade-rw:5432/bitnami_keycloak'
url = 'jdbc:postgresql://unknown:5432/bitnami_keycloak' if scenario == 'unknown_endpoint' else new if scenario == 'target_stopped' else old
replicas = 0 if scenario == 'target_stopped' else 1
if '--raw=/readyz' in args:
 print('ok')
elif 'cluster' in args:
 print(json.dumps({'status': {'currentPrimary': 'fixture-primary'}}))
elif 'statefulset' in args:
 print(json.dumps({'metadata': {'generation': 2}, 'status': {'observedGeneration': 1 if scenario == 'stale' else 2, 'readyReplicas': replicas}, 'spec': {'replicas': replicas, 'template': {'spec': {'containers': [{'name':'keycloak','env':[{'name':'KC_DB_URL','value':url}]}]}}}}))
elif 'pods' in args:
 pod_url = new if scenario == 'pod_mismatch' else url
 pod = {'metadata': {'ownerReferences':[{'kind':'StatefulSet','name':'keycloak'}]}, 'status': {'phase':'Running','containerStatuses':[{'name':'keycloak','ready':True}]}, 'spec': {'containers':[{'name':'keycloak','env':[{'name':'KC_DB_URL','value':pod_url}]}]}}
 print(json.dumps({'items': [pod] if replicas else []}))
else:
 raise SystemExit('unexpected fixture kubectl command')
'''


class DevBackupSelectionTest(unittest.TestCase):
    def test_ambiguous_or_unready_identity_never_creates_a_backup_directory(self):
        for scenario in ("unknown_endpoint", "stale", "pod_mismatch", "target_stopped"):
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as tmp:
                bindir = pathlib.Path(tmp) / "bin"
                bindir.mkdir()
                for name, content in {
                    "hostname": "#!/bin/sh\nprintf '%s\\n' playsay-dev\n",
                    "kubectl": FAKE_KUBECTL,
                    "mkdir": "#!/bin/sh\nprintf '%s\\n' unsafe > \"$BACKUP_TEST_SENTINEL\"\nexit 99\n",
                }.items():
                    file = bindir / name
                    file.write_text(content)
                    file.chmod(0o755)
                sentinel = pathlib.Path(tmp) / "backup-directory-attempted"
                env = dict(os.environ, PATH=f"{bindir}:{os.environ['PATH']}", BACKUP_TEST_SCENARIO=scenario, BACKUP_TEST_SENTINEL=str(sentinel))
                result = subprocess.run(["bash", str(SCRIPT)], env=env, capture_output=True, text=True, timeout=20)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertFalse(sentinel.exists(), result.stderr)


if __name__ == "__main__":
    unittest.main()
