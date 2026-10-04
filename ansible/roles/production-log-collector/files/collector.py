#!/usr/bin/env python3
"""Production diagnostics. Only sanitize() output enters SQLite or transport.
No raw stderr, exception, record, address or journal MESSAGE is ever logged.
"""
import argparse
import datetime as dt
import glob
import json
import math
import os
import re
import sqlite3
import subprocess
import time
import uuid
from pathlib import Path

SOURCES = ('rf_nginx', 'ax41_nginx', 'rf_coturn', 'livekit', 'api_route', 'collaboration')
MAX_LINE = 16384
MAX_RECORD = 2048

def utc(value):
    if isinstance(value, (int, float)) or re.fullmatch(r'\d+(\.\d+)?', str(value)):
        date = dt.datetime.fromtimestamp(float(value), dt.timezone.utc)
    else:
        date = dt.datetime.fromisoformat(str(value).replace('Z', '+00:00'))
        if date.tzinfo is None:
            raise ValueError('timestamp requires timezone')
    return date.astimezone(dt.timezone.utc).isoformat(timespec='milliseconds').replace('+00:00', 'Z')

def number(value, maximum=604800):
    n = float(value)
    if not math.isfinite(n) or n < 0 or n > maximum:
        raise ValueError('number outside budget')
    return n

def pairs(raw):
    return dict(re.findall(r'\b([a-z_]+)=([^\s]+)', raw))

def sanitize(source, raw, timestamp=None):
    """Reject by default. Enumerations only, never copy arbitrary messages."""
    try:
        if source not in SOURCES:
            return None
        if isinstance(raw, str) and len(raw.encode()) > MAX_LINE:
            return None
        if source == 'rf_coturn':
            timestamp = utc(int(raw['__REALTIME_TIMESTAMP']) / 1e6)
            raw = raw['MESSAGE']
            if not isinstance(raw, str) or len(raw.encode()) > MAX_LINE: return None
        elif source in ('livekit', 'api_route', 'collaboration'):
            cri = re.fullmatch(r'(\S+) (?:stdout|stderr) F (.*)', raw, re.S)
            if cri:
                timestamp = utc(cri[1]); raw = cri[2]
            if timestamp is None:
                return None
        event = {'environment': 'prod', 'source': source, 'timestamp': timestamp}
        if source.endswith('nginx'):
            fields = pairs(raw)
            event.update(timestamp=utc(fields['msec']), event='signaling_request', severity='info')
            if not re.fullmatch(r'[a-f0-9]{32}', fields.get('request_id', '')):
                return None
            event['request_id'] = fields['request_id']
            status = int(fields['status'])
            if not 100 <= status <= 599:
                return None
            event['status'] = status
            event['outcome'] = 'success' if status < 400 else 'failure'
            for key in ('request_time', 'upstream_connect_time', 'upstream_header_time', 'upstream_response_time'):
                if fields.get(key, '-') != '-':
                    # Multiple upstream attempts are ambiguous: do not invent a sum.
                    if ',' not in fields[key] and ':' not in fields[key]:
                        event[key] = number(fields[key])
        elif source == 'rf_coturn':
            text = raw.lower()
            taxonomy = (
                ('allocation timeout', 'allocation_closed', 'timeout'),
                ('allocation deleted', 'allocation_closed', 'normal'),
                ('allocation created', 'allocation_opened', 'normal'),
                ('incoming packet allocate processed, success', 'allocation_opened', 'normal'),
                ('closed (2nd stage)', 'allocation_closed', 'normal'),
                ('401: unauthorized', 'authentication_challenge', 'unauthorized'),
                ('438: stale nonce', 'authentication_challenge', 'stale_nonce'),
                ('connection reset by peer', 'transport_error', 'connection_reset'),
                ('tls/tcp socket error', 'transport_error', 'socket_error'),
            )
            found = next(((name, reason) for match, name, reason in taxonomy if match in text), None)
            if not found:
                return None
            event.update(event=found[0], reason=found[1], severity='warn' if found[0] == 'transport_error' else 'info')
        elif source == 'livekit':
            # Exact phrases only; room/participant/error objects are discarded.
            taxonomy = (
                ('starting rtc session', 'rtc_opened', 'normal'),
                ('participant closing', 'rtc_closed', 'normal'),
                ('removing participant', 'rtc_closed', 'normal'),
                ('error reading data channel', 'rtc_error', 'data_channel'),
                ('could not establish', 'rtc_error', 'connection_failed'),
                ('ice connection state failed', 'rtc_error', 'ice_failed'),
                ('dtls timeout', 'rtc_error', 'dtls_timeout'),
            )
            found = next(((name, reason) for match, name, reason in taxonomy if match in raw.lower()), None)
            if not found:
                return None
            event.update(event=found[0], reason=found[1], severity='warn' if found[0] == 'rtc_error' else 'info')
        elif source == 'api_route':
            if 'regional_route_diagnostic ' not in raw:
                return None
            fields = pairs(raw)
            enums = {
                'stage': {'ENTRY', 'AUTH', 'POLICY', 'SIGNALING', 'ICE', 'MEDIA'},
                'outcome': {'STARTED', 'SUCCESS', 'FAILURE', 'UNAVAILABLE'},
                'connection_role': {'PUBLISHER', 'SUBSCRIBER', 'NONE'},
                'transport_class': {'DIRECT', 'TURN_UDP', 'TURN_TCP', 'TURN_TLS', 'UNKNOWN'},
                'regional_endpoint_matched': {'true', 'false', 'null'},
            }
            for key, allowed in enums.items():
                if fields.get(key) not in allowed:
                    return None
                event[key] = fields[key]
            attempt = fields.get('attempt_id', '')
            if not re.fullmatch(r'[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}', attempt):
                return None
            event.update(attempt_id=attempt, event='regional_route', severity='info')
        elif source == 'collaboration':
            if raw.startswith('{'):
                fields = json.loads(raw)
                name = fields.get('event')
                if name in ('connection_opened', 'connection_closed', 'heartbeat_termination', 'connection_error'):
                    if fields.get('channel') not in ('yjs', 'game', 'external-activity'):
                        return None
                    event.update(event=name, channel=fields['channel'], severity='warn' if name in ('connection_error', 'heartbeat_termination') else 'info')
                    if name == 'connection_closed':
                        if fields.get('close_class') not in ('heartbeat', 'normal', 'transport'):
                            return None
                        event['close_class'] = fields['close_class']
                        if 'age_seconds' in fields:
                            event['age_seconds'] = number(fields['age_seconds'])
                elif name == 'external_activity_input_failure':
                    event.update(event=name, severity='warn', reason='input_failure')
                else:
                    return None
            elif raw.startswith('snapshot persistence failed for document '):
                event.update(event='snapshot_failure', severity='warn', reason='persistence_failed')
            else:
                return None
        if event['timestamp'] is None:
            return None
        return event
    except (ValueError, TypeError, KeyError, OverflowError, OSError):
        return None

