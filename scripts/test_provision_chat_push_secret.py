import base64
import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("provision", Path(__file__).with_name("provision-chat-push-secret.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ProvisionTest(unittest.TestCase):
    def test_create_preserve_and_environment_isolation(self):
        with patch.object(module.subprocess, "run", return_value=SimpleNamespace(stdout="")) as run:
            first = module.provision("playsay-dev", "mailto:ops@honey.school")
            secret = json.loads(run.call_args.kwargs["input"])
            self.assertEqual(2, run.call_count)
            self.assertNotIn(secret["stringData"]["private-key"], first)
        stored = {"data": {key: base64.b64encode(value.encode()).decode()
            for key, value in secret["stringData"].items()}}
        with patch.object(module.subprocess, "run", return_value=SimpleNamespace(stdout=json.dumps(stored))) as run:
            self.assertEqual(first, module.provision("playsay-dev", "mailto:changed@honey.school"))
            self.assertEqual(1, run.call_count)
        with patch.object(module.subprocess, "run", return_value=SimpleNamespace(stdout="")):
            self.assertNotEqual(first, module.provision("playsay-prod", "mailto:ops@honey.school"))

    def test_missing_keys_and_lookup_failure_do_not_create(self):
        for response in (SimpleNamespace(stdout='{"data":{}}'), RuntimeError("redacted")):
            with patch.object(module.subprocess, "run") as run:
                if isinstance(response, Exception):
                    run.side_effect = response
                else:
                    run.return_value = response
                with self.assertRaises(Exception):
                    module.provision("playsay-prod", "mailto:ops@honey.school")
                self.assertEqual(1, run.call_count)


if __name__ == "__main__":
    unittest.main()
