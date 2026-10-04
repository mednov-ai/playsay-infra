#!/usr/bin/env python3
"""Generate once into a protected operator directory, never print credentials."""
import argparse
import json
import os
import secrets
import subprocess
from pathlib import Path

parser=argparse.ArgumentParser(); parser.add_argument('--directory',required=True); args=parser.parse_args()
os.umask(0o077); root=Path(args.directory).resolve(); root.mkdir(mode=0o700,parents=True,exist_ok=True)
manifest=root/'credentials.json'
if manifest.exists(): credentials=json.loads(manifest.read_text())
else:
    credentials={profile:{'user':'prod-'+profile,'password':secrets.token_urlsafe(32)} for profile in ('rf','ax41','prod')}
    manifest.write_text(json.dumps(credentials)); manifest.chmod(0o600)
verifiers=[]
for profile,credential in credentials.items():
    digest=subprocess.check_output(['openssl','passwd','-apr1','-stdin'],input=(credential['password']+'\n').encode()).decode().strip()
    verifiers.append(credential['user']+':'+digest)
    directory=root/profile; directory.mkdir(mode=0o700,exist_ok=True)
    address='127.0.0.1' if profile=='ax41' else '65.109.55.110'
    for filename,endpoint in [('production-logs.curl','/victoria-logs/insert/jsonline'),('production-log-metrics.curl','/production-log-metrics')]:
        path=directory/filename
        content='url = "https://ops.honey.school'+endpoint+'"\nuser = "'+credential['user']+':'+credential['password']+'"\nresolve = "ops.honey.school:443:'+address+'"\n'
        if not path.exists(): path.write_text(content)
        path.chmod(0o600)
verifier=root/'production-log-ingest.htpasswd'
# APR1 salts change on regeneration, so preserve the first verifier for idempotence.
if not verifier.exists(): verifier.write_text('\n'.join(verifiers)+'\n')
verifier.chmod(0o600)
print('Dedicated production log credentials prepared; values are not displayed.')