class Outbox:
    def __init__(self, directory, limit=64*1024*1024):
        directory = Path(directory); directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.db = sqlite3.connect(directory / 'sanitized.sqlite')
        self.limit = limit
        self.db.execute('PRAGMA auto_vacuum=FULL')
        self.db.execute('PRAGMA journal_mode=DELETE')
        self.db.executescript('''CREATE TABLE IF NOT EXISTS events(id INTEGER PRIMARY KEY, body TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS cursors(key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS counters(source TEXT, name TEXT, value INTEGER, PRIMARY KEY(source,name));
CREATE TABLE IF NOT EXISTS gauges(source TEXT, name TEXT, value REAL, PRIMARY KEY(source,name));''')
        # SQLite pages, transaction journal and metadata fit in the declared 64Mi budget.
        self.db.execute(f'PRAGMA max_page_count={max(64, limit // 12288)}')
        self.used = self.db.execute('SELECT COALESCE(SUM(length(body)),0) FROM events').fetchone()[0]

    def count(self, source, name, increment=1):
        self.db.execute('INSERT INTO counters VALUES(?,?,?) ON CONFLICT(source,name) DO UPDATE SET value=value+excluded.value', (source,name,increment))

    def cursor(self, key):
        row = self.db.execute('SELECT value FROM cursors WHERE key=?', (key,)).fetchone()
        return row[0] if row else None

    def checkpoint(self, key, value):
        self.db.execute('INSERT OR REPLACE INTO cursors VALUES(?,?)', (key, str(value)))
        # Metadata is bounded even when Kubernetes pod filenames continually change.
        self.db.execute('DELETE FROM cursors WHERE rowid IN (SELECT rowid FROM cursors ORDER BY rowid DESC LIMIT -1 OFFSET 128)')

    def enqueue(self, source, record, cursor=None):
        with self.db:
            if record is None:
                self.count(source, 'rejected')
            else:
                record = dict(record, event_id=str(uuid.uuid4()), collected_timestamp=utc(time.time()))
                body = json.dumps(record, separators=(',', ':'))
                if len(body) > MAX_RECORD:
                    self.count(source, 'rejected')
                else:
                    used = self.used
                    while used + len(body) > self.limit // 4:
                        row = self.db.execute('SELECT id,body FROM events ORDER BY id LIMIT 1').fetchone()
                        if row is None: break
                        old = json.loads(row[1]); self.count(old['source'], 'dropped')
                        self.db.execute('DELETE FROM events WHERE id=?', (row[0],)); used -= len(row[1])
                    self.db.execute('INSERT INTO events(body) VALUES(?)', (body,))
                    self.used = used + len(body)
                    self.count(source, 'accepted')
            if cursor:
                self.checkpoint(*cursor)

    def batch(self):
        return self.db.execute('SELECT id,body FROM events ORDER BY id LIMIT 128').fetchall()

    def deliver(self, curl_config):
        batch = self.batch()
        if not batch: return True
        payload = '\n'.join(row[1] for row in batch) + '\n'
        try:
            # config is root-only: URL/auth never appear in process arguments or output.
            result = subprocess.run(['curl', '--config', curl_config, '--proto', '=https', '--tlsv1.2', '--no-insecure', '--no-location', '--silent', '--fail', '--connect-timeout', '2', '--max-time', '5', '--header', 'Content-Type: application/stream+json', '--data-binary', '@-', '--output', '/dev/null'], input=payload.encode(), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=6)
            success = result.returncode == 0
        except (OSError, subprocess.TimeoutExpired):
            success = False
        if success:
            with self.db:
                for row in batch:
                    record = json.loads(row[1]); source = record['source']
                    lag = max(0, time.time() - dt.datetime.fromisoformat(record['timestamp'].replace('Z', '+00:00')).timestamp())
                    self.db.execute('INSERT OR REPLACE INTO gauges VALUES(?,?,?)', (source, 'delivery_lag_seconds', lag))
                    self.db.execute('INSERT OR REPLACE INTO gauges VALUES(?,?,?)', (source, 'last_delivery_seconds', time.time()))
                    self.db.execute('DELETE FROM events WHERE id=?', (row[0],))
                    self.used -= len(row[1])
        return success

