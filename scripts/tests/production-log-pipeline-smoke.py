#!/usr/bin/env python3
"""Local-only TLS ingress + pinned VictoriaLogs smoke. No real credentials or data."""
import importlib.util
import json
import subprocess
import tempfile
import time
from pathlib import Path
import jinja2

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('collector',ROOT/'ansible/roles/production-log-collector/files/collector.py')
c=importlib.util.module_from_spec(spec); spec.loader.exec_module(c)
SUFFIX=str(__import__('os').getpid()); NET='honey-log-smoke-'+SUFFIX; VL='honey-log-vl-'+SUFFIX; NG='honey-log-nginx-'+SUFFIX
IMAGE='victoriametrics/victoria-logs@sha256:251121fa882af99b95ba0c230a4a2f412ea602d2698c64a96c58dc9842bb755d'
def run(args,**kwargs): return subprocess.run(args,check=True,capture_output=True,**kwargs)
with tempfile.TemporaryDirectory(prefix='honey-log-smoke-') as directory:
    root=Path(directory)
    run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(root/'key.pem'),'-out',str(root/'cert.pem'),'-days','1','-subj','/CN=ops.honey.school','-addext','subjectAltName=DNS:ops.honey.school'])
    password=run(['openssl','passwd','-apr1','synthetic-prod-password']).stdout.decode().strip()
    (root/'auth').write_text('synthetic-prod:'+password+'\n')
    env=jinja2.Environment(loader=jinja2.FileSystemLoader(ROOT/'ansible/roles/edge-proxy/templates'))
    snippet=env.get_template('production-log-ingress.conf.j2').render(route={'victoria_logs_ingest_trusted_peers':['172.29.210.1'],'victoria_logs_ingest_credentials_path':'/test/auth','victoria_logs_upstream':VL+':9428','victoria_metrics_upstream':VL+':9428'},edge_vpn_subnet='10.250.0.0/24')
    (root/'nginx.conf').write_text('events {}\nhttp { server { listen 443 ssl; server_name ops.honey.school; ssl_certificate /test/cert.pem; ssl_certificate_key /test/key.pem;\n'+snippet+'\n} }\n')
    (root/'ingest.curl').write_text('url = "https://ops.honey.school:18443/victoria-logs/insert/jsonline"\nuser = "synthetic-prod:synthetic-prod-password"\ncacert = "'+str(root/'cert.pem')+'"\nresolve = "ops.honey.school:18443:127.0.0.1"\n')
    def curl(path, data=None, auth=None):
        args=['curl','--silent','--cacert',str(root/'cert.pem'),'--resolve','ops.honey.school:18443:127.0.0.1','-w','%{http_code}','-o',str(root/'response'),'https://ops.honey.school:18443'+path]
        if auth: args+=['--user',auth]
        if data is not None: args+=['--data-binary',data]
        return run(args).stdout.decode()
    try:
        run(['docker','network','create','--subnet','172.29.210.0/24',NET])
        run(['docker','run','-d','--name',VL,'--network',NET,'-p','127.0.0.1:19428:9428',IMAGE,'-http.pathPrefix=/victoria-logs','-retentionPeriod=7d','-retention.maxDiskSpaceUsageBytes=8589934592','-storage.minFreeDiskSpaceBytes=1073741824'])
        for _ in range(30):
            response=subprocess.run(['curl','-sf','http://127.0.0.1:19428/victoria-logs/health'],capture_output=True)
            if response.returncode==0: break
            time.sleep(.2)
        else: raise RuntimeError('local storage did not become healthy')
        run(['docker','run','-d','--name',NG,'--network',NET,'-p','127.0.0.1:18443:443','-v',directory+':/test:ro','nginx:1.27-alpine','nginx','-g','daemon off;','-c','/test/nginx.conf'])
        for _ in range(30):
            try:
                if curl('/victoria-logs/insert/jsonline','{}') in ('401','403'): break
            except subprocess.CalledProcessError: pass
            time.sleep(.2)
        else: raise RuntimeError('local TLS ingress did not become ready')
        assert curl('/victoria-logs/insert/jsonline','{}')=='401'
        assert curl('/victoria-logs/insert/jsonline','{}','synthetic-dev:synthetic-dev-password')=='401'
        assert curl('/victoria-logs/select/logsql/query')=='403'
        assert curl('/victoria-logs/internal/force_flush')=='403'
        assert curl('/victoria-logs/select/vmalert/-/reload')=='403'
        assert curl('/victoria-logs/insert/jsonline',auth='synthetic-prod:synthetic-prod-password')=='403'
        # An untrusted source IP cannot bypass allowlist even with production auth.
        forbidden=subprocess.run(['docker','exec',NG,'wget','-S','-O','/dev/null','--no-check-certificate','--post-data={}','https://127.0.0.1/victoria-logs/insert/jsonline'],capture_output=True)
        assert forbidden.returncode != 0 and b'403' in forbidden.stderr, forbidden.stderr
        box=c.Outbox(root/'spool')
        fixtures=json.loads((ROOT/'scripts/tests/fixtures/production-log-source-examples.json').read_text())
        for fixture in fixtures:
            record=c.sanitize(fixture['source'],fixture['input']); assert record is not None
            box.enqueue(fixture['source'],record)
        lifecycle=c.sanitize('collaboration','2026-10-04T09:49:01+03:00 stdout F {"event":"connection_closed","channel":"yjs","close_class":"heartbeat","age_seconds":60,"token":"CANARY_SECRET"}')
        box.enqueue('collaboration',lifecycle)
        before=box.batch(); assert box.deliver(str(root/'ingest.curl')); assert not box.batch()
        # Replay the same IDs: incident query must count logical events once.
        payload='\n'.join(row[1] for row in before)+'\n'
        assert curl('/victoria-logs/insert/jsonline',payload,'synthetic-prod:synthetic-prod-password')=='200'
        run(['curl','-sf','-X','POST','http://127.0.0.1:19428/victoria-logs/internal/force_flush'])
        time.sleep(2)
        result=run(['curl','-sf','http://127.0.0.1:19428/victoria-logs/select/logsql/query','--data-urlencode','query=environment:prod','--data-urlencode','start=2026-10-04T06:48:00Z','--data-urlencode','end=2026-10-04T06:50:00Z','--data-urlencode','limit=100']).stdout
        rows=[json.loads(line) for line in result.splitlines()]
        assert len(rows)==14, len(rows)
        assert len({row['event_id'] for row in rows})==7
        assert {row['source'] for row in rows}==set(c.SOURCES)
        assert b'CANARY_SECRET' not in result
        for row in rows: assert row['_time'].startswith('2026-10-04T06:')
        print('PASS: pinned storage, TLS verification, prod/dev/public access isolation, six sources + collaboration lifecycle, timestamps, privacy, stable retry IDs')
    finally:
        subprocess.run(['docker','rm','-f',NG,VL],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        subprocess.run(['docker','network','rm',NET],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
