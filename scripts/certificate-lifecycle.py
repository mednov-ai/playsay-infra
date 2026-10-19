#!/usr/bin/env python3
"""Owned certificate renewal and health. Never logs provider output or key data."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import socket
import ssl
import subprocess
import tempfile
import time

OWNERS = {'ax41', 'selectel'}
NAME = re.compile(r'[a-z0-9][a-z0-9.-]*\.(?:school|ru)\Z')


def load_inventory(path):
    data = json.loads(Path(path).read_text())
    if data.get('version') != 1 or not data.get('certificates'):
        raise ValueError('inventory_version')
    seen = set()
    for item in data['certificates']:
        key = (item['owner'], item['lineage'])
        if key in seen or item['owner'] not in OWNERS or not NAME.fullmatch(item['lineage']):
            raise ValueError('inventory_identity')
        seen.add(key)
        if item['method'] != 'webroot' or item['activation'] not in {'nginx', 'deferred-turn'}:
            raise ValueError('inventory_policy')
        if not item['names'] or not item['probes']:
            raise ValueError('inventory_coverage')
        if {p['hostname'] for p in item['probes']} != set(item['names']):
            raise ValueError('inventory_coverage')
        for probe in item['probes']:
            if not NAME.fullmatch(probe['hostname']) or not (probe['hostname'] in {'honey.school', 'honeyschool.ru'} or probe['hostname'].endswith(('.honey.school', '.honeyschool.ru'))):
                raise ValueError('inventory_probe')
            if probe['connect'] != probe['hostname'] and not (item['owner'] == 'ax41' and probe['connect'] == '65.109.55.110'):
                raise ValueError('inventory_destination')
            if probe['port'] not in {443, 5349, 5350}:
                raise ValueError('inventory_port')
        if item['activation'] == 'deferred-turn' and not item.get('pending_marker', '').startswith('/run/'):
            raise ValueError('inventory_activation')
    return data['certificates']


def atomic_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, temporary = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as target:
            json.dump(value, target)
            target.write('\n')
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def command(args, timeout=300):
    # Raw Certbot/OpenSSL output can contain URLs/account information. Suppress it.
    return subprocess.run(args, capture_output=True, timeout=timeout, check=False)


def disk_certificate(path, names, ca_file):
    pem = Path(path).read_text()
    leaf = re.search(r'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----', pem, re.S)
    if not leaf:
        raise ValueError('certificate_format')
    der = ssl.PEM_cert_to_DER_cert(leaf.group())
    result = command(['openssl', 'x509', '-in', str(path), '-noout', '-enddate'])
    expiry = ssl.cert_time_to_seconds(result.stdout.decode().strip().split('=', 1)[1])
    valid = command(['openssl', 'verify', '-CAfile', ca_file, '-untrusted', str(path), str(path)]).returncode == 0
    for name in names:
        valid = valid and command(['openssl', 'verify', '-verify_hostname', name, '-CAfile', ca_file, '-untrusted', str(path), str(path)]).returncode == 0
    return {'expiry': expiry, 'fingerprint': hashlib.sha256(der).hexdigest(), 'valid': valid}


def served_certificate(probe, ca_file):
    context = ssl.create_default_context(cafile=ca_file)
    with socket.create_connection((probe['connect'], probe['port']), timeout=5) as tcp:
        with context.wrap_socket(tcp, server_hostname=probe['hostname']) as tls:
            return {'expiry': ssl.cert_time_to_seconds(tls.getpeercert()['notAfter']),
                    'fingerprint': hashlib.sha256(tls.getpeercert(binary_form=True)).hexdigest()}


def health(item, previous, cert_root, ca_file, now):
    result = {'checked_at': now, 'healthy': 0, 'matching': 0, 'disk_expiry': 0,
              'served_expiry': 0, 'mismatch_since': 0, 'pending_since': 0}
    marker = Path(item.get('pending_marker', '/nonexistent-certificate-marker'))
    if item['activation'] == 'deferred-turn' and marker.exists():
        result['pending_since'] = previous.get('pending_since') or min(marker.stat().st_mtime, now)
    try:
        disk = disk_certificate(cert_root / 'live' / item['lineage'] / 'fullchain.pem', item['names'], ca_file)
        result['disk_expiry'] = disk['expiry']
        served = [served_certificate(probe, ca_file) for probe in item['probes']]
        result['served_expiry'] = min(p['expiry'] for p in served)
        result['matching'] = int(all(p['fingerprint'] == disk['fingerprint'] for p in served))
        result['healthy'] = int(disk['valid'] and disk['expiry'] > now and result['served_expiry'] > now)
        if not result['matching']:
            result['mismatch_since'] = previous.get('mismatch_since') or now
    except (OSError, ValueError, KeyError, IndexError, ssl.SSLError, subprocess.SubprocessError):
        # Retain a fresh explicit failure, never the previous healthy result.
        pass
    return result


def renewal_check(item, cert_root):
    config = cert_root / 'renewal' / (item['lineage'] + '.conf')
    if not config.exists() or not (cert_root / 'live' / item['lineage'] / 'fullchain.pem').exists():
        raise ValueError('missing_owned_lineage')
    if not re.search(r'^authenticator\s*=\s*webroot\s*$', config.read_text(), re.M):
        raise ValueError('unexpected_authenticator')


def renew_one(item, cert_root, ca_file, now, rehearsal=False):
    result = {'checked_at': now, 'success': 0, 'outcome': 'failed'}
    try:
        renewal_check(item, cert_root)
        before = disk_certificate(cert_root / 'live' / item['lineage'] / 'fullchain.pem', item['names'], ca_file)
        args = ['certbot', 'renew', '--non-interactive', '--no-random-sleep-on-renew', '--cert-name', item['lineage']]
        if rehearsal:
            args += ['--dry-run', '--no-directory-hooks', '--pre-hook', '/usr/bin/true',
                     '--post-hook', '/usr/bin/true', '--deploy-hook', '/usr/bin/true']
        run = command(args)
        if run.returncode != 0:
            return result
        after = disk_certificate(cert_root / 'live' / item['lineage'] / 'fullchain.pem', item['names'], ca_file)
        if rehearsal and before['fingerprint'] != after['fingerprint']:
            return result
        changed = before['fingerprint'] != after['fingerprint']
        if not rehearsal and (not after['valid'] or after['expiry'] <= now):
            return result
        result.update(success=1, outcome='rehearsed' if rehearsal else ('renewed' if changed else 'not_due'))
        if changed:
            result['renewed_at'] = now
    except (OSError, ValueError, KeyError, IndexError, subprocess.SubprocessError):
        pass
    return result


def activate(item, cert_root, ca_file):
    if item['activation'] == 'deferred-turn':
        # Only record pending work; never restart a relay or copy its private key.
        marker = Path(item['pending_marker'])
        if not marker.exists():
            marker.touch()
        return True
    try:
        disk = disk_certificate(cert_root / 'live' / item['lineage'] / 'fullchain.pem', item['names'], ca_file)
        if all(served_certificate(p, ca_file)['fingerprint'] == disk['fingerprint'] for p in item['probes']):
            return True  # an existing deploy hook already activated the chain
    except (OSError, ValueError, ssl.SSLError, subprocess.SubprocessError):
        pass
    return command(['nginx', '-t']).returncode == 0 and command(['systemctl', 'reload', 'nginx']).returncode == 0


def process_renewals(items, state, cert_root, ca_file, now, rehearsal=False, include_unmanaged=False):
    kind = 'rehearsal' if rehearsal else 'renewal'
    for item in items:
        row = state.setdefault(item['lineage'], {})
        result = renew_one(item, cert_root, ca_file, now, rehearsal)
        previous = row.get(kind, {})
        result['activation_success'] = previous.get('activation_success', 1)
        if not rehearsal and result.get('outcome') == 'renewed':
            try:
                result['activation_success'] = int(activate(item, cert_root, ca_file))
            except (OSError, ValueError, subprocess.SubprocessError):
                result['activation_success'] = 0
        result['failure_since'] = (previous.get('failure_since') or now) if not result['success'] else 0
        result['last_renewed_at'] = result.get('renewed_at', previous.get('last_renewed_at', 0))
        row[kind] = result
    if include_unmanaged and not rehearsal:
        # The pre-existing package job renewed all lineages. Preserve that coverage
        # without changing foreign configs or exporting their names/data.
        owned = {item['lineage'] for item in items}
        for config in sorted((cert_root / 'renewal').glob('*.conf')):
            if config.stem not in owned:
                try:
                    if command(['certbot', 'renew', '--non-interactive', '--no-random-sleep-on-renew', '--cert-name', config.stem]).returncode:
                        state['_unmanaged_failure'] = True
                except (OSError, subprocess.SubprocessError):
                    state['_unmanaged_failure'] = True


def metrics(items, state):
    result = []
    for item in items:
        labels = '{owner="%s",lineage="%s",certificate_environment="%s",activation="%s"}' % (item['owner'], item['lineage'], item['environment'], item['activation'])
        row = state.get(item['lineage'], {})
        for field in ['checked_at', 'healthy', 'matching', 'disk_expiry', 'served_expiry', 'mismatch_since', 'pending_since']:
            result.append('hs_certificate_health_%s%s %s' % (field, labels, row.get('health', {}).get(field, 0)))
        for kind in ['renewal', 'rehearsal']:
            for field in ['checked_at', 'success', 'failure_since', 'last_renewed_at', 'activation_success']:
                result.append('hs_certificate_%s_%s%s %s' % (kind, field, labels, row.get(kind, {}).get(field, 1 if field == 'activation_success' else 0)))
    return '\n'.join(result) + '\n'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=['validate', 'health', 'renew', 'rehearse', 'publish'])
    parser.add_argument('--owner', choices=sorted(OWNERS), required=True)
    parser.add_argument('--inventory', default='/etc/honeyschool/certificates/inventory.json')
    parser.add_argument('--state-dir', default='/var/lib/honeyschool/certificates')
    parser.add_argument('--cert-root', default='/etc/letsencrypt')
    parser.add_argument('--ca-file', default='/etc/ssl/certs/ca-certificates.crt')
    parser.add_argument('--include-unmanaged', action='store_true')
    parser.add_argument('--push-url')
    parser.add_argument('--curl-config')
    parser.add_argument('--resolve')
    args = parser.parse_args()
    items = [item for item in load_inventory(args.inventory) if item['owner'] == args.owner]
    if not items:
        raise ValueError('empty_owner')
    if args.mode == 'validate':
        print('certificate_inventory_valid owner=%s count=%d' % (args.owner, len(items)))
        return 0
    directory = Path(args.state_dir)
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (directory / 'lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return 0  # no timestamp update: prolonged contention becomes stale
        state_file = directory / 'state.json'
        state = json.loads(state_file.read_text()) if state_file.exists() else {}
        now = int(time.time())
        if args.mode in {'renew', 'rehearse'}:
            state.pop('_unmanaged_failure', None)
            process_renewals(items, state, Path(args.cert_root), args.ca_file, now,
                             args.mode == 'rehearse', args.include_unmanaged)
        if args.mode in {'health', 'renew'}:
            for item in items:
                row = state.setdefault(item['lineage'], {})
                row['health'] = health(item, row.get('health', {}), Path(args.cert_root), args.ca_file, now)
                if row['health']['healthy'] and row['health']['matching']:
                    row.setdefault('renewal', {})['activation_success'] = 1
        if args.mode != 'publish':
            atomic_json(state_file, state)
        if args.mode == 'publish':
            if not args.push_url:
                raise ValueError('missing_metrics_destination')
            with tempfile.NamedTemporaryFile(dir=directory, mode='w') as output:
                output.write(metrics(items, state)); output.flush()
                cmd = ['curl', '--silent', '--fail', '--connect-timeout', '5', '--max-time', '15']
                if args.curl_config:
                    cmd += ['--config', args.curl_config]
                if args.resolve:
                    cmd += ['--resolve', args.resolve]
                cmd += ['--no-insecure', '-H', 'Content-Type: text/plain', '--data-binary', '@'+output.name, args.push_url]
                return int(command(cmd, timeout=20).returncode != 0)
        kind = 'rehearsal' if args.mode == 'rehearse' else ('renewal' if args.mode == 'renew' else 'health')
        field = 'healthy' if kind == 'health' else 'success'
        return int((args.mode == 'renew' and bool(state.get('_unmanaged_failure'))) or any(not state[i['lineage']][kind][field] for i in items))


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, IndexError, subprocess.SubprocessError):
        print('certificate_lifecycle_failed stage=configuration_or_runtime')
        raise SystemExit(1)
