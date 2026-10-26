"""Fail-closed eligibility, persistent ownership and service-specific security debt."""
from contextlib import contextmanager
from datetime import datetime
import fcntl
import json
import math
import os
import re
from pathlib import Path
import tempfile
from zoneinfo import ZoneInfo

HOSTS = ('ax41', 'selectel')
GUESTS = ('prod', 'dev')
GUEST_FIELDS = frozenset(('lesson_windows', 'unknown_deadlines', 'livekit_rooms', 'livekit_participants',
                         'collaboration_connections', 'game_connections',
                         'external_connections', 'snapshot_queue', 'direct_turn_relay_sockets',
                         'direct_turn_control_connections','direct_turn_control_queued_bytes'))
HOST_FIELDS = frozenset(('ingress_reading', 'ingress_writing'))
TURN_FIELDS = frozenset(('prod_relay_sockets', 'dev_relay_sockets', 'control_connections',
                        'control_queued_bytes'))


class Deferred(Exception):
    """Only fixed safe codes may leave privileged collection/execution boundaries."""
    def __init__(self, code):
        super().__init__(code)
        self.code = code


def integer(value, minimum=0):
    return type(value) is int and value >= minimum


def within_window(now, synchronized, budget=0):
    if not synchronized or not math.isfinite(now) or not integer(budget):
        return False
    local = datetime.fromtimestamp(now, ZoneInfo('Europe/Moscow'))
    seconds = local.hour * 3600 + local.minute * 60 + local.second
    return 10800 <= seconds and seconds + budget < 18000


def validate_observation(sample, fields, now, require_zero=True):
    if not isinstance(sample, dict) or sample.get('healthy') is not True:
        raise Deferred('source_unhealthy')
    stamp = sample.get('observed_at')
    if not integer(stamp) or not 0 <= now - stamp <= 30:
        raise Deferred('source_stale')
    begun=sample.get('read_started_at')
    if not integer(begun) or not 0<=stamp-begun<=25 or now-begun>30:raise Deferred('source_stale')
    if not isinstance(sample.get('generation'), str) or not sample['generation']:
        raise Deferred('source_generation_unknown')
    counts = sample.get('counts')
    if not isinstance(counts, dict) or set(counts) != fields or any(not integer(x) for x in counts.values()):
        raise Deferred('source_malformed')
    if require_zero and any(counts.values()):
        raise Deferred('activity_busy')
    return stamp


def validate_snapshot(snapshot, now, budget, require_fence=True):
    if not isinstance(snapshot, dict) or set(snapshot.get('guests', {})) != set(GUESTS):
        raise Deferred('source_missing')
    generations = []
    stamps = []
    for guest in GUESTS:
        sample = snapshot['guests'][guest]
        stamps.append(validate_observation(sample, GUEST_FIELDS, now, require_zero=False))
        opening = sample.get('next_opening_at')
        # No next lesson is an explicit SQL result; unknown is never infinity.
        if sample.get('next_opening_known') is not True:
            raise Deferred('lesson_opening_unknown')
        if opening is not None and (not integer(opening) or opening <= now + budget + 120):
            raise Deferred('lesson_lookahead')
        generations.append(sample['generation'])
    for host in HOSTS:
        host_sample = snapshot.get('hosts', {}).get(host)
        stamps.append(validate_observation(host_sample, HOST_FIELDS, now, require_zero=False))
        generations.append(host_sample['generation'])
    stamps.append(validate_observation(snapshot.get('turn'), TURN_FIELDS, now, require_zero=False))
    generations.append(snapshot['turn']['generation'])
    samples=[*snapshot['guests'].values(),*snapshot['hosts'].values(),snapshot['turn']]
    if require_fence:
        fences = snapshot.get('fences', {})
        if set(fences) != set(HOSTS) or not all(value is True for value in fences.values()):
            raise Deferred('fence_not_closed')
        if snapshot.get('lease_phase') not in ('fenced', 'committing', 'step_running', 'verifying'):
            raise Deferred('lease_not_fenced')
        epoch=snapshot.get('fenced_at')
        if not integer(epoch) or any(item['read_started_at']<epoch for item in samples):
            raise Deferred('observations_precede_fence')
    # First prove that every complete read belongs to the closed-admission
    # epoch. Old positive values are neither a post-fence busy decision nor a
    # zero baseline. Claiming (without a fence) still rejects any activity.
    if any(any(item['counts'].values()) for item in samples):raise Deferred('activity_busy')
    return dict(zip(('prod', 'dev', 'ax41', 'selectel', 'turn'), stamps)), tuple(generations)


