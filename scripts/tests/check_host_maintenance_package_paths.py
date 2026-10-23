#!/usr/bin/env python3
"""Replay the installed apt daily entrypoint in disposable offline containers.

The fake upgrade models both needrestart and direct package hooks. No actual
package is installed and no production process is signalled. Requires cached Ubuntu.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile

parser=argparse.ArgumentParser()
parser.add_argument('--apt-script', required=True)
args=parser.parse_args()
repo=Path(__file__).resolve().parents[2]
script=Path(args.apt_script).resolve()
assert script.is_file()
with tempfile.TemporaryDirectory() as directory:
    root=Path(directory)
    (root/'bin').mkdir()
    stub='''#!/bin/sh
case " $* " in *" --help "*) echo download-only; exit 0;; *" --download-only "*) echo download >> /fixture/download; exit 0;; esac
# Model the original zlib/needrestart request and an independent direct hook.
echo nginx.service >> /fixture/critical_restart_requested
echo direct-package-hook >> /fixture/critical_restart_requested
'''
    (root/'bin/unattended-upgrade').write_text(stub)
    (root/'bin/unattended-upgrade').chmod(0o755)
    (root/'bin/apt-get').write_text('#!/bin/sh\necho "$*" >> /fixture/apt-commands\nexit 0\n')
    (root/'bin/apt-get').chmod(0o755)
    (root/'20auto-upgrades').write_text('APT::Periodic::Unattended-Upgrade "1";\n')
    (root/'zz-enable').write_text('APT::Periodic::Enable "1";\n')
    (root/'invalid').write_text('APT::Periodic::Unattended-Upgrade "0" missing_terminator\n')
    base=['docker','run','--rm','--network','none','--cap-drop','ALL','--cap-add','DAC_OVERRIDE','--security-opt','no-new-privileges',
          '-v', str(root)+':/fixture', '-v', str(script)+':/apt-daily:ro',
          '-v', str(root/'20auto-upgrades')+':/etc/apt/apt.conf.d/20auto-upgrades:ro',
          '-v', str(root/'zz-enable')+':/etc/apt/apt.conf.d/zz-enable:ro',
          '-e','PATH=/fixture/bin:/usr/sbin:/usr/bin:/sbin:/bin']
    subprocess.run(base+['ubuntu:24.04','sh','/apt-daily','install'],check=True,capture_output=True)
    marker=root/'critical_restart_requested'
    assert marker.exists(), 'Unprotected control did not exercise the original hook'
    marker.unlink()
    protected=base+['-v', str(repo/'ansible/roles/honey-school-host-maintenance/templates/99-honey-school-maintenance.conf.j2')+':/etc/apt/apt.conf.d/99-honey-school-maintenance:ro']
    subprocess.run(protected+['ubuntu:24.04','sh','/apt-daily','install'],check=True,capture_output=True)
    assert not marker.exists(), 'Protected installer entered disruptive hooks'
    subprocess.run(protected+['ubuntu:24.04','sh','/apt-daily','update'],check=True,capture_output=True)
    assert not marker.exists(), 'Discovery/download entered a disruptive path'
    assert '-d dist-upgrade' in (root/'apt-commands').read_text(), 'Download discovery was lost'
    invalid=subprocess.run(base+['ubuntu:24.04','apt-config','-c','/fixture/invalid','dump'],capture_output=True)
    assert invalid.returncode != 0, 'Invalid candidate was accepted'
print('PASS: original hooks exercised; installation deferred before both hooks; downloads retained; invalid policy rejected')
