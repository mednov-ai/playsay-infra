#!/usr/bin/env python3

from __future__ import annotations

import subprocess
import unittest
from pathlib import Path


LAUNCHER = Path(__file__).with_name("run_dev_to_prod_operator.sh")


class OperatorLauncherTest(unittest.TestCase):
    def test_help_is_available_without_environment_access(self) -> None:
        completed = subprocess.run(
            ["bash", str(LAUNCHER), "--help"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        self.assertEqual(0, completed.returncode, completed.stderr)
        self.assertIn("--apply", completed.stdout)

    def test_launcher_keeps_production_safety_gates(self) -> None:
        source = LAUNCHER.read_text(encoding="utf-8")
        self.assertIn("set +x", source)
        self.assertIn("trap cleanup EXIT INT TERM", source)
        self.assertIn("Type APPLY PROD", source)
        self.assertGreaterEqual(source.count("--operator-production-approval"), 2)
        self.assertIn('openssl pkey -in "$private_key" -pubout', source)
        self.assertIn("printf -v \"$result_variable\"", source)
        self.assertNotIn('dev_tunnel_pid="$(start_tunnel', source)
        self.assertNotIn(" port-forward ", source)
        self.assertIn("ExitOnForwardFailure=yes", source)
        self.assertIn("get service $service -o jsonpath='{.spec.clusterIP}'", source)
        self.assertIn('-L "$local_keycloak:$keycloak_ip:5432"', source)
        self.assertGreaterEqual(source.count("ssh -n ${ssh_common[*]@Q}"), 4)


if __name__ == "__main__":
    unittest.main()
