#!/usr/bin/env python3
"""Run ONLY in the disposable Linux container: real nft, signed APT, dpkg and mmap.

The caller provisions cached Ubuntu with python3/nftables/gnupg/dpkg-dev, mounts
scripts read-only at /source, adds NET_ADMIN in its private network namespace and
sets HONEY_MAINTENANCE_FIXTURE=1. No production credentials or image are used.
"""
import ctypes
from datetime import datetime
import fcntl
import gzip
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest.mock as mock

assert Path('/.dockerenv').exists() and os.environ.get('HONEY_MAINTENANCE_FIXTURE')=='1', 'disposable_container_required'
sys.path.insert(0,'/source')
from host_maintenance.agent import Agent
from host_maintenance.collect import mapped_runtime_pending,package_read_lock,package_busy
from host_maintenance.fence import AdmissionFence
from host_maintenance.model import Deferred,GUEST_FIELDS,HOST_FIELDS,TURN_FIELDS,atomic_json
from host_maintenance.packages import Planner,apt_hook_fingerprint,apt_source_fingerprint,audit_archive
from host_maintenance.worker import Worker


def command(args,**kwargs):
    result=subprocess.run(args,capture_output=True,**kwargs)
    if result.returncode:raise AssertionError('fixture_command_failed: '+args[0]+': '+result.stderr.decode()[-600:])
    return result.stdout


def archive(root,version,library,script=None):
    tree=root/('package-'+version);(tree/'DEBIAN').mkdir(parents=True)
    (tree/'DEBIAN/control').write_text('Package: honey-maintenance-fixture\nVersion: '+version+'\nArchitecture: all\nMaintainer: fixture <fixture@invalid.example>\nDescription: private disposable maintenance test\n')
    (tree/'usr/lib/honeyschool-maintenance-fixture').mkdir(parents=True)
    shutil.copyfile(library,tree/'usr/lib/honeyschool-maintenance-fixture/libfixture.so')
    if script:
        (tree/'DEBIAN/postinst').write_text(script);(tree/'DEBIAN/postinst').chmod(0o755)
    target=root/('fixture-'+version+'.deb');command(['dpkg-deb','--build','--root-owner-group',str(tree),str(target)])
    return target


class Fence:
    def __init__(self):self.flag=False
    def table(self):return None
    def closed(self):return self.flag
    def close(self,*args):self.flag=True
    def hold(self,*args):assert self.flag
    def open(self,*args):self.flag=False
    def expire_uncommitted(self,*args):pass


class Peer:
    def request(self,path,data=None):return {}


