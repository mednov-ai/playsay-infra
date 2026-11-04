"""Run inside the no-secret DEV probe pod; print only connectivity outcomes."""

import http.client
import json
import socket
import sys

IDENTITY = "keycloak.keycloak.svc.cluster.local"
DENIED = (
    ("playsay-postgres-rw.playsay-data.svc.cluster.local", 5432),
    ("collaboration-service.playsay-dev.svc.cluster.local", 80),
)


def resolve(host, port):
    records = socket.getaddrinfo(host, port, family=socket.AF_INET, type=socket.SOCK_STREAM)
    if not records:
        raise RuntimeError("Required DEV service DNS is unavailable")


def cannot_connect(host, port):
    try:
        with socket.create_connection((host, port), timeout=3):
            return False
    except OSError:
        return True


def main():
    resolve(IDENTITY, 80)
    for host, port in DENIED:
        resolve(host, port)
    connection = http.client.HTTPConnection(IDENTITY, 80, timeout=5)
    try:
        connection.request("GET", "/keycloak/realms/playsay/protocol/openid-connect/certs")
        response = connection.getresponse()
        if response.status != 200:
            raise RuntimeError("DEV identity JWKS is not reachable")
        response.read(65536)
    finally:
        connection.close()
    if not all(cannot_connect(host, port) for host, port in DENIED):
        raise RuntimeError("A shared DEV service is reachable from the fixture")
    print(json.dumps({"devIdentity": "reachable", "sharedDatabase": "unreachable", "sharedCollaboration": "unreachable"}))


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