class FileReader:
    def __init__(self, outbox, inputs):
        self.outbox = outbox; self.inputs = inputs; self.handles = {}; self.parts = {}; self.available = {}

    def poll(self):
        self.available = {source: False for source in self.inputs}
        paths = [(source, path) for source, pattern in self.inputs.items() for path in sorted(glob.glob(pattern))][:32]
        for source, path in paths:
            try:
                stat = os.stat(path); self.available[source] = True; key = f'{path}:{stat.st_dev}:{stat.st_ino}'
                if key not in self.handles:
                    if len(self.handles) >= 32:
                        self.available[source] = False
                        with self.outbox.db: self.outbox.count(source, 'read_errors')
                        continue
                    handle = open(path, 'rb'); offset = int(self.outbox.cursor(key) or 0)
                    handle.seek(offset if offset <= stat.st_size else 0)
                    self.handles[key] = (source, handle)
            except OSError:
                self.available[source] = False
                with self.outbox.db: self.outbox.count(source, 'read_errors')
        # Open handles preserve the old inode through rename/rotation.
        for key, (source, handle) in list(self.handles.items()):
            if os.fstat(handle.fileno()).st_size < handle.tell():
                handle.seek(0); self.parts.pop(key, None)
            for _ in range(128):
                offset = handle.tell(); line = handle.readline(MAX_LINE + 1)
                if not line: break
                if not line.endswith(b'\n'):
                    if len(line) <= MAX_LINE:
                        handle.seek(offset); break
                    # Oversized physical records are discarded, not split into valid events.
                    self.parts[key] = None
                    continue
                text = line.decode('utf-8', errors='replace').rstrip('\n')
                if len(line) > MAX_LINE or (key in self.parts and self.parts[key] is None):
                    self.parts.pop(key, None); record = None
                else:
                    cri = re.fullmatch(r'(\S+) (stdout|stderr) ([PF]) (.*)', text, re.S)
                    if cri:
                        partial = self.parts.get(key, '') + cri[4]
                        if len(partial.encode()) > MAX_LINE:
                            self.parts[key] = None; continue
                        if cri[3] == 'P':
                            self.parts[key] = partial; continue
                        self.parts.pop(key, None)
                        text = f'{cri[1]} {cri[2]} F {partial}'
                    record = sanitize(source, text)
                self.outbox.enqueue(source, record, (key, handle.tell()))
            current = set()
            for _, path in paths:
                try:
                    stat = os.stat(path); current.add(f'{path}:{stat.st_dev}:{stat.st_ino}')
                except OSError: pass
            if key not in current and handle.tell() >= os.fstat(handle.fileno()).st_size:
                handle.close(); del self.handles[key]; self.parts.pop(key, None)

