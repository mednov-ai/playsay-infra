#!/usr/bin/env python3
"""Real nginx upgrade/keep-alive/fence/reload behavior in private disposable containers."""
import argparse
import http.client
import importlib.util
import json
from pathlib import Path
import re
import socket
import subprocess
import tempfile
import time
import uuid


def docker(*args, **kwargs):
    return subprocess.check_output(['docker',*args],text=True,**kwargs).strip()


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--proxy-image',default='nginx:stable-alpine');args=parser.parse_args()
    prefix='honey-maintenance-test-'+uuid.uuid4().hex[:12]
    network=prefix+'-net';backend=prefix+'-backend';proxy=prefix+'-proxy'
    with tempfile.TemporaryDirectory() as directory:
        root=Path(directory);root.chmod(0o755)
        spec=importlib.util.spec_from_file_location('ingress_owner',Path(__file__).resolve().parents[1]/'install-maintenance-ingress.py')
        owner=importlib.util.module_from_spec(spec);spec.loader.exec_module(owner)
        admission=owner.ADMISSION.replace('/var/lib/honey-school-maintenance-admission/closed','/fixture/closed')
        (root/'nginx.conf').write_text('events {}\nhttp { server { listen 81; location = /status { stub_status; } }\nserver { listen 82; location / { return 200 "login"; } }\nserver { listen 80;\n'+admission+'''
location ^~ /.well-known/acme-challenge/ { return 200 "acme"; }
location = /cabinet { return 200 "ok"; }
location = /socket {
proxy_pass http://backend:8080; proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection upgrade;
} } }''')
        (root/'nginx.conf').chmod(0o644)
        try:
            docker('network','create',network)
            docker('run','-d','--name',backend,'--network',network,'--network-alias','backend',
                   '--entrypoint','/bin/sh','nginx:stable-alpine','-c',
                   '(printf "HTTP/1.1 101 Switching Protocols\\r\\nUpgrade: websocket\\r\\nConnection: Upgrade\\r\\n\\r\\n"; sleep 120) | nc -l -p 8080')
            docker('run','-d','--name',proxy,'--network',network,'-p','127.0.0.1::80','-p','127.0.0.1::81','-p','127.0.0.1::82',
                   '-v',str(root)+':/fixture:ro','-v',str(root/'nginx.conf')+':/etc/nginx/nginx.conf:ro',
                   '--entrypoint','/usr/sbin/nginx',args.proxy_image,'-g','daemon off;')
            info=json.loads(docker('inspect',proxy))[0]
            if not info['State']['Running']:
                raise AssertionError(docker('logs',proxy,stderr=subprocess.STDOUT))
            port=int(info['NetworkSettings']['Ports']['80/tcp'][0]['HostPort'])
            status_port=int(info['NetworkSettings']['Ports']['81/tcp'][0]['HostPort'])
            login_port=int(info['NetworkSettings']['Ports']['82/tcp'][0]['HostPort'])
            def request(path,other=None):
                client=http.client.HTTPConnection('127.0.0.1',other or (status_port if path=='/status' else port),timeout=3)
                client.request('GET',path);response=client.getresponse();status=response.status;body=response.read().decode();client.close()
                return status,body
            for _ in range(30):
                try:
                    if request('/status')[0]==200:break
                except OSError:pass
                time.sleep(0.1)
            tunnel=socket.create_connection(('127.0.0.1',port),timeout=3)
            try:
                tunnel.sendall(b'GET /socket HTTP/1.1\r\nHost: local\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n')
                assert b' 101 ' in tunnel.recv(4096)
                assert 'Writing: 2' in request('/status')[1], 'An idle upgraded connection was not counted'
                (root/'closed').touch(mode=0o644)
                assert request('/.well-known/acme-challenge/probe')[0]==200, 'ACME was blocked'
                assert request('/login',login_port)[0]==200, 'SSO was blocked'
                assert request('/cabinet')[0]==503, 'New cabinet admission bypassed the fence'
                assert 'Writing: 2' in request('/status')[1], 'Fencing terminated or hid the existing tunnel'
                docker('exec',proxy,'nginx','-s','reload',stderr=subprocess.DEVNULL)
                time.sleep(0.2)
                assert 'Writing: 2' in request('/status')[1], 'Reload lost old-worker activity'
                (root/'closed').unlink()
                assert request('/cabinet')[0]==200
            finally:tunnel.close()
            for _ in range(20):
                if 'Writing: 1' in request('/status')[1]:break
                time.sleep(0.1)
            else:raise AssertionError('Closed upgrade did not drain')
            idle=http.client.HTTPConnection('127.0.0.1',port,timeout=3)
            idle.request('GET','/cabinet');idle.getresponse().read()
            text=request('/status')[1]
            assert 'Writing: 1' in text and int(re.search(r'Waiting: (\d+)',text)[1])>=1
            idle.close()
            print('PASS: upgrades counted across reload; fence rejects new requests and preserves old tunnels; idle keep-alive is not active work')
        finally:
            for name in (proxy,backend):
                subprocess.run(['docker','rm','-f',name],capture_output=True)
            subprocess.run(['docker','network','rm',network],capture_output=True)


if __name__=='__main__':main()
