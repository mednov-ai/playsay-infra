#!/usr/bin/env python3
"""Root-only policy backup. No service action, secrets or application data export."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import tarfile
import time

paths = ['/etc/apt/apt.conf.d', '/etc/needrestart/conf.d',
         '/etc/systemd/system/apt-daily-upgrade.service.d', '/etc/systemd/system/apt-daily-upgrade.timer.d',
         '/etc/systemd/system/honey-school-maintenance-observer.service',
         '/etc/systemd/system/honey-school-maintenance-observer.timer',
         '/usr/local/sbin/honey-school-host-maintenance', '/usr/local/sbin/honey-school-rf-nic-counters',
         '/usr/local/sbin/playsay-probe-rf-to-ax41']
os.umask(0o077)
root = Path('/var/backups/honeyschool/host-maintenance') / time.strftime('%Y%m%dT%H%M%SZ', time.gmtime())
root.mkdir(parents=True, mode=0o700)
with tarfile.open(root/'policy.tar', 'w') as archive:
    for item in paths:
        if Path(item).exists():
            archive.add(item, arcname=item.lstrip('/'))
result = subprocess.run(['systemctl', 'show', 'nginx', 'libvirtd', 'coturn', 'honey-school-dev-turn',
                         'apt-daily-upgrade.timer', '-p', 'Id', '-p', 'MainPID', '-p', 'ActiveState',
                         '-p', 'NextElapseUSecRealtime'], capture_output=True, text=True, check=True)
(root/'state.txt').write_text(result.stdout)
(root/'manifest.json').write_text(json.dumps({'sha256':hashlib.sha256((root/'policy.tar').read_bytes()).hexdigest(),
                                             'paths':paths}, sort_keys=True)+'\n')
with tarfile.open(root/'policy.tar') as archive:
    archive.getmembers()
print('verified_policy_backup='+str(root))