class JournalReader:
    def __init__(self, outbox, unit):
        self.outbox = outbox; self.unit = unit; self.process = None; self.buffer = b''; self.oversized = False

    def poll(self):
        if self.process is None or self.process.poll() is not None:
            if self.process is not None:
                with self.outbox.db: self.outbox.count('rf_coturn', 'read_errors')
            cursor = self.outbox.cursor('journal')
            args = ['journalctl', '--unit', self.unit, '--output=json', '--no-pager', '--follow']
            args += ['--after-cursor', cursor] if cursor else ['--lines=0']
            self.process = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            os.set_blocking(self.process.stdout.fileno(), False)
            self.buffer = b''
        for _ in range(64):
            try: chunk = os.read(self.process.stdout.fileno(), 4096)
            except BlockingIOError: break
            if not chunk: break
            self.buffer += chunk
            while b'\n' in self.buffer:
                line, self.buffer = self.buffer.split(b'\n', 1)
                if self.oversized or len(line) > MAX_LINE:
                    self.outbox.enqueue('rf_coturn', None); self.oversized = False; continue
                try:
                    raw = json.loads(line)
                    if not isinstance(raw, dict):
                        self.outbox.enqueue('rf_coturn', None); continue
                    cursor = raw.get('__CURSOR')
                    # Cursor is journal metadata, not message/identity-derived.
                    checkpoint = ('journal', cursor) if isinstance(cursor, str) and len(cursor) < 512 else None
                    self.outbox.enqueue('rf_coturn', sanitize('rf_coturn', raw), checkpoint)
                except (ValueError, TypeError): self.outbox.enqueue('rf_coturn', None)
            if len(self.buffer) > MAX_LINE:
                self.buffer = b''; self.oversized = True

    def close(self):
        if self.process is not None:
            self.process.terminate(); self.process.wait(timeout=2)

def metrics(outbox, sources, success, file_path, available=None):
    rows = outbox.db.execute('SELECT source,name,value FROM counters').fetchall()
    present = {(source,name) for source,name,value in rows}
    rows += [(source,name,0) for source in sources for name in ('accepted','rejected','dropped','read_errors') if (source,name) not in present]
    lines = [f'honey_prod_logs_{name}_total{{source="{source}"}} {value}' for source,name,value in rows]
    lines += [f'honey_prod_logs_{name}{{source="{source}"}} {value}' for source,name,value in outbox.db.execute('SELECT source,name,value FROM gauges')]
    batch = outbox.db.execute('SELECT body FROM events ORDER BY id LIMIT 1').fetchone()
    age = time.time() - dt.datetime.fromisoformat(json.loads(batch[0])['timestamp'].replace('Z','+00:00')).timestamp() if batch else 0
    size = outbox.db.execute('SELECT COALESCE(SUM(length(body)),0) FROM events').fetchone()[0]
    for source in sources:
        lines.append(f'honey_prod_logs_input_ok{{source="{source}"}} {int((available or {}).get(source, False))}')
        lines += [f'honey_prod_logs_heartbeat_seconds{{source="{source}"}} {time.time()}', f'honey_prod_logs_delivery_ok{{source="{source}"}} {int(success)}', f'honey_prod_logs_backlog_bytes{{source="{source}"}} {size}', f'honey_prod_logs_oldest_seconds{{source="{source}"}} {max(0, age)}']
    path = Path(file_path); path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix('.tmp'); temp.write_text('\n'.join(lines)+'\n'); os.replace(temp, path)

def main():
    parser = argparse.ArgumentParser(); parser.add_argument('--config', required=True); args = parser.parse_args()
    config = json.loads(Path(args.config).read_text())
    os.umask(0o077)
    outbox = Outbox(config['state_dir']); files = FileReader(outbox, config['files'])
    journal = JournalReader(outbox, config['journal_unit']) if config.get('journal_unit') else None
    sources = list(config['files']) + (['rf_coturn'] if journal else [])
    last_heartbeat = 0
    try:
        while True:
            files.poll()
            if journal: journal.poll()
            available = dict(files.available)
            if journal: available['rf_coturn'] = journal.process.poll() is None
            if time.time() - last_heartbeat >= 15:
                for source in sources:
                    outbox.enqueue(source, {'environment':'prod','source':source,'timestamp':utc(time.time()),'event':'collector_heartbeat','severity':'info','input_ok':int(available.get(source, False))})
                last_heartbeat = time.time()
            success = outbox.deliver(config['curl_config'])
            metrics(outbox, sources, success, config['metrics_file'], available)
            try:
                subprocess.run(['curl', '--config', config['metrics_curl_config'], '--proto', '=https', '--tlsv1.2', '--no-insecure', '--no-location', '--silent', '--fail', '--connect-timeout', '2', '--max-time', '5', '--header', 'Content-Type: text/plain', '--data-binary', '@'+config['metrics_file'], '--output', '/dev/null'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=6)
            except (OSError, subprocess.TimeoutExpired): pass
            time.sleep(1 if success else 5)
    finally:
        if journal: journal.close()

if __name__ == '__main__':
    try: main()
    except Exception:
        # Do not print a traceback or data-dependent exception to systemd logs.
        raise SystemExit('production log collector stopped; inspect health counters and storage')
