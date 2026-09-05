#!/usr/bin/env python3
"""Bounded loopback-only test of Fluent Bit privacy and HTTP retry recovery."""
import argparse
import http.server
import json
from pathlib import Path
import subprocess
import tempfile
import threading
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--binary', default='/opt/fluent-bit/bin/fluent-bit')
    parser.add_argument('--privacy-filter', default='/etc/fluent-bit/privacy-filter.lua')
    args = parser.parse_args()
    received = []
    attempts = []

    class Sink(http.server.BaseHTTPRequestHandler):
        def do_POST(self):
            body = self.rfile.read(int(self.headers['Content-Length']))
            attempts.append(1)
            if len(attempts) < 3:
                self.send_response(503)
            else:
                received.extend(json.loads(line) for line in body.splitlines() if line)
                self.send_response(200)
            self.end_headers()

        def log_message(self, *args):
            pass

    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Sink)
    worker = threading.Thread(target=server.serve_forever, daemon=True)
    worker.start()
    process = None
    try:
        with tempfile.TemporaryDirectory(prefix='dev-log-runtime-') as directory:
            root = Path(directory)
            (root / 'buffer').mkdir()
            config = root / 'probe.conf'
            config.write_text(f'''[SERVICE]
    Flush 1
    Log_Level error
    storage.path {root / 'buffer'}
[INPUT]
    Name dummy
    Tag privacy
    Dummy {{"MESSAGE":"error 401: SYNTHETIC_PRIVATE_VALUE"}}
    Samples 1
    storage.type memory
[FILTER]
    Name lua
    Match privacy
    script {args.privacy_filter}
    call sanitize_turn_event
[OUTPUT]
    Name http
    Match privacy
    Host 127.0.0.1
    Port {server.server_port}
    URI /probe
    Format json_lines
    Retry_Limit False
    storage.total_limit_size 1M
''')
            process = subprocess.Popen([args.binary, '-c', str(config)], stdout=subprocess.DEVNULL,
                                       stderr=subprocess.DEVNULL)
            deadline = time.monotonic() + 35
            while time.monotonic() < deadline and not received and process.poll() is None:
                time.sleep(0.2)
            if not received or len(attempts) < 3:
                raise RuntimeError('HTTP retry/recovery was not observed')
            for event in received:
                if event.get('event') != 'authentication_challenge' or event.get('outcome') != 'expected':
                    raise RuntimeError('Normal challenge was misclassified')
                if set(event) - {'date', 'environment', 'source', 'event', 'outcome'}:
                    raise RuntimeError('Unexpected output fields')
            for path in (root / 'buffer').rglob('*'):
                if path.is_file() and b'SYNTHETIC_PRIVATE_VALUE' in path.read_bytes():
                    raise RuntimeError('Unfiltered fixture reached the disk buffer')
            print('PASS: two 503 responses recovered; challenge classified; output allowlist and disk privacy verified')
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
        server.shutdown()
        server.server_close()


if __name__ == '__main__':
    main()
