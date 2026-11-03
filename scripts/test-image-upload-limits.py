#!/usr/bin/env python3
"""Exercise real nginx route selection using synthetic payloads and a mock gateway."""

import argparse
import contextlib
import http.server
import re
import socket
import subprocess
import tempfile
import threading
import time
from pathlib import Path

from jinja2 import Environment, FileSystemLoader
import yaml


INFRA = Path(__file__).resolve().parent.parent
MIB = 1024 * 1024


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


class Gateway(http.server.BaseHTTPRequestHandler):
    requests = []

    def do_POST(self):
        remaining = int(self.headers["Content-Length"])
        total = remaining
        while remaining:
            block = self.rfile.read(min(remaining, 65536))
            if not block:
                break
            remaining -= len(block)
        self.requests.append((self.path, total - remaining))
        self.send_response(204)
        self.end_headers()

    def log_message(self, *args):
        pass


def render_macro(template, macro_names, call, **values):
    environment = Environment(loader=FileSystemLoader(str(INFRA / "ansible/roles")))
    environment.filters["bool"] = bool
    names = ", ".join(macro_names)
    source = "{% from '" + template + "' import " + names + " with context %}" + call
    return environment.from_string(source).render(**values)


def render_scoped_block(task_path, **values):
    document = yaml.safe_load((INFRA / task_path).read_text())
    task = next(item for item in document[0]["block"] if "ansible.builtin.blockinfile" in item)
    return Environment().from_string(task["ansible.builtin.blockinfile"]["block"]).render(**values)


def route_limits(content):
    return dict(re.findall(r"location\s+([^\n{]+?)\s*\{\s*client_max_body_size\s+(\w+);", content))


