import copy
import json
from pathlib import Path
import secrets
import sys
import tempfile
import unittest
import unittest.mock
from datetime import datetime,timezone

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from host_maintenance.model import (Deferred, GUEST_FIELDS, HOST_FIELDS, TURN_FIELDS, Journal, reserve,
                                    service_debt, two_zero_observations, within_window)
from host_maintenance.wire import Authenticator, Client, mac


class Gates(unittest.TestCase):
    def snapshot(self, stamp):
        guest={'healthy':True,'read_started_at':stamp,'observed_at':stamp,'generation':'stable',
               'counts':dict.fromkeys(GUEST_FIELDS,0),'next_opening_known':True,'next_opening_at':None}
        return {'hosts':{h:{'healthy':True,'read_started_at':stamp,'observed_at':stamp,'generation':'stable','counts':dict.fromkeys(HOST_FIELDS,0)} for h in ('ax41','selectel')},'guests':{'prod':copy.deepcopy(guest),'dev':copy.deepcopy(guest)},
                'turn':{'healthy':True,'read_started_at':stamp,'observed_at':stamp,'generation':'stable','counts':dict.fromkeys(TURN_FIELDS,0)},
                'fences':{'ax41':True,'selectel':True},'lease_phase':'fenced','fenced_at':970,'lease_id':'a'*32}

    def test_each_producer_must_advance_and_remain_fresh(self):
        first, second=self.snapshot(980),self.snapshot(995)
        two_zero_observations(first,second,1000,900)
        for guest in ('prod','dev'):
            bad=copy.deepcopy(second);bad['guests'][guest]['observed_at']=980;bad['guests'][guest]['read_started_at']=980
            with self.assertRaisesRegex(Deferred,'observation_spacing'):
                two_zero_observations(first,bad,1000,900)
        # A newly published heartbeat cannot refresh an overlapping old read.
        overlapping=copy.deepcopy(second);overlapping['guests']['prod']['read_started_at']=980
        with self.assertRaisesRegex(Deferred,'observation_spacing'):two_zero_observations(first,overlapping,1000,900)
        with self.assertRaisesRegex(Deferred,'source_stale'):
            two_zero_observations(first,second,1011,900)

    def test_busy_missing_generation_change_and_partial_fences_deny(self):
        first, second=self.snapshot(980),self.snapshot(995)
        mutations=[lambda x:x['guests']['prod']['counts'].update(lesson_windows=1),
                   lambda x:x['guests']['dev']['counts'].update(external_connections=1),
                   lambda x:x['guests']['prod']['counts'].update(unknown_deadlines=1),
                   lambda x:x['turn']['counts'].update(control_connections=1),
                   lambda x:x['turn']['counts'].update(dev_relay_sockets=1),
                   lambda x:x['fences'].update(selectel=False),
                   lambda x:x['guests']['dev'].update(healthy=False),
                   lambda x:x['guests']['dev'].update(generation='new'),
                   lambda x:x['guests']['dev'].update(next_opening_at=2019),
                   lambda x:x['guests']['dev'].update(next_opening_known=False)]
        for mutation in mutations:
            bad=copy.deepcopy(second);mutation(bad)
            with self.assertRaises(Deferred):two_zero_observations(first,bad,1000,900)

    def test_pre_fence_positive_samples_wait_for_a_new_epoch_without_becoming_zero(self):
        from host_maintenance.model import validate_snapshot
        sample=self.snapshot(995);sample['fenced_at']=998
        sample['hosts']['selectel']['counts']['ingress_writing']=1
        preserved=copy.deepcopy(sample)
        with self.assertRaisesRegex(Deferred,'observations_precede_fence'):
            validate_snapshot(sample,1000,900)
        self.assertEqual(sample,preserved)
        # Before admission closes, the identical busy sample must deny claiming.
        with self.assertRaisesRegex(Deferred,'activity_busy'):
            validate_snapshot(sample,1000,900,require_fence=False)
        fresh=self.snapshot(1000);fresh['fenced_at']=998
        fresh['hosts']['selectel']['counts']['ingress_writing']=1
        with self.assertRaisesRegex(Deferred,'activity_busy'):
            validate_snapshot(fresh,1000,900)
        fresh['hosts']['selectel']['counts']['ingress_writing']=0
        later=self.snapshot(1011);later['fenced_at']=998
        two_zero_observations(fresh,later,1011,900)

    def test_unknown_prefence_data_is_never_an_epoch_retry_or_a_zero(self):
        from host_maintenance.model import validate_snapshot
        for mutation,reason in [(lambda x:x['guests']['prod'].update(healthy=False),'source_unhealthy'),
                                (lambda x:x['turn']['counts'].pop('control_connections'),'source_malformed'),
                                (lambda x:x['hosts']['ax41'].update(read_started_at=900),'source_stale')]:
            sample=self.snapshot(995);sample['fenced_at']=998;mutation(sample)
            with self.assertRaisesRegex(Deferred,reason):validate_snapshot(sample,1000,900)

    def test_window_checks_budget_clock_and_five_am(self):
        stamp=lambda x:datetime.fromisoformat('2026-10-24T'+x).replace(tzinfo=timezone.utc).timestamp()
        self.assertTrue(within_window(stamp('00:00:00'),True,1020))
        self.assertFalse(within_window(stamp('01:43:00'),True,1020))
        self.assertFalse(within_window(stamp('02:00:00'),True))
        self.assertFalse(within_window(stamp('06:32:00'),True))
        self.assertFalse(within_window(stamp('00:00:00'),False))

    def test_expired_cross_host_lease_is_never_stolen(self):
        now=datetime(2026,10,24,0,0,tzinfo=timezone.utc).timestamp()
        with tempfile.TemporaryDirectory() as root:
            journal=Journal(root)
            reserve(journal,'ax41','a'*32,now,True)
            with self.assertRaisesRegex(Deferred,'lease_busy'):
                reserve(journal,'selectel','b'*32,now+3600,True)
            with journal.locked('coordinator') as state:self.assertEqual(state['owner'],'ax41')
            (Path(root)/'coordinator.json').write_text('broken')
            with self.assertRaises(ValueError):reserve(journal,'selectel','b'*32,now,True)

    def test_unknown_service_debt_preserves_age_and_reload_is_not_clearance(self):
        old=service_debt({}, {'nginx':{'pending':True,'process_started':'1'}},100)
        again=service_debt(old,{'nginx':{'pending':True,'process_started':'1'}},200)
        failed=service_debt(again,{'nginx':None},300)
        self.assertEqual(failed['nginx']['first_pending_at'],100)
        self.assertFalse(failed['nginx']['healthy'])
        reload=service_debt(failed,{'nginx':{'pending':False,'process_started':'1'}},350)
        self.assertEqual(reload['nginx']['first_pending_at'],100)
        self.assertTrue(reload['nginx']['pending'])
        clear=service_debt(failed,{'nginx':{'pending':False,'process_started':'2'}},400)
        self.assertNotIn('first_pending_at',clear['nginx'])


