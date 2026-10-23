#!/usr/bin/env python3
"""Replay the exact installed public apt-pinvoke body, replacing only fixture paths."""
import argparse
import os
from pathlib import Path
import shlex
import subprocess
import tempfile

parser=argparse.ArgumentParser();parser.add_argument('--apt-pinvoke',required=True);args=parser.parse_args()
source=Path(args.apt_pinvoke).read_text()
assert source.count('RUNDIR=/run/needrestart')==1 and source.count('exec /usr/sbin/needrestart')==1
with tempfile.TemporaryDirectory(prefix='honey-needrestart-') as directory:
    root=Path(directory);runtime=root/'run';runtime.mkdir()
    marker=root/'restart-requested';executable=root/'needrestart'
    executable.write_text('#!/bin/sh\ntouch '+shlex.quote(str(marker))+'\n');executable.chmod(0o755)
    script=root/'apt-pinvoke';script.write_text(source.replace('RUNDIR=/run/needrestart','RUNDIR='+shlex.quote(str(runtime))).replace('exec /usr/sbin/needrestart','exec '+shlex.quote(str(executable))))
    (runtime/'unpacked').touch()
    environment={k:v for k,v in os.environ.items() if k not in ('NEEDRESTART_SUSPEND','NEEDRESTART_MODE')}
    subprocess.run(['/bin/sh',str(script),'-m','u'],env=environment,check=True,capture_output=True)
    assert marker.exists(), 'Unprotected control did not reach the actual native exec path'
    marker.unlink();(runtime/'unpacked').touch()
    subprocess.run(['/bin/sh',str(script),'-m','u'],env={**environment,'NEEDRESTART_SUSPEND':'1','NEEDRESTART_MODE':'l'},check=True,capture_output=True)
    assert not marker.exists() and (runtime/'unpacked').exists(), 'Native suspend guard bypassed'
print('PASS exact installed needrestart hook: unprotected path reaches restart selection; transaction suspension prevents it')
