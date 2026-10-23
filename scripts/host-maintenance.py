#!/usr/bin/env python3
"""Non-disruptive maintenance observer. No installation/restart capability exists.

An activity snapshot is an optional root-owned aggregate input, never authority to
restart. A future executing owner requires a separately reviewed exclusion lease.
"""
import argparse
import fcntl
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
from datetime import datetime
from zoneinfo import ZoneInfo

SOURCES = ('prod_windows', 'dev_windows', 'livekit_rooms', 'livekit_participants',
           'yjs_connections', 'game_connections', 'external_connections',
           'snapshot_queue', 'prod_turn_allocations', 'dev_turn_allocations')


def window(now, clock_ok):
    local = datetime.fromtimestamp(now, ZoneInfo('Europe/Moscow'))
    return clock_ok and 3 <= local.hour < 5


def activity_reason(samples, now, operation_bound=600):
    """Pure validation only; no sample can grant disruptive authority."""
    if not isinstance(samples, list) or len(samples) != 2:
        return 'activity_missing'
    try:
        times = []
        for sample in samples:
            if set(sample) != {'observed_at', 'counts', 'next_opening_at', 'authoritative'}:
                return 'activity_invalid'
            stamp = sample['observed_at']
            if type(stamp) is not int or not 0 <= now - stamp <= 30:
                return 'activity_stale'
            times.append(stamp)
            counts = sample['counts']
            if not isinstance(counts, dict) or sample['authoritative'] is not True or set(counts) != set(SOURCES):
                return 'activity_unknown'
            if any(type(v) is not int or v < 0 for v in counts.values()):
                return 'activity_invalid'
            if any(counts.values()):
                return 'activity_busy'
            opening = sample['next_opening_at']
            # Null/unknown is never silently interpreted as no future lesson.
            if type(opening) is not int or opening <= now + operation_bound + 120:
                return 'lesson_lookahead'
        if times[1] - times[0] < 10:
            return 'activity_spacing'
        return 'exclusion_unavailable'
    except (TypeError, KeyError, ValueError):
        return 'activity_invalid'


def capture(argv):
    result = subprocess.run(argv, capture_output=True, text=True, timeout=90, check=False)
    if result.returncode:
        raise ValueError('discovery_failed')
    return result.stdout


def discover():
    # Simulation and list-only inspection; NEVER apt upgrade/install or systemctl restart.
    packages = capture(['/usr/bin/apt-get', '-s', '-o', 'Debug::NoLocking=1', 'upgrade'])
    installation = sum(line.startswith('Inst ') for line in packages.splitlines())
    # Absence is unknown, never "zero restart debt"; do not install an inspector here.
    try:
        restarts = capture(['/usr/sbin/needrestart', '-b', '-r', 'l'])
        restart_count = sum(line.startswith('NEEDRESTART-SVC:') for line in restarts.splitlines())
    except (OSError, ValueError, subprocess.TimeoutExpired):
        restart_count = None
    return installation, restart_count


def update(previous, now, pending, reason):
    """Unknown discovery preserves existing debt; empty list-only evidence clears it."""
    state = dict(previous)
    state.update(checked_at=now, reason=reason, discovery_healthy=pending is not None and all(v is not None for v in pending))
    for stage, count in zip(('installation', 'restart'), pending or (None, None)):
        old = previous.get(stage, {})
        if count is None:
            state[stage] = old
        elif count:
            state[stage] = {'count': count, 'first_pending_at': old.get('first_pending_at', now)}
        else:
            state[stage] = {'count': 0}
    return state


def atomic(path, value):
    path = Path(path)
    with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, delete=False) as stream:
        tmp = stream.name
        os.chmod(tmp, 0o600)
        stream.write(value)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(tmp, path)


def metrics(state, owner):
    label = '{owner="' + owner + '"}'
    values = {'checked_at': state['checked_at'], 'discovery_healthy': int(state['discovery_healthy']),
              'disruptive_capability': 0}
    for stage in ('installation', 'restart'):
        debt = state.get(stage, {})
        if 'count' in debt:
            values[stage + '_pending'] = debt['count']
        if 'first_pending_at' in debt:
            values[stage + '_first_pending_at'] = debt['first_pending_at']
    for key in ('package_lists_checked_at', 'reboot_pending', 'reboot_first_pending_at', 'activity_sources_ready'):
        if key in state:
            values[key] = state[key]
    return ''.join(f'honey_host_maintenance_{key}{label} {value}\n' for key, value in values.items())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--owner', choices=('ax41', 'selectel'), required=True)
    parser.add_argument('--publish', action='store_true')
    parser.add_argument('--state-dir', default='/var/lib/honeyschool/maintenance')
    args = parser.parse_args()
    root = Path(args.state_dir)
    # Provisioned by the role, not created from an untrusted caller path.
    with (root / 'observer.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print('deferred=lock_busy')
            return 0
        now = int(time.time())
        state_path = root / 'state.json'
        # Corrupt existing debt must not be reset to "new" or silently forgotten.
        previous = json.loads(state_path.read_text()) if state_path.exists() else {}
        try:
            synced = capture(['/usr/bin/timedatectl', 'show', '-p', 'NTPSynchronized', '--value']).strip() == 'yes'
        except (OSError, ValueError, subprocess.TimeoutExpired):
            synced = False
        reason = 'outside_window' if not window(now, synced) else 'activity_missing'
        if not synced:
            reason = 'clock_unknown'
        try:
            samples = json.loads((root / 'activity.json').read_text())
            if window(now, synced):
                reason = activity_reason(samples, now)
        except (OSError, ValueError):
            pass
        try:
            pending = discover()
        except (OSError, ValueError, subprocess.TimeoutExpired):
            pending = None
            reason = 'discovery_failed'
        if pending is not None and any(v is None for v in pending):
            reason = 'discovery_incomplete'
        state = update(previous, now, pending, reason)
        state['activity_sources_ready'] = 0  # No authoritative producer/exclusion is installed.
        stamp = Path('/var/lib/apt/periodic/update-success-stamp')
        state['package_lists_checked_at'] = int(stamp.stat().st_mtime) if stamp.exists() else 0
        state['reboot_pending'] = int(Path('/run/reboot-required').exists())
        if state['reboot_pending']:
            state['reboot_first_pending_at'] = previous.get('reboot_first_pending_at', now)
        else:
            state.pop('reboot_first_pending_at', None)
        atomic(state_path, json.dumps(state, sort_keys=True) + '\n')
        atomic(root / 'metrics.prom', metrics(state, args.owner))
        if args.publish:
            url = ('http://10.60.0.20:32085' if args.owner == 'ax41' else 'https://ops.honey.school') + '/victoria-metrics/api/v1/import/prometheus'
            cmd = ['/usr/bin/curl', '--silent', '--fail', '--connect-timeout', '3', '--max-time', '15']
            if args.owner == 'selectel':
                cmd += ['--config', '/etc/playsay/rf-edge-observability-curl.conf',
                        '--resolve', 'ops.honey.school:443:65.109.55.110']
            # Preserve observation time even if delivery is delayed.
            payload = ''.join(line + ' ' + str(now * 1000) + '\n' for line in metrics(state, args.owner).splitlines())
            result = subprocess.run(cmd + ['--data-binary', '@-', url], input=payload,
                                    text=True, capture_output=True, timeout=20, check=False)
            if result.returncode:
                print('publication=failed')
        print('deferred=' + reason)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
