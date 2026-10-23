#!/usr/bin/env python3
"""Owning-host private backup of only maintenance control/configuration candidates."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import tarfile
from datetime import datetime,timezone
import uuid

parser=argparse.ArgumentParser();parser.add_argument('--owner',choices=('ax41','selectel','prod','dev'),required=True);args=parser.parse_args()
assert os.geteuid()==0,'privilege_required'
os.umask(0o077)
paths=[Path('/etc/honey-school-maintenance'),Path('/usr/local/lib/honey-school-maintenance'),
       Path('/var/lib/honeyschool/maintenance/state.json'),Path('/var/lib/honeyschool/maintenance/debt.json')]
paths+=list(Path('/usr/local/sbin').glob('honey-school-maintenance-*'))
paths+=list(Path('/etc/systemd/system').glob('honey-school-maintenance-*'))
if args.owner in ('prod','dev'):
    paths+=[Path('/etc/sudoers.d/honey-school-maintenance-read')]
else:
    paths+=[Path('/etc/policy-rc.d'),Path('/etc/nginx/snippets/honey-school-maintenance-admission.conf'),
            Path('/etc/nginx/snippets/honey-school-maintenance-control.conf'),Path('/etc/nginx/conf.d/01-honey-school-maintenance-status.conf')]
    paths += [Path('/etc/nginx/conf.d')/name for name in (['playsay-honey.conf'] if args.owner=='ax41' else ['playsay-honey-rf-edge.conf','honey-school-rf-dev.conf'])]
    for unit in (['nginx','libvirtd','playsay-livekit-nat'] if args.owner=='ax41' else ['nginx','coturn','honey-school-dev-turn']):
        paths.append(Path('/etc/systemd/system')/(unit+'.service.d/95-honey-maintenance-admission.conf'))
root=Path('/var/backups/playsay')/('maintenance-control-'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')+'-'+uuid.uuid4().hex[:8])
root.mkdir(parents=True,mode=0o700)
manifest=[]
with tarfile.open(root/'configuration.tar.gz','w:gz',dereference=False) as archive:
    for path in sorted(set(paths)):
        present=path.exists() or path.is_symlink()
        manifest.append({'path':str(path),'existed':present})
        if present:archive.add(path,arcname=str(path).lstrip('/'),recursive=True)
(root/'manifest.json').write_text(json.dumps({'owner':args.owner,'paths':manifest},indent=2)+'\n')
with (root/'configuration.tar.gz').open('rb') as stream:checksum=hashlib.file_digest(stream,'sha256').hexdigest()
(root/'SHA256SUMS').write_text(checksum+'  configuration.tar.gz\n')
print(json.dumps({'backup_dir':str(root),'paths':len(manifest),'archive_sha256':checksum}))
