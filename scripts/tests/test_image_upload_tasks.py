"""Exercise the scoped Ansible tasks on disposable local nginx fixtures."""

import getpass
import grp
import json
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HEADER = "location ~ ^/api/(?:materials/[^/]+/(?:image-page|assets/images)|schedule/lessons/[^/]+/image-page)$ {"
BEGIN = "    # BEGIN HONEY SCHOOL IMAGE UPLOAD ROUTES\n"
END = "    # END HONEY SCHOOL IMAGE UPLOAD ROUTES\n"


class ScopedImageRoutesTest(unittest.TestCase):
    def run_case(self, kind):
        hostname = ("dev.online.honey.school" if kind == "AX41 DEV" else
                    "online.honey.school" if kind == "AX41" else "online.honeyschool.ru")
        other_hostname = "online.honey.school" if kind == "AX41 DEV" else "dev." + hostname
        upstream = "10.60.0.30:32083" if kind == "AX41 DEV" else "10.60.0.20:32083"
        task_path = ROOT / ("ansible/roles/edge-proxy/tasks/image-upload-routes.yaml" if kind.startswith("AX41")
                            else "ansible/roles/rf-edge-proxy/tasks/image-upload-routes.yaml")
        production_path = ("/etc/nginx/conf.d/playsay-honey.conf" if kind.startswith("AX41")
                           else "/etc/nginx/conf.d/playsay-honey-rf-edge.conf")
        fixture = (
            "server {\n    listen 80;\n    server_name " + hostname + ";\n    location / { return 301; }\n}\n"
            "server {\n    listen 443 ssl;\n    server_name " + hostname + ";\n    location / { proxy_pass http://upstream; }\n}\n"
            "server {\n    listen 443 ssl;\n    server_name " + other_hostname + ";\n    " + HEADER
            + "\n        client_max_body_size 21m;\n    }\n"
            "    location = /api/worksheet-imports { client_max_body_size 129m; }\n"
            "    location = /api/materials/ai-draft { client_max_body_size 3m; }\n"
            "    location / { return 200; }\n}\n"
        )
        with tempfile.TemporaryDirectory(prefix="image-upload-ansible-") as directory:
            tmp = Path(directory)
            config = tmp / "nginx.conf"
            config.write_text(fixture)
            task = task_path.read_text().replace(production_path, str(config)).replace("cmd: nginx -t", "cmd: /usr/bin/true")
            tasks = tmp / "tasks.yaml"
            tasks.write_text(task)
            play = tmp / "play.yaml"
            play.write_text(
                "- hosts: localhost\n"
                "  gather_facts: false\n"
                "  vars:\n"
                "    edge_routes:\n"
                "      - {hostname: " + hostname + ", upstream: '" + upstream + "'}\n"
                "    ax41_image_target_hostname: " + hostname + "\n"
                "    ax41_image_target_upstream: '" + upstream + "'\n"
                "    ax41_image_target_enabled: '{{ image_upload_routes_" +
                ("dev" if kind == "AX41 DEV" else "prod") + "_enabled | default(true) }}'\n"
                "    rf_edge_origin_address: 127.0.0.1\n"
                "  tasks:\n"
                "    - ansible.builtin.import_tasks: " + str(tasks) + "\n"
                "  handlers:\n"
                "    - name: reload nginx\n"
                "      ansible.builtin.command: /usr/bin/true\n"
            )
            env = os.environ.copy()
            ansible_config = tmp / "ansible.cfg"
            ansible_config.write_text("[defaults]\n")
            env["ANSIBLE_CONFIG"] = str(ansible_config)
            env["ANSIBLE_NOCOLOR"] = "1"

            def run(*options, expected=0):
                result = subprocess.run(
                    ["ansible-playbook", "-i", "localhost,", "-c", "local", str(play), *options],
                    capture_output=True, text=True, env=env,
                )
                if (result.returncode == 0) != (expected == 0):
                    self.fail(result.stdout + result.stderr)
                return result.stdout

            run("--check", "--diff")
            self.assertEqual(config.read_text(), fixture, "check mode must not write")
            run()
            updated = config.read_text()
            self.assertEqual(updated.count(BEGIN), 1)
            self.assertEqual(updated.count(END), 1)
            target = updated.split("server_name " + hostname + ";")[2].split("server {")[0]
            for header, limit in (
                (HEADER, "21m"),
                ("location = /api/worksheet-imports {", "129m"),
                ("location = /api/materials/ai-draft {", "3m"),
            ):
                self.assertIn(header, target)
                self.assertIn("client_max_body_size " + limit + ";", target.split(header)[1].split("}")[0])
            self.assertEqual(re.sub(re.escape(BEGIN) + r".*?" + re.escape(END), "", updated, flags=re.S), fixture)
            self.assertIn("changed=0", run(), "a repeat must be idempotent")
            flag = "image_upload_routes_dev_enabled" if kind == "AX41 DEV" else "image_upload_routes_prod_enabled"
            run("-e", json.dumps({flag: False}))
            self.assertEqual(config.read_text(), fixture, "scoped rollback must restore the original file")

            # Simulate a failed nginx validation followed by a successful check
            # of the restored file, without changing local services.
            probe = tmp / "validate-once.sh"
            marker = tmp / "validation-failed-once"
            probe.write_text("#!/bin/sh\nif [ ! -e '" + str(marker) + "' ]; then touch '" + str(marker)
                             + "'; exit 1; fi\nexit 0\n")
            probe.chmod(0o755)
            failing_task = task_path.read_text().replace(production_path, str(config))
            failing_task = failing_task.replace("cmd: nginx -t", "cmd: " + str(probe))
            failing_task = failing_task.replace("owner: root", "owner: " + getpass.getuser())
            failing_task = failing_task.replace("group: root", "group: " + grp.getgrgid(os.getgid()).gr_name)
            failing_task = failing_task.replace(
                "ansible.builtin.service:\n        name: nginx\n        state: reloaded",
                "ansible.builtin.command:\n        cmd: /usr/bin/true",
            )
            tasks.write_text(failing_task)
            run(expected=1)
            self.assertTrue(marker.exists())
            self.assertEqual(config.read_text(), fixture, "failed validation must restore the original file")

            # A handler failure is part of the same transaction and must also
            # restore the saved file before returning an error.
            reload_failure = tmp / "reload-fails.sh"
            reload_failure.write_text("#!/bin/sh\nexit 1\n")
            reload_failure.chmod(0o755)
            handler_task = task.replace("owner: root", "owner: " + getpass.getuser())
            handler_task = handler_task.replace("group: root", "group: " + grp.getgrgid(os.getgid()).gr_name)
            handler_task = handler_task.replace(
                "ansible.builtin.service:\n        name: nginx\n        state: reloaded",
                "ansible.builtin.command:\n        cmd: /usr/bin/true",
            )
            tasks.write_text(handler_task)
            previous_play = play.read_text()
            play.write_text(previous_play.replace("ansible.builtin.command: /usr/bin/true",
                                                  "ansible.builtin.command: " + str(reload_failure)))
            run(expected=1)
            self.assertEqual(config.read_text(), fixture, "failed activation must restore the original file")
            play.write_text(previous_play)
            tasks.write_text(task)

            # A differently scoped existing location is a conflict, not permission
            # to silently replace or widen it.
            conflict = fixture.replace("location / { proxy_pass http://upstream; }",
                                       "location ~ ^/api/schedule/lessons/[^/]+/image-page$ { return 418; }\n"
                                       "    location / { proxy_pass http://upstream; }")
            config.write_text(conflict)
            run(expected=1)
            self.assertEqual(config.read_text(), conflict)

    def test_ax41(self):
        self.run_case("AX41")

    def test_ax41_dev(self):
        self.run_case("AX41 DEV")

    def test_rf(self):
        self.run_case("RF")

    def test_wrapper_rejects_unsafe_modes(self):
        wrapper = ROOT / "scripts/apply-rf-edge-release.sh"
        for options in (
            ["--syntax", "--image-upload-only"],
            ["--check", "--image-upload-only", "--monitoring-only"],
            ["--check", "--image-upload-only", "--acme-only"],
        ):
            result = subprocess.run([str(wrapper), *options], capture_output=True, text=True)
            self.assertEqual(result.returncode, 2, options)


if __name__ == "__main__":
    unittest.main()
