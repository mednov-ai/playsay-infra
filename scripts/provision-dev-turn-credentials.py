#!/usr/bin/env python3
"""Create matching dev-only TURN credentials; preserve existing values, never rotate."""
import argparse
import base64
import json
import re
import secrets
import subprocess

EDGE = "94.102.89.213"
GUEST = "10.60.0.30"
SECRET_FILE = "/etc/honeyschool/secrets/dev-turn-rest-secret"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ssh-key", required=True)
    args = parser.parse_args()
    common = ["ssh", "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes", "-i", args.ssh_key]

    def run(command, data=None):
        result = subprocess.run(command, input=data, capture_output=True, timeout=45)
        if result.returncode:
            raise RuntimeError("Protected dev TURN operation failed")
        return result.stdout

    edge = common + ["root@" + EDGE]
    # ProxyCommand is interpreted by a shell, so quote the user-supplied key path.
    import shlex
    proxy = "ssh -o IdentitiesOnly=yes -i " + shlex.quote(args.ssh_key) + " -W %h:%p root@65.109.55.110"
    guest = common + ["-o", "ProxyCommand=" + proxy, "playsay@" + GUEST]
    run(guest + ["test $(hostname) = playsay-dev"])
    kubectl = "sudo env KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n playsay-dev "
    current = run(guest + [kubectl + "get secret rf-media-relay-auth --ignore-not-found -o json"])
    guest_value = base64.b64decode(json.loads(current)["data"]["shared-secret"]) if current.strip() else None
    edge_value = run(edge + ["if test -e " + SECRET_FILE + "; then "
                            "test $(stat -c %a:%U:%G " + SECRET_FILE + ") = 600:root:root && cat "
                            + SECRET_FILE + "; fi"]).strip() or None
    for value in (guest_value, edge_value):
        if value is not None and not re.fullmatch(b"[0-9a-f]{64}", value):
            raise ValueError("Unexpected credential format")
    if guest_value is not None and edge_value is not None and guest_value != edge_value:
        raise ValueError("Existing credentials differ; refusing rotation")
    value = guest_value or edge_value or secrets.token_hex(32).encode()
    if edge_value is None:
        run(edge + ["install -d -o root -g root -m 0700 /etc/honeyschool/secrets; "
                    "umask 077; set -C; cat > " + SECRET_FILE], value)
    if guest_value is None:
        # Secret material goes over stdin, never through process arguments or logs.
        manifest = {"apiVersion": "v1", "kind": "Secret", "type": "Opaque",
                    "metadata": {"name": "rf-media-relay-auth", "namespace": "playsay-dev",
                                 "labels": {"app.kubernetes.io/managed-by": "playsay-infra"}},
                    "data": {"shared-secret": base64.b64encode(value).decode()}}
        run(guest + [kubectl + "create -f -"], json.dumps(manifest).encode())
    verified = json.loads(run(guest + [kubectl + "get secret rf-media-relay-auth -o json"]))
    if base64.b64decode(verified["data"]["shared-secret"]) != value:
        raise ValueError("Credential verification failed")
    print("Dev TURN credentials match; existing values preserved; values suppressed")


if __name__ == "__main__":
    try:
        main()
    except (KeyError, ValueError, RuntimeError, subprocess.SubprocessError):
        raise SystemExit("Dev TURN credential provisioning stopped; no values disclosed") from None