class Authentication(unittest.TestCase):
    def test_signature_binds_body_path_time_actor_and_nonce(self):
        key=secrets.token_hex(32);auth=Authenticator({'prod':key})
        nonce='a'*32; body=b'{}'
        headers={'X-Honey-Actor':'prod','X-Honey-Time':'1000','X-Honey-Nonce':nonce,
                 'X-Honey-MAC':mac(key,'POST','/activity','1000',nonce,body)}
        self.assertEqual(auth.verify('POST','/activity',headers,body,1000),'prod')
        with self.assertRaisesRegex(Deferred,'request_replayed'):auth.verify('POST','/activity',headers,body,1000)
        for method,path,payload,now in [('POST','/lease/claim',body,1000),('POST','/activity',b'{"x":1}',1000),('POST','/activity',body,1031)]:
            with self.assertRaises(Deferred):Authenticator({'prod':key}).verify(method,path,headers,payload,now)

    def test_control_cannot_follow_remote_plaintext_or_undeclared_destination(self):
        for endpoint,address in [('http://94.102.89.213',None),('https://example.com','65.109.55.110'),
                                 ('https://ops.honey.school','127.0.0.1'),('https://user:secret@ops.honey.school','65.109.55.110')]:
            with self.assertRaises(ValueError):Client(endpoint,'prod','a'*64,address)



