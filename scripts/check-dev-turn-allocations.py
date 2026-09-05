#!/usr/bin/env python3
"""Run on the RF edge: bounded dev allocation checks, no credential/log output."""
import base64
import hashlib
import hmac
import os
import secrets
import socket
import ssl
import struct
import time
from pathlib import Path

HOST = "dev.turn.honeyschool.ru"
COOKIE = 0x2112A442


def attr(kind, value):
    return struct.pack("!HH", kind, len(value)) + value + b"\0" * (-len(value) % 4)


def request(kind, attributes, key=None):
    tid = secrets.token_bytes(12)
    body = b"".join(attributes)
    header = struct.pack("!HHI12s", kind, len(body) + (24 if key else 0), COOKIE, tid)
    if key:
        body += attr(8, hmac.new(key, header + body, hashlib.sha1).digest())
    return header + body, tid


def exchange(conn, packet, tid, udp):
    conn.sendall(packet)
    if udp:
        data = conn.recv(4096)
    else:
        def read(n):
            value = b""
            while len(value) < n:
                part = conn.recv(n - len(value))
                if not part:
                    raise ValueError("Truncated TURN response")
                value += part
            return value
        data = read(20)
        data += read(struct.unpack("!H", data[2:4])[0])
    kind, length, cookie, response_tid = struct.unpack("!HHI12s", data[:20])
    assert cookie == COOKIE and response_tid == tid and len(data) == length + 20
    fields = {}
    offset = 20
    while offset < len(data):
        k, size = struct.unpack("!HH", data[offset:offset + 4])
        fields[k] = data[offset + 4:offset + 4 + size]
        offset += 4 + size + (-size % 4)
    return kind, fields


def main():
    assert os.geteuid() == 0
    source = Path("/etc/honeyschool/secrets/dev-turn-rest-secret")
    assert source.stat().st_mode & 0o777 == 0o600
    secret = source.read_bytes().strip()
    assert len(secret) == 64
    username = (str(int(time.time()) + 120) + ":dev-check-" + secrets.token_hex(8)).encode()
    password = base64.b64encode(hmac.new(secret, username, hashlib.sha1).digest())
    for transport in ("UDP", "TCP", "TLS"):
        udp = transport == "UDP"
        conn = socket.socket(socket.AF_INET, socket.SOCK_DGRAM if udp else socket.SOCK_STREAM)
        conn.settimeout(5)
        if transport == "TLS":
            conn = ssl.create_default_context().wrap_socket(conn, server_hostname=HOST)
        with conn:
            conn.connect((HOST, 5350 if transport == "TLS" else 3479))
            allocation = [attr(0x19, b"\x11\0\0\0"), attr(0x0D, struct.pack("!I", 30))]
            kind, fields = exchange(conn, *request(3, allocation), udp)
            assert kind == 0x113 and fields[9][2:4] == b"\x04\x01"
            realm, nonce = fields[0x14], fields[0x15]
            auth = [attr(6, username), attr(0x14, realm), attr(0x15, nonce)]
            wrong = hashlib.md5(username + b":" + realm + b":invalid").digest()
            kind, fields = exchange(conn, *request(3, allocation + auth, wrong), udp)
            assert kind == 0x113 and fields[9][2:4] == b"\x04\x01"
            key = hashlib.md5(username + b":" + realm + b":" + password).digest()
            kind, fields = exchange(conn, *request(3, allocation + auth, key), udp)
            assert kind == 0x103
            relay = fields[0x16]
            port = struct.unpack("!H", relay[2:4])[0] ^ (COOKIE >> 16)
            assert relay[1] == 1 and 49300 <= port <= 49399
            kind, _ = exchange(conn, *request(4, [attr(0x0D, b"\0\0\0\0")] + auth, key), udp)
            assert kind == 0x104
        print("PASS dev TURN " + transport + " invalid-auth rejection, allocation range and release")
    print("Allocation checks only; bidirectional SFU media acceptance remains required")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        raise SystemExit("Dev TURN allocation check failed; private data suppressed") from None