def check_full_templates():
    """Render enabled and rollback states, including unrelated safety includes."""
    env = Environment(loader=FileSystemLoader([
        str(INFRA / "ansible/roles"),
        str(INFRA / "ansible/roles/rf-edge-proxy/templates"),
    ]))
    env.filters["bool"] = bool
    marker = "schedule/lessons/[^/]+/image-page"
    ax_routes = [
        {"hostname": "online.honey.school", "kind": "online", "upstream": "127.0.0.1:1"},
        {"hostname": "dev.online.honey.school", "kind": "online", "upstream": "127.0.0.1:2"},
        {"hostname": "key.honey.school", "kind": "keyboard", "upstream": "127.0.0.1:3"},
    ]
    rf_routes = [
        {"hostname": "online.honeyschool.ru", "kind": "application", "tls_enabled": True},
        {"hostname": "dev.online.honeyschool.ru", "kind": "application", "tls_enabled": True},
        {"hostname": "key.honeyschool.ru", "kind": "application", "tls_enabled": True},
    ]
    for prod_enabled, dev_enabled in ((True, True), (False, True), (True, False)):
        ax = env.get_template("edge-proxy/templates/playsay-honey.conf.j2").render(
            edge_root_certificate={"stat": {"exists": True}},
            edge_root_site={"hostname": "honey.school", "certificate_name": "honey.school", "document_root": "/tmp"},
            edge_certificate={"stat": {"exists": True}},
            edge_certificate_name="test",
            edge_tls_protocols="TLSv1.2",
            edge_routes=ax_routes,
            image_upload_routes_prod_enabled=prod_enabled,
            image_upload_routes_dev_enabled=dev_enabled,
        )
        rf = env.get_template("rf-edge-proxy/templates/playsay-honey-rf-edge.conf.j2").render(
            rf_edge_routes=rf_routes,
            rf_edge_certificate_directory="/tmp/cert",
            rf_edge_tls_enabled=True,
            rf_edge_tls_protocols="TLSv1.2",
            rf_edge_origin_address="127.0.0.1",
            rf_edge_acme_webroot="/tmp/acme",
            image_upload_routes_prod_enabled=prod_enabled,
            image_upload_routes_dev_enabled=dev_enabled,
        )
        for label, content, names in (
            ("AX41", ax, ["online.honey.school", "dev.online.honey.school", "key.honey.school"]),
            ("RF", rf, ["online.honeyschool.ru", "dev.online.honeyschool.ru", "key.honeyschool.ru"]),
        ):
            for index, name in enumerate(names):
                servers = [part for part in content.split("server {") if "server_name " + name + ";" in part and "listen 443 ssl" in part]
                assert len(servers) == 1, (label, name, "missing HTTPS server")
                server = servers[0]
                assert (marker in server) == ([prod_enabled, dev_enabled, False][index]), (label, name, "image route scope")
                assert ("location = /api/worksheet-imports" in server) == ([prod_enabled, dev_enabled, False][index]), (label, name, "worksheet route scope")
                assert ("location = /api/materials/ai-draft" in server) == ([prod_enabled, dev_enabled, False][index]), (label, name, "photo draft route scope")
                if index < 2:
                    assert "honey-school-maintenance-admission" in server, (label, name, "maintenance admission")
    print("Full AX41 and RF templates preserve route scope and maintenance includes in enabled and rollback states")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform-dir", required=True, type=Path)
    parser.add_argument("--nginx-binary", required=True, type=Path)
    args = parser.parse_args()

    check_full_templates()

    web_port, ax_port, rf_port, ax_scoped_port, rf_scoped_port = (free_port() for _ in range(5))
    gateway = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Gateway)
    threading.Thread(target=gateway.serve_forever, daemon=True).start()
    gateway_port = gateway.server_port

    web = (args.platform_dir / "frontend/web-app/nginx.conf").read_text()
    web = web.replace("listen 80;", f"listen 127.0.0.1:{web_port};", 1)
    for name in ("api-gateway", "media-service", "ai-tutor-service", "vocabulary-service"):
        web = web.replace("http://" + name, f"http://127.0.0.1:{gateway_port}")

    ax = render_macro(
        "edge-proxy/templates/playsay-honey.conf.j2",
        ["html_game_upload_locations", "image_upload_locations"],
        "{{ html_game_upload_locations(route, 'https') }}{{ image_upload_locations(route, 'https') }}",
        edge_root_certificate={"stat": {"exists": False}},
        edge_root_site={"hostname": "local", "document_root": "/tmp"},
        edge_routes=[],
        route={"upstream": f"127.0.0.1:{web_port}"},
    )
    rf = render_macro(
        "rf-edge-proxy/templates/playsay-honey-rf-edge.conf.j2",
        ["html_game_upload_locations", "image_upload_locations"],
        "{{ html_game_upload_locations(route, 'https') }}{{ image_upload_locations(route, 'https') }}",
        rf_edge_routes=[],
        rf_edge_origin_address=f"127.0.0.1:{ax_port}",
        route={"hostname": "online.honeyschool.ru", "origin_hostname": "online.honey.school"},
    )
    ax_scoped = render_scoped_block(
        "ansible/roles/edge-proxy/tasks/image-upload-routes.yaml",
        ax41_image_target_upstream=f"127.0.0.1:{web_port}",
    )
    rf_scoped = render_scoped_block(
        "ansible/roles/rf-edge-proxy/tasks/image-upload-routes.yaml",
        rf_edge_origin_address=f"127.0.0.1:{ax_scoped_port}",
    )
    for name, template, scoped in (("AX41", ax, ax_scoped), ("RF", rf, rf_scoped)):
        expected = route_limits(scoped)
        assert len(expected) == 3, (name, "scoped route count", expected)
        assert {key: route_limits(template).get(key) for key in expected} == expected, (name, "scoped/template mismatch")
    # The size and route test uses loopback HTTP; real RF-to-AX41 TLS remains
    # covered by release acceptance and is not simulated by this fixture.
    rf = rf.replace("proxy_pass https://", "proxy_pass http://")
    rf = re.sub(r"(?m)^\s*proxy_ssl_[^\n]*\n", "", rf)
    rf_scoped = rf_scoped.replace("proxy_pass https://", "proxy_pass http://")
    rf_scoped = re.sub(r"(?m)^\s*(?:proxy_ssl_|sub_filter)[^\n]*\n", "", rf_scoped)

    with tempfile.TemporaryDirectory(prefix="image-upload-nginx-") as directory:
        root = Path(directory)
        for name in ("client", "proxy"):
            (root / name).mkdir()
        config = f"""
daemon off;
pid {root}/nginx.pid;
error_log {root}/error.log notice;
events {{ worker_connections 128; }}
http {{
    access_log off;
    client_body_temp_path {root}/client;
    proxy_temp_path {root}/proxy;
    map $http_upgrade $playsay_connection_upgrade {{ default upgrade; "" close; }}
    map $http_upgrade $playsay_rf_connection_upgrade {{ default upgrade; "" close; }}
    map $remote_addr $honey_school_client_ip {{ default $remote_addr; }}
    {web}
    server {{
        listen 127.0.0.1:{ax_port};
        {ax}
        location / {{ proxy_pass http://127.0.0.1:{web_port}; }}
    }}
    server {{
        listen 127.0.0.1:{rf_port};
        {rf}
        location / {{ proxy_pass http://127.0.0.1:{ax_port}; }}
    }}
    server {{
        listen 127.0.0.1:{ax_scoped_port};
        {ax_scoped}
        location / {{ proxy_pass http://127.0.0.1:{web_port}; }}
    }}
    server {{
        listen 127.0.0.1:{rf_scoped_port};
        {rf_scoped}
        location / {{ proxy_pass http://127.0.0.1:{ax_scoped_port}; }}
    }}
}}
"""
        config_path = root / "nginx.conf"
        config_path.write_text(config)
        subprocess.run([str(args.nginx_binary), "-t", "-c", str(config_path)], check=True)
        nginx = subprocess.Popen([str(args.nginx_binary), "-c", str(config_path)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        try:
            for _ in range(100):
                if nginx.poll() is not None:
                    raise RuntimeError("nginx exited: " + nginx.stderr.read().decode())
                try:
                    with socket.create_connection(("127.0.0.1", rf_port), timeout=0.1):
                        break
                except OSError:
                    time.sleep(0.05)
            else:
                raise RuntimeError("nginx did not start")

            def request(port, path, size, expected):
                payload = root / "payload"
                with payload.open("wb") as stream:
                    stream.truncate(size)
                result = subprocess.run(
                    ["curl", "-sS", "--max-time", "25", "-o", "/dev/null", "-w", "%{http_code}",
                     "-X", "POST", "--data-binary", "@" + str(payload), f"http://127.0.0.1:{port}{path}"],
                    capture_output=True, text=True, check=True,
                ).stdout
                assert result == str(expected), f"{path}, {size} bytes: expected {expected}, got {result}"
                print(f"{path}: {size} request bytes -> {result}")

            incident = "/api/schedule/lessons/lesson-1/image-page"
            request(rf_port, incident, 1_049_799, 204)
            assert Gateway.requests[-1] == ("/schedule/lessons/lesson-1/image-page", 1_049_799)
            request(ax_port, incident, 1_049_799, 204)
            request(rf_port, incident, 20 * MIB + 2048, 204)
            request(rf_port, "/api/materials/material-1/image-page", 2 * MIB, 204)
            request(rf_port, "/api/materials/material-1/assets/images", 2 * MIB, 204)
            request(rf_port, incident, 21 * MIB + 1, 413)
            request(ax_port, incident, 21 * MIB + 1, 413)
            request(web_port, incident, 21 * MIB + 1, 413)
            request(rf_scoped_port, incident, 20 * MIB + 2048, 204)
            request(rf_scoped_port, incident, 21 * MIB + 1, 413)
            request(rf_port, "/api/worksheet-imports", 20 * MIB + 2048, 204)
            assert Gateway.requests[-1] == ("/worksheet-imports", 20 * MIB + 2048)
            request(rf_port, "/api/worksheet-imports", 128 * MIB + 2048, 204)
            request(rf_port, "/api/worksheet-imports", 129 * MIB + 1, 413)
            request(ax_port, "/api/worksheet-imports", 129 * MIB + 1, 413)
            request(web_port, "/api/worksheet-imports", 129 * MIB + 1, 413)
            request(rf_port, "/api/materials/ai-draft", 2_500_100, 204)
            assert Gateway.requests[-1] == ("/materials/ai-draft", 2_500_100)
            request(rf_port, "/api/materials/ai-draft", 3 * MIB + 1, 413)
            request(ax_port, "/api/materials/ai-draft", 3 * MIB + 1, 413)
            request(web_port, "/api/materials/ai-draft", 3 * MIB + 1, 413)
            request(rf_port, "/api/worksheet-imports/other", MIB + 1, 413)
            request(rf_port, "/api/me", MIB + 1, 413)
            request(rf_port, "/api/materials/material-1/assets/html-games", 14 * MIB, 204)
        finally:
            nginx.terminate()
            with contextlib.suppress(subprocess.TimeoutExpired):
                nginx.wait(timeout=5)
            if nginx.poll() is None:
                nginx.kill()
                nginx.wait()
            gateway.shutdown()
            gateway.server_close()


if __name__ == "__main__":
    main()