class PersistentAuthentication(unittest.TestCase):
    def test_restart_does_not_reset_nonce_replay_cache(self):
        key='a'*64;nonce='b'*32;body=b'{}'
        headers={'X-Honey-Actor':'prod','X-Honey-Time':'1000','X-Honey-Nonce':nonce,
                 'X-Honey-MAC':mac(key,'POST','/activity','1000',nonce,body)}
        with tempfile.TemporaryDirectory() as root:
            self.assertEqual(Authenticator({'prod':key},Journal(root)).verify('POST','/activity',headers,body,1000),'prod')
            with self.assertRaisesRegex(Deferred,'request_replayed'):
                Authenticator({'prod':key},Journal(root)).verify('POST','/activity',headers,body,1001)


class Protocol(unittest.TestCase):
    def setUp(self):
        from host_maintenance.agent import Agent
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)
        self.now=datetime(2026,10,24,0,0,tzinfo=timezone.utc).timestamp()
        self.closed=False;self.peer_closed=False;self.fail_open=False
        parent=self
        class Fence:
            def table(self):return None
            def closed(self):return parent.closed
            def close(self,*args):parent.closed=True
            def hold(self,*args):pass
            def open(self,*args):parent.closed=False
        class Peer:
            def request(self,path,data=None):
                if path=='/fence/close':parent.peer_closed=True
                elif path=='/fence/open':
                    if parent.fail_open:raise Deferred('control_unavailable')
                    parent.peer_closed=False
                return {}
        self.agent=Agent({'role':'ax41','state_dir':str(self.root),'enabled':True,'restart_units':{'ax41':['nginx'],'selectel':['coturn']}},
                         {'server':{'ax41':'a'*64}},clock=lambda:self.now,fence=Fence(),peer=Peer())
        self.sample=Gates().snapshot(int(self.now))
        self.sample['lease_id']='a'*32;self.sample['fenced_at']=int(self.now)-20
        self.agent.snapshot=lambda:copy.deepcopy(self.sample)
        self.sync=unittest.mock.patch('host_maintenance.agent.synchronized',return_value=True)
        self.busy=unittest.mock.patch('host_maintenance.agent.package_busy',return_value=False)
        self.sync.start();self.busy.start()

    def tearDown(self):self.sync.stop();self.busy.stop();self.temp.cleanup()

    def own(self,phase='fenced',**fields):
        with self.agent.journal.locked('coordinator') as state:
            state.update(owner='ax41',lease_id='a'*32,phase=phase,**fields)

    def test_each_critical_step_needs_independent_post_fence_proof(self):
        self.own()
        result=self.agent.dispatch('ax41','/lease/step',{'lease_id':'a'*32,'operation':'restart','service':'nginx'})
        self.assertFalse(result['eligible'])
        self.now+=11
        self.sample=Gates().snapshot(int(self.now));self.sample['fenced_at']=int(self.now)-31
        # Lease identity/fence epoch must remain stable across both samples.
        self.sample['fenced_at']=int(self.now)-31
        result=self.agent.dispatch('ax41','/lease/step',{'lease_id':'a'*32,'operation':'restart','service':'nginx'})
        self.assertTrue(result['eligible'])
        with self.assertRaisesRegex(Deferred,'lease_phase_invalid'):
            self.agent.dispatch('ax41','/lease/step',{'lease_id':'a'*32,'operation':'restart','service':'nginx'})
        with self.assertRaisesRegex(Deferred,'step_still_running'):
            self.agent.release('ax41','a'*32)

    def test_prefence_busy_sample_never_becomes_a_zero_baseline(self):
        self.own();epoch=int(self.now)+1;self.sample['fenced_at']=epoch
        self.sample['hosts']['selectel']['counts']['ingress_writing']=1
        with self.assertRaisesRegex(Deferred,'observations_precede_fence'):
            self.agent.observe_zero('ax41','a'*32,120)
        self.assertNotIn('zero_baseline',self.agent.read('coordinator'))
        self.now+=4;self.sample=Gates().snapshot(int(self.now));self.sample['fenced_at']=epoch
        self.assertFalse(self.agent.observe_zero('ax41','a'*32,120)['eligible'])
        self.now+=11;self.sample=Gates().snapshot(int(self.now));self.sample['fenced_at']=epoch
        self.assertTrue(self.agent.observe_zero('ax41','a'*32,120)['eligible'])

    def test_cached_token_or_new_activity_invalidates_native_preflight(self):
        self.own('step_running',step_id='c'*32,operation='install',step_granted_at=int(self.now),proof_generation=['stable']*5)
        data={'lease_id':'a'*32,'step_id':'c'*32,'operation':'install'}
        self.sample['lease_phase']='step_running'
        self.assertTrue(self.agent.dispatch('ax41','/lease/preflight',data)['ready'])
        for source,field in [('prod','direct_turn_relay_sockets'),('dev','external_connections')]:
            self.sample['guests'][source]['counts'][field]=1
            with self.assertRaisesRegex(Deferred,'activity_busy'):self.agent.dispatch('ax41','/lease/preflight',data)
            self.sample['guests'][source]['counts'][field]=0
        self.now+=16
        with self.assertRaisesRegex(Deferred,'step_grant_stale'):self.agent.dispatch('ax41','/lease/preflight',data)

    def test_source_generation_change_resets_baseline_durably(self):
        self.own();self.agent.observe_zero('ax41','a'*32,120)
        self.now+=11;self.sample=Gates().snapshot(int(self.now));self.sample['fenced_at']=int(self.now)-31
        self.sample['guests']['dev']['generation']='new'
        with self.assertRaisesRegex(Deferred,'source_generation_changed'):self.agent.observe_zero('ax41','a'*32,120)
        self.assertEqual(self.agent.read('coordinator')['zero_baseline']['guests']['dev']['generation'],'new')

    def test_partial_release_can_retry_but_never_steal_or_skip_verification(self):
        self.closed=True;self.peer_closed=True
        self.own('verifying',destructive_started=True)
        with self.assertRaisesRegex(Deferred,'runtime_not_verified'):self.agent.release('ax41','a'*32)
        self.own('verified',destructive_started=True)
        self.fail_open=True
        with self.assertRaisesRegex(Deferred,'control_unavailable'):self.agent.release('ax41','a'*32)
        self.assertTrue(self.closed)
        self.fail_open=False
        self.assertEqual(self.agent.release('ax41','a'*32)['phase'],'idle')
        self.assertFalse(self.closed)

    def test_lost_completion_ack_does_not_renew_time_or_finish_a_new_step(self):
        self.own('step_running',step_id='c'*32,destructive_started=True)
        data={'lease_id':'a'*32,'step_id':'c'*32,'success':True}
        self.agent.dispatch('ax41','/lease/complete-step',data)
        completed=self.agent.read('coordinator')['last_step_completed_at']
        self.now+=5
        self.agent.dispatch('ax41','/lease/complete-step',data)
        self.assertEqual(self.agent.read('coordinator')['last_step_completed_at'],completed)
        self.own('step_running',step_id='d'*32)
        self.agent.dispatch('ax41','/lease/complete-step',data)
        self.assertEqual(self.agent.read('coordinator')['phase'],'step_running')
        with self.assertRaises(Deferred):
            self.agent.dispatch('selectel','/lease/complete-step',data)

    def test_lost_release_ack_cannot_touch_a_later_lease(self):
        self.own('fenced');self.closed=True;self.peer_closed=True
        self.agent.release('ax41','a'*32)
        self.own('step_running')
        with self.agent.journal.locked('coordinator') as state:state['lease_id']='b'*32
        self.closed=True;self.peer_closed=True
        self.assertEqual(self.agent.release('ax41','a'*32)['phase'],'idle')
        self.assertTrue(self.closed);self.assertTrue(self.peer_closed)
        self.assertEqual(self.agent.read('coordinator')['lease_id'],'b'*32)

    def test_guest_cannot_issue_host_or_other_guest_operations(self):
        with self.assertRaisesRegex(Deferred,'role_forbidden'):self.agent.dispatch('prod','/lease/claim',{})
        sample=copy.deepcopy(self.sample['guests']['prod']);sample['generation']='a'*64
        self.agent.dispatch('prod','/activity',sample)
        with self.assertRaisesRegex(Deferred,'source_did_not_advance'):self.agent.dispatch('prod','/activity',sample)
        sample['private_data']='forbidden'
        with self.assertRaisesRegex(Deferred,'source_schema_invalid'):self.agent.dispatch('prod','/activity',sample)



