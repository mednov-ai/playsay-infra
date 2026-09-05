#!/usr/bin/env python3
"""Provision only dev ingest credentials without printing their values or rotating them."""
import argparse
import secrets
import subprocess

EDGE = "94.102.89.213"
ORIGIN = "65.109.55.110"
ENV_FILE = "/etc/honeyschool/secrets/edge-log-ingest.env"
HASH_FILE = "/etc/honeyschool/secrets/edge-log-ingest.htpasswd"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ssh-key", required=True)
    args = parser.parse_args()

    def ssh(host, command, data=None):
        result = subprocess.run(
            ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-i", args.ssh_key,
             "root@" + host, command], input=data, capture_output=True, timeout=30,
        )
        if result.returncode:
            raise RuntimeError("Protected dev credential operation failed; values suppressed")
        return result.stdout

    def exists(host, path):
        return ssh(host, f"if test -f {path}; then printf yes; else printf no; fi") == b"yes"

    def create(host, path, value):
        ssh(host, f"install -d -o root -g root -m 0700 /etc/honeyschool/secrets; "
            f"umask 077; set -C; cat > {path}", value)

    def allow_nginx_hash_read():
        ssh(ORIGIN, "chown root:www-data /etc/honeyschool/secrets " + HASH_FILE +
            "; chmod 0710 /etc/honeyschool/secrets; chmod 0640 " + HASH_FILE)

    edge_exists = exists(EDGE, ENV_FILE)
    hash_exists = exists(ORIGIN, HASH_FILE)
    if hash_exists:
        if not edge_exists:
            raise RuntimeError("Origin hash exists without edge credentials; refusing rotation")
        allow_nginx_hash_read()
        print("Dev ingest credential files already exist; no rotation performed")
        return
    if edge_exists:
        data = ssh(EDGE, f"test $(stat -c %a {ENV_FILE}) = 600 && cat {ENV_FILE}")
        fields = dict(line.split(b"=", 1) for line in data.splitlines())
        username = fields[b"EDGE_LOG_INGEST_USERNAME"]
        password = fields[b"EDGE_LOG_INGEST_PASSWORD"]
    else:
        username = b"edge_dev"
        password = secrets.token_urlsafe(48).encode()
        create(EDGE, ENV_FILE, b"EDGE_LOG_INGEST_USERNAME=" + username +
               b"\nEDGE_LOG_INGEST_PASSWORD=" + password + b"\n")
    if username != b"edge_dev" or not password or len(password) > 128:
        raise RuntimeError("Unexpected protected dev credential format")
    result = subprocess.run(["htpasswd", "-niB", "edge_dev"], input=password + b"\n",
                            capture_output=True, timeout=15)
    if result.returncode:
        raise RuntimeError("Could not hash dev ingest password; values suppressed")
    create(ORIGIN, HASH_FILE, result.stdout.strip() + b"\n")
    allow_nginx_hash_read()
    print("Independent dev ingest credentials provisioned; values suppressed")


if __name__ == "__main__":
    try:
        main()
    except (KeyError, ValueError, RuntimeError, subprocess.SubprocessError):
        raise SystemExit("Dev ingest credential provisioning stopped; inspect file metadata only") from None
