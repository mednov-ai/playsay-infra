"""Certificate fixtures and failure injection; never runs Certbot or remote services."""
import copy
import importlib.util
import os
from pathlib import Path
import socket
import ssl
import subprocess
import tempfile
import threading
import time
import unittest
import yaml
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('lifecycle',ROOT/'scripts/certificate-lifecycle.py')
lifecycle=importlib.util.module_from_spec(spec);spec.loader.exec_module(lifecycle)
INVENTORY=ROOT/'helm-charts/monitoring-lite/files/certificate-inventory.json'


class CertificateLifecycle(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary=tempfile.TemporaryDirectory(prefix='hs-certificate-')
        cls.directory=Path(cls.temporary.name)
        cls.cert=cls.directory/'cert.pem';cls.key=cls.directory/'key.pem'
        subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(cls.key),'-out',str(cls.cert),'-days','45',
            '-subj','/CN=online.honey.school','-addext','subjectAltName=DNS:online.honey.school'],check=True,capture_output=True)
        cls.item=copy.deepcopy(lifecycle.load_inventory(INVENTORY)[0]);cls.item['names']=['online.honey.school']
        cls.item['probes']=[{'hostname':'online.honey.school','connect':'127.0.0.1','port':443}]
        target=cls.directory/'live/online.honey.school';target.mkdir(parents=True);(target/'fullchain.pem').write_bytes(cls.cert.read_bytes())
        renewal=cls.directory/'renewal';renewal.mkdir();(renewal/'online.honey.school.conf').write_text('authenticator = webroot\n')

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def test_inventory_and_origin_coverage(self):
        entries=lifecycle.load_inventory(INVENTORY)
        self.assertEqual(len(entries),11)
        origin=entries[0]
        self.assertEqual(len(origin['names']),8)
        self.assertTrue(all(p['connect']=='65.109.55.110' for p in origin['probes']))
        self.assertEqual({i['activation'] for i in entries},{'nginx','deferred-turn'})

    def test_inventory_covers_declared_public_and_turn_routes(self):
        entries=lifecycle.load_inventory(INVENTORY)
        variables=yaml.safe_load((ROOT/'ansible/group_vars/rf_edges.yaml').read_text())
        routes=variables['rf_edge_production_routes']+variables['rf_edge_development_routes']
        expected={name for route in routes for name in [route['hostname']]+route.get('aliases',[])}
        actual={name for item in entries if item['owner']=='selectel' for name in item['names']}
        self.assertEqual(actual,expected|{'turn.honeyschool.ru','dev.turn.honeyschool.ru'})
        for environment in ['prod','dev']:
            turn=next(i for i in entries if i['activation']=='deferred-turn' and i['environment']==environment)
            marker='honey-school-dev-turn-certificate-reload-required' if environment=='dev' else 'playsay-rf-edge-media-relay-certificate-reload-required'
            self.assertEqual(Path(turn['pending_marker']).name,marker)

    def test_release_wrappers_reject_topic_without_remote_fetch(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory);(path/'inventory.yaml').write_text('all: {}\n')
            git=path/'git';git.write_text('#!/bin/sh\ncase "$1" in\n symbolic-ref) echo feature/fixture ;;\n fetch) touch "'+str(path/'unexpected-fetch')+'"; exit 97 ;;\n *) exit 0 ;;\nesac\n');git.chmod(0o755)
            env={**os.environ,'PATH':str(path)+os.pathsep+os.environ['PATH']}
            commands=[['scripts/apply-certificate-lifecycle-release.sh','--check','--owner','ax41','--inventory',str(path/'inventory.yaml')],
                      ['scripts/apply-rf-edge-release.sh','--check','--acme-only','--inventory',str(path/'inventory.yaml')]]
            for args in commands:
                result=subprocess.run(args,cwd=ROOT,env=env,capture_output=True)
                self.assertEqual(result.returncode,2,result.stderr.decode())
                self.assertFalse((path/'unexpected-fetch').exists())

    def test_real_disk_chain_and_wrong_name(self):
        result=lifecycle.disk_certificate(self.cert,['online.honey.school'],str(self.cert))
        self.assertTrue(result['valid'])
        self.assertGreater(result['expiry'],time.time()+30*86400)
        self.assertFalse(lifecycle.disk_certificate(self.cert,['ops.honey.school'],str(self.cert))['valid'])

    def test_actual_tls_validates_identity(self):
        listener=socket.socket();listener.bind(('127.0.0.1',0));listener.listen(1)
        context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);context.load_cert_chain(self.cert,self.key)
        errors=[]
        def server():
            try:
                with listener.accept()[0] as tcp:
                    with context.wrap_socket(tcp,server_side=True):pass
            except ssl.SSLError:pass
            except Exception as error:errors.append(error)
            finally:listener.close()
        thread=threading.Thread(target=server);thread.start()
        probe={'connect':'127.0.0.1','hostname':'online.honey.school','port':listener.getsockname()[1]}
        result=lifecycle.served_certificate(probe,str(self.cert));thread.join(3)
        self.assertFalse(errors)
        self.assertEqual(result['fingerprint'],lifecycle.disk_certificate(self.cert,['online.honey.school'],str(self.cert))['fingerprint'])

    def test_bad_or_missing_disk_is_fresh_failure(self):
        result=lifecycle.health(self.item,{'healthy':1},Path('/nonexistent-fixture'),str(self.cert),100)
        self.assertEqual((result['healthy'],result['checked_at']),(0,100))

    def test_wrong_chain_expiry_and_network_failure(self):
        for disk in [{'expiry':99,'valid':True,'fingerprint':'one'},{'expiry':200,'valid':False,'fingerprint':'one'}]:
            with patch.object(lifecycle,'disk_certificate',return_value=disk),patch.object(lifecycle,'served_certificate',return_value={'expiry':200,'fingerprint':'one'}):
                self.assertEqual(lifecycle.health(self.item,{},self.directory,str(self.cert),100)['healthy'],0)
        with patch.object(lifecycle,'served_certificate',side_effect=ssl.SSLError('fixture')):
            self.assertEqual(lifecycle.health(self.item,{},self.directory,str(self.cert),100)['healthy'],0)

    def test_disk_served_mismatch_retains_first_observation(self):
        with patch.object(lifecycle,'disk_certificate',return_value={'expiry':200,'valid':True,'fingerprint':'one'}),patch.object(lifecycle,'served_certificate',return_value={'expiry':200,'fingerprint':'two'}):
            first=lifecycle.health(self.item,{},self.directory,str(self.cert),100)
            second=lifecycle.health(self.item,first,self.directory,str(self.cert),110)
        self.assertEqual((second['matching'],second['mismatch_since']),(0,100))

    def test_turn_marker_never_restarts_media(self):
        item=copy.deepcopy(self.item);item['activation']='deferred-turn';marker=self.directory/'marker';marker.touch();item['pending_marker']=str(marker)
        with patch.object(lifecycle,'served_certificate',side_effect=OSError()):
            result=lifecycle.health(item,{},self.directory,str(self.cert),int(time.time()))
        marker.unlink()
        self.assertGreater(result['pending_since'],0)
        self.assertEqual(result['healthy'],0)

    def test_noop_and_failed_renewals_are_distinct(self):
        real=lifecycle.command
        for code,success,outcome in [(0,1,'not_due'),(1,0,'failed')]:
            def run(args,timeout=300):
                if args[0]=='certbot':return subprocess.CompletedProcess(args,code,b'private provider output',b'')
                return real(args,timeout)
            with patch.object(lifecycle,'command',side_effect=run):
                result=lifecycle.renew_one(self.item,self.directory,str(self.cert),int(time.time()))
            self.assertEqual((result['success'],result['outcome']),(success,outcome))
            self.assertNotIn('private',str(result))

    def test_weekly_rehearsal_disables_activation_hooks(self):
        seen=[];real=lifecycle.command
        def run(args,timeout=300):
            if args[0]=='certbot':
                seen.extend(args);return subprocess.CompletedProcess(args,0,b'',b'')
            return real(args,timeout)
        with patch.object(lifecycle,'command',side_effect=run):
            result=lifecycle.renew_one(self.item,self.directory,str(self.cert),int(time.time()),True)
        self.assertEqual(result['outcome'],'rehearsed')
        self.assertIn('--no-directory-hooks',seen)
        self.assertIn('--no-random-sleep-on-renew',seen)
        self.assertNotIn('--run-deploy-hooks',seen)
        self.assertNotIn('--force-renewal',seen)

    def test_one_failure_does_not_skip_other_lineages_and_resolves(self):
        second={**self.item,'lineage':'honey.school'};state={}
        with patch.object(lifecycle,'renew_one',side_effect=[{'checked_at':100,'success':0},{'checked_at':100,'success':1}]):
            lifecycle.process_renewals([self.item,second],state,self.directory,str(self.cert),100)
        self.assertEqual(state[self.item['lineage']]['renewal']['failure_since'],100)
        self.assertEqual(state[second['lineage']]['renewal']['success'],1)
        with patch.object(lifecycle,'renew_one',return_value={'checked_at':200,'success':1}):
            lifecycle.process_renewals([self.item],state,self.directory,str(self.cert),200)
        self.assertEqual(state[self.item['lineage']]['renewal']['failure_since'],0)

    def test_activation_skips_duplicate_reload_and_blocks_invalid_nginx(self):
        with patch.object(lifecycle,'disk_certificate',return_value={'fingerprint':'one'}),patch.object(lifecycle,'served_certificate',return_value={'fingerprint':'one'}),patch.object(lifecycle,'command') as run:
            self.assertTrue(lifecycle.activate(self.item,self.directory,str(self.cert)))
            run.assert_not_called()
        with patch.object(lifecycle,'disk_certificate',return_value={'fingerprint':'one'}),patch.object(lifecycle,'served_certificate',return_value={'fingerprint':'two'}),patch.object(lifecycle,'command',return_value=subprocess.CompletedProcess([],1)) as run:
            self.assertFalse(lifecycle.activate(self.item,self.directory,str(self.cert)))
            self.assertEqual(run.call_args_list[0].args[0],['nginx','-t'])
            self.assertEqual(run.call_count,1)

    def test_turn_activation_only_sets_marker(self):
        item={**self.item,'activation':'deferred-turn','pending_marker':str(self.directory/'pending')}
        with patch.object(lifecycle,'command') as run:
            self.assertTrue(lifecycle.activate(item,self.directory,str(self.cert)))
            run.assert_not_called()
        Path(item['pending_marker']).unlink()

    def test_missing_state_and_failed_state_are_not_hidden(self):
        text=lifecycle.metrics([self.item],{})
        self.assertIn('hs_certificate_health_checked_at',text)
        self.assertTrue(all(line.endswith(' 0') for line in text.splitlines() if 'activation_success' not in line))
        lifecycle.atomic_json(self.directory/'state.json',{'checked_at':1})
        self.assertEqual((self.directory/'state.json').stat().st_mode&0o777,0o600)

if __name__=='__main__':unittest.main()