class FenceRecovery(unittest.TestCase):
    def test_preinstall_barrier_expires_but_committed_barrier_never_expires(self):
        from host_maintenance.fence import AdmissionFence
        from host_maintenance.model import atomic_json
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);marker=root/'closed'
            fence=AdmissionFence('ax41',root)
            with unittest.mock.patch('host_maintenance.fence.MARKER',marker),unittest.mock.patch.object(fence,'table',return_value=None),unittest.mock.patch.object(fence,'nft_closed',return_value=True),unittest.mock.patch('host_maintenance.fence.tls_status',return_value=(503,'closed','60')):
                marker.touch();atomic_json(fence.record,{'lease_id':'a'*32,'owner':'ax41','armed_at':100,'committed':False})
                fence.expire_uncommitted(159);self.assertTrue(marker.exists())
                fence.expire_uncommitted(160);self.assertFalse(marker.exists())
                marker.touch();atomic_json(fence.record,{'lease_id':'b'*32,'owner':'selectel','armed_at':200,'committed':False})
                fence.hold('b'*32);fence.expire_uncommitted(999999)
                self.assertTrue(marker.exists());self.assertTrue(json.loads(fence.record.read_text())['committed'])
                with self.assertRaisesRegex(Deferred,'other_lease'):fence.open('c'*32)
                self.assertTrue(marker.exists())



