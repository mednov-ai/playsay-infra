#!/usr/bin/env python3
"""Private-container kernel packet acceptance; never use on a host network namespace."""
import argparse
import ipaddress
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import time
import uuid


def checked(args,**options):
    return subprocess.check_output(args,**options)


def line(connection):
    result=b''
    while not result.endswith(b'\n'):
        value=connection.recv(1)
        if not value:raise AssertionError('fixture peer closed')
        result+=value
        if len(result)>128:raise AssertionError('fixture protocol oversized')
    return result.strip()


def server(owner):
    assert Path('/.dockerenv').exists() and os.environ.get('HONEY_MAINTENANCE_FIXTURE')=='1'
    sys.path.insert(0,'/source')
    from host_maintenance.fence import AdmissionFence,TABLE
    control=socket.socket();relay=socket.socket();new=socket.socket()
    udp=socket.socket(type=socket.SOCK_DGRAM);media=socket.socket(type=socket.SOCK_DGRAM)
    for endpoint in (control,relay,new):endpoint.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
    port=4478 if owner=='ax41' else 3478
    control.bind(('0.0.0.0',port));control.listen();control.settimeout(30)
    relay.bind(('0.0.0.0',49152));relay.listen();relay.settimeout(30)
    new.bind(('0.0.0.0',3479));new.listen()
    udp.bind(('0.0.0.0',port));udp.settimeout(1)
    media.bind(('0.0.0.0',49152));media.settimeout(10)
    if owner=='ax41':
        rules='table ip honey_fixture_nat { chain before { type nat hook prerouting priority dstnat; tcp dport 3478 redirect to :4478; udp dport 3478 redirect to :4478; }\n}\n'
        subprocess.run(['nft','-f','-'],input=rules.encode(),check=True)
    fence=AdmissionFence(owner,Path('/tmp'))
    try:
        print('READY',flush=True)
        connection,_=control.accept();connection.settimeout(3)
        assert line(connection)==b'before';connection.sendall(b'ack\n')
        channel,_=relay.accept();channel.settimeout(15)
        fence.install_nft();assert fence.nft_closed();channel.sendall(b'closed\n')
        assert line(channel)==b'new-denied'
        assert line(channel)==b'sent'
        assert media.recvfrom(128)[0]==b'udp-relay'
        for endpoint in (connection,udp):
            try:value=endpoint.recv(128)
            except socket.timeout:pass
            else:raise AssertionError('control traffic bypassed barrier: '+repr(value))
        checked(['nft','delete','table','inet',TABLE]);channel.sendall(b'reopen\n')
        connection.settimeout(20)
        received=b''
        while b'resumed\n' not in received:received+=connection.recv(128)
        channel.sendall(b'passed\n')
        print('PASS '+owner+': existing TCP controls and new TCP/UDP controls blocked; relay TCP/UDP preserved; reopen recovers traffic',flush=True)
        connection.close();channel.close()
    finally:
        subprocess.run(['nft','delete','table','inet',TABLE],capture_output=True)
        if owner=='ax41':subprocess.run(['nft','delete','table','ip','honey_fixture_nat'],capture_output=True)
        for endpoint in (control,relay,new,udp,media):endpoint.close()


CLIENT='''target=$1
exec 3<>/dev/tcp/$target/3478
printf 'before\\n' >&3
read -r -t 20 -u 3 ack
[ "$ack" = ack ]
exec 4<>/dev/tcp/$target/49152
read -r -t 20 -u 4 stage
[ "$stage" = closed ]
if timeout 2 bash -c 'exec 5<>/dev/tcp/$1/3479' fixture "$target"; then exit 40; fi
printf 'new-denied\\n' >&4
printf 'blocked\\n' >&3
printf 'udp-blocked' >/dev/udp/$target/3478
printf 'udp-relay' >/dev/udp/$target/49152
printf 'sent\\n' >&4
read -r -t 20 -u 4 stage
[ "$stage" = reopen ]
printf 'resumed\\n' >&3
read -r -t 30 -u 4 stage
[ "$stage" = passed ]
'''


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--container');parser.add_argument('--server',choices=('ax41','selectel'));args=parser.parse_args()
    if args.server:return server(args.server)
    assert args.container and args.container.startswith('honey-maintenance-linux-')
    info=json.loads(checked(['docker','inspect',args.container]))[0]
    assert info['HostConfig']['NetworkMode']!='host'
    address=info['NetworkSettings']['IPAddress'];assert ipaddress.ip_address(address).is_private
    for owner in ('ax41','selectel'):
        name='honey-maintenance-packet-'+uuid.uuid4().hex[:10]
        process=subprocess.Popen(['docker','exec','-e','HONEY_MAINTENANCE_FIXTURE=1',args.container,'python3','/source/tests/check_maintenance_turn_fence.py','--server',owner],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        try:
            ready=process.stdout.readline().strip()
            if ready!='READY':raise AssertionError(process.stderr.read())
            result=subprocess.run(['docker','run','--rm','--name',name,'ubuntu:24.04','bash','-ec',CLIENT,'fixture',address],capture_output=True,text=True,timeout=60)
            output,error=process.communicate(timeout=30)
            assert result.returncode==0 and process.returncode==0,(result.stderr,error,output)
            print(output.strip(),flush=True)
        finally:
            subprocess.run(['docker','rm','-f',name],capture_output=True)
            if process.poll() is None:process.terminate();process.wait()


if __name__=='__main__':main()
