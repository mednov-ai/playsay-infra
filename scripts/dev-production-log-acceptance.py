#!/usr/bin/env python3
"""Authorized DEV acceptance: RF TLS client, isolated DEV tenant, temporary sanitized queue."""
import argparse, base64, datetime as dt, importlib.util, json, subprocess, time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(); p.add_argument('--ssh-key',required=True); args=p.parse_args()
collector=ROOT/'ansible/roles/production-log-collector/files/collector.py'
spec=importlib.util.spec_from_file_location('collector',collector); c=importlib.util.module_from_spec(spec); spec.loader.exec_module(c)
project=str(int(time.time())); stamp=c.utc(time.time()); events=[]
for fixture in json.loads((ROOT/'scripts/tests/fixtures/production-log-source-examples.json').read_text()):
    record=c.sanitize(fixture['source'],fixture['input']); assert record
    record['timestamp']=stamp; events.append(record)
events.append(c.sanitize('collaboration',stamp+' stdout F {"event":"connection_closed","channel":"yjs","close_class":"heartbeat","age_seconds":60,"token":"CANARY_SECRET"}'))
assert all('CANARY_SECRET' not in json.dumps(event) for event in events)
payload={'code':base64.b64encode(collector.read_bytes()).decode(),'events':events,'project':project}
remote=r'''
import base64,json,os,shlex,subprocess,tempfile,time,types
from pathlib import Path
DATA=PAYLOAD
c=types.ModuleType('collector'); exec(compile(base64.b64decode(DATA['code']),'<reviewed-collector>','exec'),c.__dict__)
secret={}
for line in Path('/etc/honeyschool/secrets/edge-log-ingest.env').read_text().splitlines():
    if '=' in line and not line.lstrip().startswith('#'):
        k,v=line.split('=',1); parts=shlex.split(v); secret[k.strip()]=parts[0] if parts else ''
with tempfile.TemporaryDirectory(prefix='honey-dev-log-acceptance-') as directory:
    root=Path(directory); box=c.Outbox(root/'spool')
    for event in DATA['events']: box.enqueue(event['source'],event)
    before=box.batch()
    failed=root/'failed.curl'; failed.write_text('url = "https://127.0.0.1:1/insert/jsonline"\n'); failed.chmod(0o600)
    assert not box.deliver(str(failed)) and before==box.batch(), 'retry did not retain stable IDs'
    target=root/'dev.curl'
    text='url = "https://dev.ops.honey.school/victoria-logs/insert/jsonline?_time_field=timestamp&_stream_fields=environment,source&_msg_field=event"\n'
    text+='user = '+json.dumps(secret['EDGE_LOG_INGEST_USERNAME']+':'+secret['EDGE_LOG_INGEST_PASSWORD'])+'\n'
    text+='resolve = "dev.ops.honey.school:443:65.109.55.110"\nheader = "AccountID: 10004"\nheader = "ProjectID: '+DATA['project']+'"\n'
    target.write_text(text); target.chmod(0o600)
    assert box.deliver(str(target)) and not box.batch(), 'DEV TLS delivery failed'
    lags=[row[0] for row in box.db.execute("SELECT value FROM gauges WHERE name='delivery_lag_seconds'")]
    assert max(lags)<=30, 'normal delivery exceeds 30 seconds'
    box.db.close()
    assert all(b'CANARY_SECRET' not in f.read_bytes() for f in (root/'spool').iterdir())
    print(json.dumps({'delivered':len(before),'sources':len({e['source'] for e in DATA['events']}),'max_ack_lag_seconds':round(max(lags),3),'retry_preserved':True,'sanitized_spool':True}))
'''
ssh=['ssh','-i',args.ssh_key,'-o','IdentitiesOnly=yes','-o','BatchMode=yes']
result=subprocess.run(ssh+['root@94.102.89.213','python3 -'],input=('PAYLOAD='+repr(payload)+'\n'+remote).encode(),capture_output=True,check=True)
print(result.stdout.decode().strip())
time.sleep(2)
query=r'''
import json,time,urllib.parse,urllib.request
url='http://127.0.0.1:32089/victoria-logs/select/logsql/query'
body=urllib.parse.urlencode({'query':'environment:prod','limit':'100'}).encode()
req=urllib.request.Request(url,data=body,headers={'AccountID':'10004','ProjectID':PROJECT})
rows=[json.loads(line) for line in urllib.request.urlopen(req,timeout=10).read().splitlines()]
assert len(rows)==7 and len({r['event_id'] for r in rows})==7
assert len({r['source'] for r in rows})==6
assert all(r['_time'].replace('Z','.000Z')[:19]==STAMP[:19] for r in rows)
assert all('CANARY_SECRET' not in json.dumps(r) for r in rows)
print(json.dumps({'receiver_records':len(rows),'source_coverage':6,'original_timestamp_preserved':True,'tenant_isolated':True}))
'''
# Key path is an operator-provided absolute path; subprocess does not shell-interpolate it.
import shlex
proxy='ssh -i '+shlex.quote(args.ssh_key)+' -o IdentitiesOnly=yes -W %h:%p root@65.109.55.110'
result=subprocess.run(ssh+['-o','ProxyCommand='+proxy,'playsay@10.60.0.30','python3 -'],input=('PROJECT='+repr(project)+'\nSTAMP='+repr(stamp)+'\n'+query).encode(),capture_output=True,check=True)
print(result.stdout.decode().strip())
