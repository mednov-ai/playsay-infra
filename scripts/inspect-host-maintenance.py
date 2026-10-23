#!/usr/bin/env python3
"""Read-only, aggregate/path/checksum-only host policy inventory. Never emits contents."""
import hashlib
import json
from pathlib import Path
import re
import subprocess

roots = ['/etc/cron.d', '/etc/cron.daily', '/etc/cron.hourly', '/etc/cron.weekly',
         '/etc/cron.monthly', '/var/spool/cron/crontabs', '/etc/systemd/system',
         '/etc/apt/apt.conf.d', '/etc/needrestart', '/etc/unattended-upgrades']
pattern = re.compile(r'apt(-get)?\s.*(upgrade|install)|unattended|needrestart|reboot|shutdown|systemctl\s+(try-)?restart')
for folder in roots:
    root = Path(folder)
    if not root.exists():
        continue
    for path in sorted(root.rglob('*')):
        if not path.is_file() or path.is_symlink():
            continue
        try:
            content = path.read_bytes()
            if pattern.search(content.decode(errors='replace')):
                print(json.dumps({'path': str(path), 'sha256': hashlib.sha256(content).hexdigest(),
                                  'class': 'review_maintenance_entrypoint'}))
        except OSError:
            print(json.dumps({'path': str(path), 'class': 'unreadable'}))
for argv in (['dpkg-query', '-W', '-f=${Package} ${Version}\n', 'apt', 'unattended-upgrades', 'needrestart'],
             ['systemctl', 'show', 'nginx', 'libvirtd', 'coturn', 'honey-school-dev-turn', 'apt-daily-upgrade',
              '-p', 'Id', '-p', 'MainPID', '-p', 'ActiveState'],
             ['systemctl', 'show', 'unattended-upgrades', '-p', 'ExecStart', '-p', 'ActiveState']):
    result = subprocess.run(argv, text=True, capture_output=True)
    print(result.stdout.strip())
print(json.dumps({'reboot_required': Path('/run/reboot-required').exists(),
                  'package_lists_stamp': Path('/var/lib/apt/periodic/update-success-stamp').stat().st_mtime}))
