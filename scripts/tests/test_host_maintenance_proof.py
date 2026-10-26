from contextlib import ExitStack
from datetime import datetime,timezone
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock,patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from host_maintenance.model import Deferred
from host_maintenance.worker import Worker

class ProofScheduling(unittest.TestCase):
    def owner(self):
        temp=tempfile.TemporaryDirectory();self.addCleanup(temp.cleanup)
        policy=Path(temp.name)/'policy.json';policy.write_text('{}')
        return Worker({'role':'ax41','enabled':True,'state_dir':temp.name,'package_policy':str(policy),'services':{'nginx':{}}},{'local':'a'*64})
    def clock(self,stack):
        elapsed=[0.0];base=datetime(2026,10,26,0,15,tzinfo=timezone.utc).timestamp()
        stack.enter_context(patch('host_maintenance.worker.time.monotonic',side_effect=lambda:elapsed[0]))
        stack.enter_context(patch('host_maintenance.worker.time.time',side_effect=lambda:base+elapsed[0]))
        stack.enter_context(patch('host_maintenance.worker.time.sleep',side_effect=lambda n:elapsed.__setitem__(0,elapsed[0]+n)))
        stack.enter_context(patch('host_maintenance.worker.synchronized',return_value=True))
        return elapsed,base
    def test_second_proof_is_not_requested_before_independent_spacing_can_advance(self):
        owner=self.owner();calls=[]
        with ExitStack() as stack:
            elapsed,base=self.clock(stack)
            def request(path,**data):
                calls.append(elapsed[0])
                return {'eligible':False,'reason':'observation_spacing'} if len(calls)==1 else {'eligible':True,'step_id':'b'*32,'granted_at':base+elapsed[0]}
            owner.request=request
            self.assertEqual(owner.proof('restart','nginx'),'b'*32)
        self.assertGreaterEqual(calls[1]-calls[0],10)
        self.assertLess(elapsed[0],45)
    def test_busy_or_lost_clock_after_wait_still_denies_without_a_step(self):
        for lost_clock in [False,True]:
            with self.subTest(lost_clock=lost_clock),ExitStack() as stack:
                owner=self.owner();elapsed,base=self.clock(stack);calls=[]
                if lost_clock:stack.enter_context(patch('host_maintenance.worker.synchronized',side_effect=lambda:elapsed[0]==0))
                def request(path,**data):
                    calls.append(elapsed[0])
                    if len(calls)==1:return {'eligible':False,'reason':'observation_spacing'}
                    raise Deferred('activity_busy')
                owner.request=request
                with self.assertRaisesRegex(Deferred,'outside_window' if lost_clock else 'activity_busy'):owner.proof('restart','nginx')
                self.assertEqual(len(calls),1 if lost_clock else 2)
    def test_spacing_timeout_does_not_make_a_request_after_its_bound(self):
        owner=self.owner();calls=[]
        with ExitStack() as stack:
            elapsed,base=self.clock(stack)
            def request(*args,**kwargs):calls.append(elapsed[0]);return {'eligible':False,'reason':'observation_spacing'}
            owner.request=request
            with self.assertRaisesRegex(Deferred,'observation_timeout'):owner.proof('restart','nginx')
        self.assertLessEqual(elapsed[0],45)
        self.assertTrue(all(t<45 for t in calls))
    def test_unusable_unstarted_grant_uses_verified_release_not_a_bare_abort(self):
        owner=self.owner();owner.acknowledge=Mock()
        def request(path,**data):
            if path=='/lease/step':return {'eligible':True,'step_id':'b'*32,'granted_at':base+elapsed[0]-6}
            return {}
        owner.request=request
        def verify():owner.state('idle')
        owner.verify_release=Mock(side_effect=verify)
        runtime={'active':True,'pending':True,'process_started':'same'}
        with ExitStack() as stack:
            elapsed,base=self.clock(stack)
            planner=stack.enter_context(patch('host_maintenance.worker.Planner'));planner.return_value.plan.return_value={'allowed':[],'blocked':[],'pending_count':0}
            stack.enter_context(patch('host_maintenance.worker.service_runtime',return_value=runtime))
            stack.enter_context(patch('host_maintenance.worker.package_read_lock'))
            native=stack.enter_context(patch('host_maintenance.worker.subprocess.run'))
            stack.enter_context(patch('host_maintenance.worker.threading.Thread'))
            with self.assertRaisesRegex(Deferred,'step_grant_stale'):owner.run()
            native.assert_not_called()
        owner.verify_release.assert_called_once()
        self.assertEqual(json.loads((owner.root/'worker.json').read_text())['phase'],'idle')