def main():
    with tempfile.TemporaryDirectory(prefix='honey-linux-fixture-') as directory:
        root=Path(directory);root.chmod(0o755)
        # Real nft syntax, atomic replacement and exact JSON interpretation on both owners.
        for owner in ('ax41','selectel'):
            fence=AdmissionFence(owner,root);fence.install_nft();assert fence.nft_closed()
            fence.install_nft();assert fence.nft_closed()
            command(['nft','delete','table','inet','honey_school_maintenance'])
        print('PASS real nft: AX41 pre-DNAT and Selectel input barriers, exact JSON and idempotence',flush=True)
        writer=['/usr/bin/python3','-c','import fcntl; f=open("/var/lib/dpkg/lock-frontend","a"); fcntl.lockf(f,fcntl.LOCK_EX|fcntl.LOCK_NB)']
        with package_read_lock():
            assert package_busy() is False
            assert subprocess.run(writer,capture_output=True).returncode!=0, 'Nested status query dropped native ownership'
        assert subprocess.run(writer,capture_output=True).returncode==0
        print('PASS retained native restart locks exclude package writers and survive nested status checks',flush=True)

        # Native APT repository is signed with a disposable fixture-only key. The root
        # fixture policy explicitly approves its exact source/key/config fingerprint.
        home=root/'gpg';home.mkdir(mode=0o700)
        command(['gpg','--batch','--homedir',str(home),'--passphrase','','--quick-gen-key','Maintenance Fixture <fixture@invalid.example>','rsa2048','sign','0'])
        key=command(['gpg','--batch','--homedir',str(home),'--export'])
        keyring=Path('/etc/apt/keyrings/honey-fixture.gpg');keyring.parent.mkdir(parents=True,exist_ok=True);keyring.write_bytes(key)
        library=next(Path('/usr/lib').glob('*/libzstd.so.1.*'))
        old=archive(root,'1.0',library);new=archive(root,'2.0',library)
        bad=archive(root,'2.1',library,'#!/bin/sh\ntouch /tmp/honey-unsupported-hook-ran\n')
        command(['dpkg','-i',str(old)])
        repo=root/'repo';pool=repo/'pool';pool.mkdir(parents=True);shutil.copyfile(new,pool/'fixture.deb')
        arch=command(['dpkg','--print-architecture']).decode().strip()
        distro=repo/'dists/noble-security';index=distro/('main/binary-'+arch);index.mkdir(parents=True)
        packages=command(['dpkg-scanpackages','pool','/dev/null'],cwd=repo)
        (index/'Packages').write_bytes(packages);(index/'Packages.gz').write_bytes(gzip.compress(packages))
        release='Origin: Ubuntu\nLabel: Ubuntu\nSuite: noble-security\nCodename: noble-security\nVersion: 24.04\nArchitectures: '+arch+'\nComponents: main\nSHA256:\n'
        for file in sorted(index.iterdir()):
            body=file.read_bytes();release+=' '+hashlib.sha256(body).hexdigest()+' '+str(len(body))+' '+str(file.relative_to(distro))+'\n'
        (distro/'Release').write_text(release)
        command(['gpg','--batch','--yes','--homedir',str(home),'--clearsign','--output',str(distro/'InRelease'),str(distro/'Release')])
        Path('/etc/apt/sources.list.d/honey-fixture.list').write_text('deb [signed-by='+str(keyring)+'] file:'+str(repo)+' noble-security main\n')
        command(['apt-get','update','-qq'])
        Path('/var/lib/apt/periodic').mkdir(parents=True,exist_ok=True);Path('/var/lib/apt/periodic/update-success-stamp').touch()
        policy={'package_names':['honey-maintenance-fixture'],'maintainer_script_sha256':[],
                'installed_trigger_sha256':[],'apt_hook_fingerprint':apt_hook_fingerprint(),
                'apt_source_fingerprint':apt_source_fingerprint()}
        try:audit_archive(bad,policy)
        except Deferred as error:assert error.code=='unsupported_package_hook'
        else:raise AssertionError('unsupported hook was accepted')
        assert not Path('/tmp/honey-unsupported-hook-ran').exists()
        state=root/'state';state.mkdir(mode=0o700);policy_file=root/'policy.json';atomic_json(policy_file,policy)
        plan=Planner(state,policy).plan();assert [p['name'] for p in plan['allowed']]==['honey-maintenance-fixture'],plan
        atomic_json(state/'package-plan.json',plan)
        configuration={'role':'ax41','enabled':True,'state_dir':str(state),'package_policy':str(policy_file),
                       'services':{},'restart_units':{'ax41':[],'selectel':[]}}
        credentials={'local':'a'*64,'server':{'ax41':'a'*64}}
        config_dir=Path('/etc/honey-school-maintenance');config_dir.mkdir(parents=True,exist_ok=True)
        atomic_json(config_dir/'config.json',configuration);atomic_json(config_dir/'keys.json',credentials)
        entry=Path('/usr/local/sbin/honey-school-maintenance-package-preflight')
        entry.write_text('#!/usr/bin/python3 -I\nimport sys\nsys.path.insert(0,"/source")\nfrom host_maintenance.cli import main\nfrom host_maintenance.model import Deferred\ntry: main("package-preflight")\nexcept Deferred as error: raise SystemExit(error.code)\n');entry.chmod(0o755)
        fence=Fence();agent=Agent(configuration,credentials,fence=fence,peer=Peer())
        def snapshot():
            now=int(time.time());lease=agent.read('coordinator')
            guest={'healthy':True,'read_started_at':now,'observed_at':now,'generation':'stable','counts':dict.fromkeys(GUEST_FIELDS,0),'next_opening_known':True,'next_opening_at':None}
            return {'guests':{'prod':guest,'dev':guest},'hosts':{h:{'healthy':True,'read_started_at':now,'observed_at':now,'generation':'stable','counts':dict.fromkeys(HOST_FIELDS,0)} for h in ('ax41','selectel')},
                    'turn':{'healthy':True,'read_started_at':now,'observed_at':now,'generation':'stable','counts':dict.fromkeys(TURN_FIELDS,0)},
                    'lease_id':lease.get('lease_id'),'lease_phase':lease.get('phase','idle'),'fenced_at':lease.get('fenced_at'),
                    'fences':{'ax41':fence.closed(),'selectel':fence.closed()}}
        agent.snapshot=snapshot
        with mock.patch('host_maintenance.agent.within_window',return_value=True) as eligible, mock.patch('host_maintenance.model.within_window',return_value=True),mock.patch('host_maintenance.worker.within_window',return_value=True),mock.patch('host_maintenance.agent.synchronized',return_value=True),mock.patch('host_maintenance.worker.synchronized',return_value=True):
            thread=threading.Thread(target=agent.serve,daemon=True);thread.start();time.sleep(.3)
            worker=Worker(configuration,credentials);worker.lease='b'*32
            worker.request('/lease/claim');worker.request('/lease/fence');worker.state('fenced')
            holder=subprocess.Popen(['/usr/bin/python3','-c','import fcntl,time; f=open("/var/lib/dpkg/lock-frontend","a"); fcntl.lockf(f,fcntl.LOCK_EX); print("ready",flush=True); time.sleep(120)'],stdout=subprocess.PIPE,text=True)
            try:
                assert holder.stdout.readline().strip()=='ready'
                try:worker.install(plan,policy)
                except Deferred as error:assert error.code=='package_lock_busy',error.code
                else:raise AssertionError('native package contention ignored')
            finally:holder.terminate();holder.wait()
            print('PASS real native frontend lock defers before a package step',flush=True)
            original=worker.proof
            def close_after_grant(*args,**kwargs):
                token=original(*args,**kwargs);eligible.return_value=False;return token
            worker.proof=close_after_grant
            try:worker.install(plan,policy)
            except Deferred as error:
                if error.code!='native_preinstall_deferred':print((state/'transaction.log').read_text(),flush=True)
                assert error.code=='native_preinstall_deferred',error.code
            else:raise AssertionError('native pre-install window guard ignored')
            assert command(['dpkg-query','-W','-f=${Version}','honey-maintenance-fixture'])==b'1.0'
            assert agent.read('coordinator')['phase']=='verifying'
            print('PASS real APT pre-invoke guard rejects window closure after grant; dpkg remains untouched',flush=True)
            eligible.return_value=True;worker.proof=original
            child=subprocess.Popen(['/usr/bin/python3','-c','import ctypes,time; ctypes.CDLL("/usr/lib/honeyschool-maintenance-fixture/libfixture.so"); time.sleep(120)'])
            try:
                time.sleep(.2);assert not mapped_runtime_pending(child.pid)
                try:worker.install(plan,policy)
                except Deferred:
                    print((state/'transaction.log').read_text(),flush=True)
                    raise
                assert command(['dpkg-query','-W','-f=${Version}','honey-maintenance-fixture'])==b'2.0'
                assert mapped_runtime_pending(child.pid), 'Package success incorrectly cleared old running mappings'
            finally:child.terminate();child.wait()
            assert agent.read('coordinator')['phase']=='verifying'
            print('PASS real signed APT install: audited versions installed; old running library remains restart debt',flush=True)
        agent.stopping.set()


if __name__=='__main__':main()