class PrivilegedReadBoundary(unittest.TestCase):
    def test_caller_basename_cannot_select_a_privileged_operation(self):
        import contextlib,io
        from host_maintenance import cli
        with tempfile.TemporaryDirectory() as directory:
            config=Path(directory)/'config.json';config.write_text('{"role":"prod"}')
            with unittest.mock.patch.object(cli,'CONFIG',config),unittest.mock.patch('sys.argv',['/tmp/honey-school-maintenance-execute']),unittest.mock.patch('os.geteuid',return_value=0),unittest.mock.patch('host_maintenance.collect.GuestCollector') as reader,unittest.mock.patch('host_maintenance.worker.Worker') as worker,contextlib.redirect_stdout(io.StringIO()):
                reader.return_value.collect.return_value={'healthy':False}
                cli.main('guest-read')
                reader.assert_called_once_with('prod');worker.assert_not_called()
            with unittest.mock.patch.object(cli,'CONFIG',config),unittest.mock.patch('sys.argv',['reader','extra']):
                with self.assertRaisesRegex(SystemExit,'arguments_not_allowed'):cli.main('guest-read')

    def test_listen_backlog_capacity_is_not_queued_control_data(self):
        from host_maintenance.collect import direct_turn_snapshot
        configuration='listening-port=3478\nmin-port=49152\nmax-port=49999\n'
        listen='tcp LISTEN 0 4096 0.0.0.0:3478 0.0.0.0:*'
        with unittest.mock.patch('host_maintenance.collect.unit_properties',return_value={'ActiveState':'active','MainPID':'100'}),unittest.mock.patch('pathlib.Path.read_text',return_value=configuration),unittest.mock.patch('host_maintenance.collect.run',return_value=listen) as sockets:
            self.assertEqual(direct_turn_snapshot('prod'),{'direct_turn_relay_sockets':0,'direct_turn_control_connections':0,'direct_turn_control_queued_bytes':0})
            sockets.return_value=listen+'\n'+'udp UNCONN 3 7 0.0.0.0:3478 0.0.0.0:*\n'+'tcp ESTAB 1 0 0.0.0.0:3478 127.0.0.1:50000\n'+'udp UNCONN 0 0 0.0.0.0:49152 0.0.0.0:*'
            self.assertEqual(direct_turn_snapshot('prod'),{'direct_turn_relay_sockets':1,'direct_turn_control_connections':1,'direct_turn_control_queued_bytes':11})


