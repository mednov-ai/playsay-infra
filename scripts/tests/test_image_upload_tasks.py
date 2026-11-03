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
        hostname = ("dev.online.honeyschool.ru" if kind == "RF DEV" else
                    "dev.online.honey.school" if kind == "AX41 DEV" else
                    "online.honey.school" if kind == "AX41" else "online.honeyschool.ru")
        other_hostname = hostname.removeprefix("dev.") if kind.endswith("DEV") else "dev." + hostname
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
        existing_location = "location / { proxy_pass http://upstream; }"
        if kind.startswith("RF"):
            origin_hostname = "dev.online.honey.school" if kind == "RF DEV" else "online.honey.school"
            rf_location = ("location / { proxy_pass https://127.0.0.1; proxy_ssl_name "
                           + origin_hostname + "; }")
            fixture = fixture.replace(existing_location, rf_location)
            existing_location = rf_location
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
                ("dev" if kind.endswith("DEV") else "prod") + "_enabled | default(true) }}'\n"
                "    rf_image_target_path: '" + str(config) + "'\n"
                "    rf_image_target_hostname: " + hostname + "\n"
                "    rf_image_origin_hostname: " + ("dev.online.honey.school" if kind == "RF DEV" else "online.honey.school") + "\n"
                "    rf_image_target_enabled: '{{ image_upload_routes_" +
                ("dev" if kind.endswith("DEV") else "prod") + "_enabled | default(true) }}'\n"
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
            target_begin = BEGIN.replace(" ROUTES\n", " ROUTES PROD\n") if kind == "AX41" else BEGIN
            target_end = END.replace(" ROUTES\n", " ROUTES PROD\n") if kind == "AX41" else END
            self.assertEqual(updated.count(target_begin), 1)
            self.assertEqual(updated.count(target_end), 1)
            target = updated.split("server_name " + hostname + ";")[2].split("server {")[0]
            for header, limit in (
                (HEADER, "21m"),
                ("location = /api/worksheet-imports {", "129m"),
                ("location = /api/materials/ai-draft {", "3m"),
            ):
                self.assertIn(header, target)
                self.assertIn("client_max_body_size " + limit + ";", target.split(header)[1].split("}")[0])
            self.assertEqual(re.sub(re.escape(target_begin) + r".*?" + re.escape(target_end), "", updated, flags=re.S), fixture)
            self.assertIn("changed=0", run(), "a repeat must be idempotent")
            if kind.startswith("RF"):
                for header in (HEADER, "location = /api/worksheet-imports {", "location = /api/materials/ai-draft {"):
                    start = updated.index(header)
                    end = updated.index("}", start)
                    block = updated[start:end]
                    wrong_block = block.replace("proxy_pass https://127.0.0.1;", "proxy_pass https://127.0.0.2;", 1)
                    self.assertNotEqual(wrong_block, block)
                    wrong_scoped = updated[:start] + wrong_block + updated[end:]
                    config.write_text(wrong_scoped)
                    run(expected=1)
                    self.assertEqual(config.read_text(), wrong_scoped)
                config.write_text(updated)
            flag = "image_upload_routes_dev_enabled" if kind.endswith("DEV") else "image_upload_routes_prod_enabled"
            run("-e", json.dumps({flag: False}))
            self.assertEqual(config.read_text(), fixture, "scoped rollback must restore the original file")
            if kind.startswith("RF"):
                foreign_anchor = "server_name " + other_hostname + ";\n    " + HEADER
                foreign = fixture.replace(foreign_anchor, "server_name " + other_hostname + ";\n"
                    + BEGIN + END + "    " + HEADER, 1)
                self.assertNotEqual(foreign, fixture)
                config.write_text(foreign)
                run(expected=1)
                self.assertEqual(config.read_text(), foreign)
                config.write_text(fixture)

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
            conflict = fixture.replace(existing_location,
                                       "location ~ ^/api/schedule/lessons/[^/]+/image-page$ { return 418; }\n"
                                       "    " + existing_location)
            config.write_text(conflict)
            run(expected=1)
            self.assertEqual(config.read_text(), conflict)
            if kind.startswith("RF"):
                wrong_origin = fixture.replace("proxy_ssl_name " + origin_hostname,
                                               "proxy_ssl_name unexpected.example")
                config.write_text(wrong_origin)
                run(expected=1)
                self.assertEqual(config.read_text(), wrong_origin)

    def test_ax41_shared_file_dev_and_prod_markers_are_independent(self):
        dev = "dev.online.honey.school"
        prod = "online.honey.school"
        dev_upstream = "10.60.0.30:32083"
        prod_upstream = "10.60.0.20:32083"
        fixture = "".join(
            "server {\n    listen 80;\n    server_name " + host + ";\n    location / { return 301; }\n}\n"
            "server {\n    listen 443 ssl;\n    server_name " + host + ";\n    location / { proxy_pass http://" + upstream + "; }\n}\n"
            for host, upstream in ((dev, dev_upstream), (prod, prod_upstream))
        )
        task_path = ROOT / "ansible/roles/edge-proxy/tasks/image-upload-routes.yaml"
        with tempfile.TemporaryDirectory(prefix="image-upload-shared-ax41-") as directory:
            tmp = Path(directory)
            config = tmp / "nginx.conf"
            config.write_text(fixture)
            task = task_path.read_text().replace("/etc/nginx/conf.d/playsay-honey.conf", str(config))
            task = task.replace("cmd: nginx -t", "cmd: /usr/bin/true")
            tasks = tmp / "tasks.yaml"
            tasks.write_text(task)
            play = tmp / "play.yaml"
            play.write_text(
                "- hosts: localhost\n"
                "  gather_facts: false\n"
                "  vars:\n"
                "    edge_routes:\n"
                "      - {hostname: " + dev + ", upstream: '" + dev_upstream + "'}\n"
                "      - {hostname: " + prod + ", upstream: '" + prod_upstream + "'}\n"
                "    ax41_image_target_hostname: '{{ target_hostname }}'\n"
                "    ax41_image_target_upstream: '{{ target_upstream }}'\n"
                "    ax41_image_target_enabled: '{{ enabled | default(true) }}'\n"
                "  tasks:\n"
                "    - ansible.builtin.import_tasks: " + str(tasks) + "\n"
                "  handlers:\n"
                "    - name: reload nginx\n"
                "      ansible.builtin.command: /usr/bin/true\n"
            )
            ansible_config = tmp / "ansible.cfg"
            ansible_config.write_text("[defaults]\n")
            env = {**os.environ, "ANSIBLE_CONFIG": str(ansible_config), "ANSIBLE_NOCOLOR": "1"}

            def run(host, upstream, *options, enabled=True, expected=0):
                args = {"target_hostname": host, "target_upstream": upstream, "enabled": enabled}
                result = subprocess.run(
                    ["ansible-playbook", "-i", "localhost,", "-c", "local", str(play),
                     "-e", json.dumps(args), *options], capture_output=True, text=True, env=env,
                )
                if (result.returncode == 0) != (expected == 0):
                    self.fail(result.stdout + result.stderr)
                return result.stdout

            def server(contents, host):
                return contents.split("server_name " + host + ";")[2].split("server {")[0]

            run(dev, dev_upstream)
            after_dev = config.read_text()
            dev_block = server(after_dev, dev)
            self.assertIn("proxy_pass http://" + dev_upstream + ";", dev_block)
            preview = run(prod, prod_upstream, "--check", "--diff")
            self.assertEqual(config.read_text(), after_dev, "check mode must not write")
            self.assertNotIn("-    proxy_pass http://" + dev_upstream + ";", preview,
                             "PROD must never replace the existing DEV marker")
            run(prod, prod_upstream)
            both = config.read_text()
            self.assertEqual(server(both, dev), dev_block)
            self.assertIn("proxy_pass http://" + prod_upstream + ";", server(both, prod))
            self.assertIn("# BEGIN HONEY SCHOOL IMAGE UPLOAD ROUTES PROD", server(both, prod))
            self.assertIn("changed=0", run(dev, dev_upstream))
            self.assertIn("changed=0", run(prod, prod_upstream))

            prod_begin = "    # BEGIN HONEY SCHOOL IMAGE UPLOAD ROUTES PROD\n"
            prod_end = "    # END HONEY SCHOOL IMAGE UPLOAD ROUTES PROD\n"
            block = re.search(re.escape(prod_begin) + r".*?" + re.escape(prod_end), both, re.S)
            self.assertIsNotNone(block)
            duplicate = both.replace(block.group(0), block.group(0) * 2, 1)
            config.write_text(duplicate)
            run(prod, prod_upstream, expected=1)
            self.assertEqual(config.read_text(), duplicate)
            dangling = both.replace(prod_end, "", 1)
            config.write_text(dangling)
            run(prod, prod_upstream, expected=1)
            self.assertEqual(config.read_text(), dangling)
            wrong_marker = both.replace(prod_begin, BEGIN, 1).replace(prod_end, END, 1)
            config.write_text(wrong_marker)
            run(prod, prod_upstream, expected=1)
            self.assertEqual(config.read_text(), wrong_marker)
            config.write_text(both)

            for header in (HEADER, "location = /api/worksheet-imports {", "location = /api/materials/ai-draft {"):
                start = both.index(header, both.index(prod_begin))
                end = both.index("}", start)
                block = both[start:end]
                wrong_block = block.replace("proxy_pass http://" + prod_upstream + ";",
                                            "proxy_pass http://" + dev_upstream + ";", 1)
                self.assertNotEqual(wrong_block, block)
                wrong_upstream = both[:start] + wrong_block + both[end:]
                config.write_text(wrong_upstream)
                run(prod, prod_upstream, expected=1)
                self.assertEqual(config.read_text(), wrong_upstream)
            config.write_text(both)

            run(prod, prod_upstream, enabled=False)
            self.assertEqual(server(config.read_text(), dev), dev_block)
            self.assertEqual(config.read_text(), after_dev)
            run(dev, dev_upstream, enabled=False)
            self.assertEqual(config.read_text(), fixture)

            foreign = fixture.replace("    server_name " + dev + ";\n    location / { proxy_pass",
                "    server_name " + dev + ";\n    # BEGIN HONEY SCHOOL IMAGE UPLOAD ROUTES PROD\n"
                "    # END HONEY SCHOOL IMAGE UPLOAD ROUTES PROD\n    location / { proxy_pass", 1)
            self.assertNotEqual(foreign, fixture)
            config.write_text(foreign)
            run(prod, prod_upstream, expected=1)
            self.assertEqual(config.read_text(), foreign)

    def test_ax41(self):
        self.run_case("AX41")

    def test_ax41_dev(self):
        self.run_case("AX41 DEV")

    def test_rf(self):
        self.run_case("RF")

    def test_rf_dev(self):
        self.run_case("RF DEV")

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
