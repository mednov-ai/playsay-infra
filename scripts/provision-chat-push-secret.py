#!/usr/bin/env python3
"""Provision environment-local VAPID; stdout contains only the public key."""
import argparse
import base64
import json
import subprocess
import sys

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec


def encoded(value):
    return base64.urlsafe_b64encode(value).decode().rstrip("=")


def public_key(private):
    return encoded(private.public_key().public_bytes(
        serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint))


def provision(namespace, subject):
    if namespace not in ("playsay-dev", "playsay-prod"):
        raise ValueError("unsupported namespace")
    if not subject.startswith(("mailto:", "https://")):
        raise ValueError("subject must be mailto or HTTPS")
    command = ["kubectl", "-n", namespace]
    existing = subprocess.run(command + ["get", "secret", "playsay-chat-push",
        "--ignore-not-found", "-o", "json"], check=True, capture_output=True, text=True)
    if existing.stdout.strip():
        data = json.loads(existing.stdout)["data"]
        raw = base64.b64decode(data["private-key"]).decode()
        scalar = base64.urlsafe_b64decode(raw + "=" * (-len(raw) % 4))
        if len(scalar) != 32 or not base64.b64decode(data["subject"]):
            raise ValueError("incomplete existing secret")
        return public_key(ec.derive_private_key(int.from_bytes(scalar, "big"), ec.SECP256R1()))
    private = ec.generate_private_key(ec.SECP256R1())
    public = public_key(private)
    secret = {
        "apiVersion": "v1", "kind": "Secret", "type": "Opaque",
        "metadata": {"name": "playsay-chat-push", "namespace": namespace,
            "labels": {"app.kubernetes.io/managed-by": "playsay-infra"}},
        "stringData": {
            "private-key": encoded(private.private_numbers().private_value.to_bytes(32, "big")),
            "subject": subject,
        },
    }
    # create, not apply: a concurrent existing secret fails closed, never rotates keys.
    subprocess.run(command + ["create", "-f", "-"], input=json.dumps(secret),
        check=True, capture_output=True, text=True)
    return public


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--namespace", required=True, choices=["playsay-dev", "playsay-prod"])
    parser.add_argument("--subject", required=True)
    args = parser.parse_args()
    try:
        print(provision(args.namespace, args.subject))
    except Exception:
        # kubectl/provider exceptions can contain the stdin Secret: never echo them.
        print("VAPID provisioning failed; existing keys were not replaced", file=sys.stderr)
        sys.exit(1)