class PeerAuthority(unittest.TestCase):
    def test_peer_barrier_requires_the_matching_coordinator_phase(self):
        from host_maintenance.agent import Agent
        with tempfile.TemporaryDirectory() as directory:
            fence=unittest.mock.Mock();fence.closed.return_value=True
            config={'role':'selectel','state_dir':directory,'coordinator_url':'https://ops.honey.school/__host_maintenance__','coordinator_address':'65.109.55.110'}
            agent=Agent(config,{'server':{'ax41':'a'*64},'coordinator':'b'*64},fence=fence)
            agent.coordinator=unittest.mock.Mock();agent.coordinator.request.return_value={'owner':'ax41','phase':'idle'}
            with unittest.mock.patch('host_maintenance.agent.within_window',return_value=True),unittest.mock.patch('host_maintenance.agent.synchronized',return_value=True),unittest.mock.patch('host_maintenance.agent.package_busy',return_value=False):
                with self.assertRaisesRegex(Deferred,'lease_phase_invalid'):agent.dispatch('ax41','/fence/close',{'lease_id':'c'*32,'owner':'ax41'})
                fence.close.assert_not_called()
                agent.coordinator.request.return_value={'owner':'ax41','phase':'fencing'}
                agent.dispatch('ax41','/fence/close',{'lease_id':'c'*32,'owner':'ax41'});fence.close.assert_called_once()
                with self.assertRaisesRegex(Deferred,'lease_phase_invalid'):agent.dispatch('ax41','/fence/open',{'lease_id':'c'*32})
                fence.open.assert_not_called()
                agent.coordinator.request.return_value={'owner':'ax41','phase':'releasing'}
                agent.dispatch('ax41','/fence/open',{'lease_id':'c'*32});fence.open.assert_called_once()



class DirectActivity(unittest.TestCase):
    def test_current_process_metrics_and_fixed_private_destinations(self):
        from host_maintenance.collect import GuestCollector
        collector=GuestCollector('prod');collector.http=unittest.mock.MagicMock()
        body=b'# TYPE process_start_time_seconds gauge\nprocess_start_time_seconds 1\n# TYPE livekit_room_total gauge\nlivekit_room_total 0\n# TYPE livekit_participant_total gauge\nlivekit_participant_total 0\n'
        collector.http.open.return_value.__enter__.return_value.read.return_value=body
        counts,_=collector.metrics({'status':{'podIP':'10.60.0.20'}},'livekit')
        self.assertEqual(counts,{'livekit_rooms':0,'livekit_participants':0})
        request=collector.http.open.call_args.args[0]
        self.assertEqual(request.full_url,'http://10.60.0.20:6789/metrics')
        collector.http.reset_mock()
        with self.assertRaisesRegex(Deferred,'workload_unready'):
            collector.metrics({'status':{'podIP':'169.254.169.254'}},'livekit')
        collector.http.open.assert_not_called()
        collector.http.open.return_value.__enter__.return_value.read.return_value=body.replace(b'livekit_room_total 0',b'livekit_room_total NaN')
        with self.assertRaisesRegex(Deferred,'metric_stale_or_invalid'):
            collector.metrics({'status':{'podIP':'10.60.0.20'}},'livekit')

    def test_healthy_reopening_does_not_wait_for_an_active_lesson_to_expire(self):
        from host_maintenance.model import validate_recovery,validate_snapshot
        sample=Gates().snapshot(995);sample['guests']['prod']['counts']['lesson_windows']=1
        sample['guests']['prod']['counts']['external_connections']=1
        validate_recovery(sample,1000)
        with self.assertRaisesRegex(Deferred,'activity_busy'):validate_snapshot(sample,1000,120)
        sample['guests']['prod']['healthy']=False
        with self.assertRaisesRegex(Deferred,'source_unhealthy'):validate_recovery(sample,1000)

if __name__=='__main__':unittest.main()

class PackageIdentity(unittest.TestCase):
    def test_signed_sha256_and_sha512_uri_identity_and_tampering(self):
        from host_maintenance.packages import archive_identity
        metadata='SHA256: '+'a'*64+'\nSHA512: '+'b'*128+'\n'
        for algorithm,value in [('SHA256','a'*64),('SHA512','b'*128)]:
            self.assertEqual(archive_identity(metadata,"'https://invalid.example/x' package_1_amd64.deb 1 "+algorithm+':'+value),'package_1_amd64.deb')
        for tail in ['SHA256:'+'b'*64,'SHA512:'+'a'*128,'MD5Sum:'+'a'*32]:
            with self.assertRaises(Deferred):archive_identity(metadata,"'https://invalid.example/x' package_1_amd64.deb 1 "+tail)
