#!/usr/bin/env python3

from __future__ import annotations

import unittest

from route_entry import build_driver_command


class RouteEntryTest(unittest.TestCase):
    def test_dev_to_prod_route_is_injected(self) -> None:
        command = build_driver_command("dev", "prod", "apply", ["--pg-service", "prod-db"])
        self.assertIn("--source-environment", command)
        self.assertEqual("dev", command[command.index("--source-environment") + 1])
        self.assertEqual("prod", command[command.index("--target-environment") + 1])
        self.assertEqual("prod", command[command.index("--environment") + 1])

    def test_caller_cannot_override_route(self) -> None:
        with self.assertRaisesRegex(ValueError, "route flags are fixed"):
            build_driver_command("vdsina", "dev", "plan", ["--environment=prod"])


if __name__ == "__main__":
    unittest.main()
