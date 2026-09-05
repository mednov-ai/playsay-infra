#!/usr/bin/env python3
"""Read-only parity gate for the two isolated TURN services on the RF edge.

No secret values, secret-derived values, addresses or raw configuration are emitted.
This is configuration evidence, not an allocation/media or ISP reachability test.
"""
import argparse
import subprocess

RUNNER = r'''
import json, pathlib, sys

def read(path):
    result = {}
    for line in pathlib.Path(path).read_text().splitlines():
        line = line.strip()
        if not line or line.startswith('#'): continue
        key, separator, value = line.partition('=')
        result[key] = value if separator else True
    return result
try:
    dev = read('/etc/honeyschool/dev-turn/turnserver.conf')
    prod = read('/etc/turnserver.conf')
    checks = {}
    for name in ['use-auth-secret', 'no-multicast-peers', 'no-loopback-peers', 'no-cli', 'no-tlsv1', 'no-tlsv1_1']:
        checks[name] = dev.get(name) is True and prod.get(name) is True
    for name, value in [('total-quota','8'),('user-quota','4'),('stale-nonce','600')]:
        checks[name] = dev.get(name) == prod.get(name) == value
    for name, d, p in [('listening-port','3479','3478'), ('tls-listening-port','5350','5349'), ('min-port','49300','49152'), ('max-port','49399','49251')]:
        checks[name] = dev.get(name) == d and prod.get(name) == p
    checks['independent-secrets'] = bool(dev.get('static-auth-secret')) and bool(prod.get('static-auth-secret')) and dev['static-auth-secret'] != prod['static-auth-secret']
    checks['independent-certificates'] = bool(dev.get('cert')) and bool(prod.get('cert')) and dev['cert'] != prod['cert']
    checks['dev-peer-isolation-options'] = dev.get('no-tcp-relay') is True and dev.get('no-dtls') is True
    print(json.dumps({'checks': checks, 'configurationParity': all(checks.values()), 'mediaAcceptance': 'separate-browser-and-network-gate'}))
    sys.exit(0 if all(checks.values()) else 1)
except Exception:
    print('TURN parity audit unavailable; raw exception suppressed', file=sys.stderr)
    sys.exit(2)
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ssh-key', required=True)
    args = parser.parse_args()
    return subprocess.run(['ssh', '-i', args.ssh_key, '-o', 'IdentitiesOnly=yes',
                           '-o', 'BatchMode=yes', 'root@94.102.89.213', 'python3', '-'],
                          input=RUNNER, text=True, check=False).returncode


if __name__ == '__main__':
    raise SystemExit(main())
