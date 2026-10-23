#!/usr/bin/env python3
"""Reviewed narrow nginx owner. Stage/validate all candidates before atomic writes/reload."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time

ROOT=Path('/etc/nginx')
CABINETS={'ax41':{'online.honey.school','dev.online.honey.school'},
          'selectel':{'online.honeyschool.ru','dev.online.honeyschool.ru'}}
FILES={'ax41':['conf.d/playsay-honey.conf'],
       'selectel':['conf.d/playsay-honey-rf-edge.conf','conf.d/honey-school-rf-dev.conf']}
INCLUDE='    include /etc/nginx/snippets/honey-school-maintenance-admission*.conf;\n'
CONTROL='    include /etc/nginx/snippets/honey-school-maintenance-control*.conf;\n'
ADMISSION='''# Honey School cabinet barrier; ACME remains reachable.
set $honey_maintenance_closed 0;
if (-f /var/lib/honey-school-maintenance-admission/closed) { set $honey_maintenance_closed 1; }
if ($uri ~ ^/\\.well-known/acme-challenge/) { set $honey_maintenance_closed 0; }
if ($honey_maintenance_closed) { return 599; }
error_page 599 = @honey_maintenance_pause;
location @honey_maintenance_pause {
    add_header Retry-After 60 always;
    add_header X-Honey-Maintenance closed always;
    return 503;
}
'''
CONTROL_TEXT='''# Separate role authentication is enforced by the local agent, never metrics-import credentials.
location ^~ /__host_maintenance__/ {
    allow 127.0.0.1;
    allow 65.109.55.110;
    allow 94.102.89.213;
    allow 10.60.0.20;
    allow 10.60.0.30;
    deny all;
    auth_basic off;
    client_max_body_size 64k;
    proxy_pass http://127.0.0.1:9276/;
    proxy_connect_timeout 2s;
    proxy_read_timeout 15s;
    proxy_set_header Connection close;
    access_log off;
}
'''
STATUS='''server {
    listen 127.0.0.1:9277;
    server_name localhost;
    access_log off;
    location = /status { stub_status; allow 127.0.0.1; deny all; }
    location / { return 404; }
}
'''


def patch(text,owner):
    stack=[];blocks=[]
    tokens=re.finditer(r'#[^\n]*|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|[{}]',text)
    for token in tokens:
        if token[0]=='{':stack.append(token.start())
        elif token[0]=='}':
            if not stack:raise ValueError('nginx_structure_unknown')
            start=stack.pop()
            if re.search(r'\bserver\s*$',text[max(0,start-30):start]):blocks.append((start,token.start()))
    if stack:raise ValueError('nginx_structure_unknown')
    edits=[];seen=[];ops=0
    for start,end in blocks:
        body=text[start:end]
        names=re.findall(r'\bserver_name\s+([^;]+);',body)
        if len(names)!=1:raise ValueError('nginx_server_inventory_unknown')
        hosts=set(names[0].split())
        if hosts&CABINETS[owner]:
            if len(hosts)!=1:raise ValueError('nginx_shared_server_unknown')
            seen+=list(hosts)
            if INCLUDE.strip() not in body:edits.append((start+1,'\n'+INCLUDE))
        if hosts=={'ops.honey.school'} and re.search(r'\blisten\s+[^;]*443[^;]*ssl',body):
            ops+=1
            if CONTROL.strip() not in body:edits.append((end,CONTROL))
    for index,value in sorted(edits,reverse=True):text=text[:index]+value+text[index:]
    return text,seen,ops


def checked(args):
    p=subprocess.run(args,capture_output=True)
    if p.returncode:raise ValueError('candidate_or_activation_failed')


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--owner',choices=FILES,required=True)
    parser.add_argument('--apply',action='store_true');args=parser.parse_args()
    candidates={};seen=[];ops=0
    for name in FILES[args.owner]:
        body,found,count=patch((ROOT/name).read_text(),args.owner)
        candidates[name]=body;seen+=found;ops+=count
    if sorted(seen)!=sorted(list(CABINETS[args.owner])*2) or ops!=1:raise ValueError('ingress_inventory_unknown')
    candidates.update({'snippets/honey-school-maintenance-admission.conf':ADMISSION,
                       'snippets/honey-school-maintenance-control.conf':CONTROL_TEXT,
                       'conf.d/01-honey-school-maintenance-status.conf':STATUS})
    for name in candidates:
        path=ROOT/name
        if any(p.is_symlink() for p in [path,*path.parents] if p!=Path('/')):raise ValueError('nginx_owner_symlink_unsupported')
    changed={name:body for name,body in candidates.items() if not (ROOT/name).exists() or (ROOT/name).read_text()!=body}
    if not changed:print(json.dumps({'changed':False}));return
    with tempfile.TemporaryDirectory(prefix='honey-maintenance-nginx-') as directory:
        stage=Path(directory)/'nginx';shutil.copytree(ROOT,stage,symlinks=True)
        for name,body in candidates.items():
            (stage/name).parent.mkdir(parents=True,exist_ok=True);(stage/name).write_text(body)
        # Only configuration includes need rebasing; certs/upstreams remain the real declared targets.
        main_config=(stage/'nginx.conf').read_text().replace('include /etc/nginx/','include '+str(stage)+'/')
        # Server snippets may contain includes in the original existing source.
        for folder in ('conf.d','sites-available','sites-enabled'):
            for file in (stage/folder).glob('*') if (stage/folder).exists() else []:
                if file.is_file() and not file.is_symlink():
                    file.write_text(file.read_text().replace('include /etc/nginx/','include '+str(stage)+'/'))
        (stage/'nginx.conf').write_text(main_config)
        checked(['/usr/sbin/nginx','-t','-c',str(stage/'nginx.conf')])
    if not args.apply:print(json.dumps({'changed':True,'validated':True}));return
    backup=Path('/var/backups/playsay')/('maintenance-ingress-'+str(time.time_ns()))
    backup.mkdir(parents=True,mode=0o700)
    modes={name:((ROOT/name).stat().st_mode & 0o777) if (ROOT/name).exists() else 0o644 for name in changed}
    prior={name:(ROOT/name).read_bytes() if (ROOT/name).exists() else None for name in changed}
    for name,body in prior.items():
        if body is not None:
            target=backup/name;target.parent.mkdir(parents=True,exist_ok=True,mode=0o700);target.write_bytes(body);target.chmod(0o600)
    try:
        for name,body in changed.items():
            with tempfile.NamedTemporaryFile(dir=(ROOT/name).parent,delete=False) as stream:
                target=Path(stream.name);stream.write(body.encode());stream.flush();os.fsync(stream.fileno());os.fchmod(stream.fileno(),modes[name])
            os.replace(target,ROOT/name)
        checked(['/usr/sbin/nginx','-t'])
        checked(['/usr/bin/systemctl','reload','nginx'])
    except Exception:
        for name,body in prior.items():
            if body is None:(ROOT/name).unlink(missing_ok=True)
            else:(ROOT/name).write_bytes(body)
        checked(['/usr/sbin/nginx','-t'])
        raise
    print(json.dumps({'changed':True,'validated':True,'backup':str(backup)}))


if __name__=='__main__':main()
