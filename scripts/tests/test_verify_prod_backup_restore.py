"""Confirm the production restore probe refuses the wrong guest or path."""

import os
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/verify-prod-backup-restore.sh"


class ProdRestoreGuardTest(unittest.TestCase):
    def test_restore_cluster_uses_utf8(self):
        script = SCRIPT.read_text()
        self.assertIn("--encoding=UTF8", script)
        self.assertIn("show server_encoding", script)

    def test_wrong_guest_or_backup_path_never_calls_kubectl(self):
        for host, backup, expected in (
            ("playsay-dev", "/var/backups/playsay/stack-upgrade-prod-20261104T111125Z", "unexpected guest"),
            ("playsay-prod", "/var/backups/playsay/other", "expected the task-owned"),
        ):
            with self.subTest(host=host), tempfile.TemporaryDirectory() as tmp:
                bindir = pathlib.Path(tmp)
                sentinel = bindir / "kubectl-called"
                hostname = bindir / "hostname"
                hostname.write_text("#!/bin/sh\nprintf '%s\\n' " + host + "\n")
                hostname.chmod(0o755)
                kubectl = bindir / "kubectl"
                kubectl.write_text("#!/bin/sh\ntouch \"$RESTORE_TEST_SENTINEL\"\nexit 1\n")
                kubectl.chmod(0o755)
                env = dict(os.environ, PATH=f"{bindir}:{os.environ['PATH']}",
                           RESTORE_TEST_SENTINEL=str(sentinel))
                result = subprocess.run(["bash", str(SCRIPT), backup], env=env,
                                        capture_output=True, text=True, timeout=10)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(expected, result.stderr)
                self.assertFalse(sentinel.exists())


if __name__ == "__main__":
    unittest.main()