def two_zero_observations(first, second, now, budget):
    left, left_generation = validate_snapshot(first, now, budget)
    right, right_generation = validate_snapshot(second, now, budget)
    samples={'prod':second['guests']['prod'],'dev':second['guests']['dev'],
             'ax41':second['hosts']['ax41'],'selectel':second['hosts']['selectel'],'turn':second['turn']}
    if any(samples[key]['read_started_at'] - left[key] < 10 for key in left):
        raise Deferred('observation_spacing')
    if first.get('lease_id') != second.get('lease_id') or first.get('fenced_at') != second.get('fenced_at'):
        raise Deferred('lease_generation_changed')
    if left_generation != right_generation:
        raise Deferred('source_generation_changed')


def atomic_json(path, value):
    path = Path(path)
    with tempfile.NamedTemporaryFile('w', dir=path.parent, delete=False) as stream:
        tmp = Path(stream.name)
        os.chmod(tmp, 0o600)
        json.dump(value, stream, sort_keys=True, allow_nan=False)
        stream.write('\n')
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(tmp, path)
    fd = os.open(path.parent, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


class Journal:
    """Shared across threads/processes; corrupt state cannot become an empty lease."""
    def __init__(self, directory):
        self.root = Path(directory)

    @contextmanager
    def locked(self, name):
        if name not in ('coordinator', 'worker', 'observations', 'debt', 'auth', 'fence'):
            raise ValueError('unknown_journal')
        with (self.root / (name + '.lock')).open('a') as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as error:
                raise Deferred('lock_busy') from error
            path = self.root / (name + '.json')
            state = json.loads(path.read_text()) if path.exists() else {}
            if not isinstance(state, dict):
                raise Deferred('journal_invalid')
            yield state
            atomic_json(path, state)


def reserve(journal, actor, lease_id, now, synchronized):
    if actor not in HOSTS or not isinstance(lease_id, str) or not re.fullmatch('[0-9a-f]{32}', lease_id):
        raise Deferred('lease_request_invalid')
    if not within_window(now, synchronized, 1020):
        raise Deferred('outside_window')
    with journal.locked('coordinator') as state:
        # Expiry NEVER steals a lease from a hung/partitioned package transaction.
        if state.get('phase', 'idle') != 'idle':
            raise Deferred('lease_busy')
        state.update(owner=actor, lease_id=lease_id, phase='reserved',
                     first_claimed_at=int(now), heartbeat_at=int(now), destructive_started=False,release_verified=False,last_step_completed_at=0)


def assert_owner(state, actor, lease_id):
    if state.get('owner') != actor or state.get('lease_id') != lease_id or state.get('phase', 'idle') == 'idle':
        raise Deferred('lease_owner_mismatch')


def service_debt(previous, observations, now):
    """Unknown preserves age; only actual inode/runtime inspection clears restart debt."""
    result = dict(previous)
    for service, observation in observations.items():
        old = previous.get(service, {})
        if observation is None:
            result[service] = {**old, 'healthy': False, 'checked_at': now}
        elif observation['pending']:
            result[service] = {**old, **observation, 'healthy': True, 'checked_at': now,
                               'first_pending_at': old.get('first_pending_at', now)}
        elif old.get('pending') and (not observation.get('active',True) or not observation.get('process_started') or observation.get('process_started')==old.get('process_started')):
            # A reload or disappearing child mapping does not prove a service restart.
            result[service] = {**old, **observation, 'pending': True, 'healthy': True, 'checked_at': now,
                               'first_pending_at': old.get('first_pending_at',now)}
        else:
            result[service] = {**observation, 'healthy': True, 'checked_at': now}
    return result


def validate_recovery(snapshot, now):
    """Healthy read-only reopening never grants a disruptive step.

    Busy work or a newly opened lesson window must not strand cabinets after a
    completed transaction. Unknown/stale sources still prevent claiming recovery.
    Lease identity, native package ownership and post-step unit health are checked
    by the coordinator separately; no timeout steals an uncertain transaction.
    """
    for guest in GUESTS:
        validate_observation(snapshot.get('guests',{}).get(guest),GUEST_FIELDS,now,require_zero=False)
    for host in HOSTS:
        validate_observation(snapshot.get('hosts',{}).get(host),HOST_FIELDS,now,require_zero=False)
    validate_observation(snapshot.get('turn'),TURN_FIELDS,now,require_zero=False)
