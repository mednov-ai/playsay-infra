import importlib.util
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
spec=importlib.util.spec_from_file_location('maintenance_recovery',Path(__file__).resolve().parents[1]/'recover-host-maintenance.py')
r=importlib.util.module_from_spec(spec);spec.loader.exec_module(r)

class Recovery(unittest.TestCase):
    def states(self):
        return ({'owner':'ax41','phase':'failed_unsafe','operation':'restart','service':'libvirtd','lease_id':'a'*32,'step_id':'b'*32},
                {'phase':'failed_unsafe','service':'libvirtd','lease_id':'a'*32,'step_id':'b'*32})
    def test_exact_failed_restart_identity_only(self):
        state,worker=self.states();r.expected_failure(state,worker)
        for key,value in [('owner','selectel'),('operation','install'),('service','nginx'),('phase','step_running'),('lease_id','c'*32),('step_id','c'*32)]:
            with self.subTest(key=key):
                changed={**state,key:value}
                with self.assertRaises(r.Deferred):r.expected_failure(changed,worker)
    def test_only_completed_selectel_coturn_commit_is_recoverable(self):
        state={'owner':'selectel','phase':'committing','operation':'restart','service':'coturn','lease_id':'a'*32,'step_id':'b'*32,'last_completed_step_id':'b'*32,'last_completed_success':True}
        worker={'phase':'recovery_required','reason':'runtime_not_verified','service':'coturn','lease_id':'a'*32,'step_id':'b'*32}
        r.expected_completed_commit(state,worker)
        for key,value in [('owner','ax41'),('phase','step_running'),('operation','install'),('service','nginx'),('last_completed_success',False),('last_completed_step_id','c'*32),('step_id','c'*32),('lease_id','c'*32)]:
            with self.subTest(key=key),self.assertRaises(r.Deferred):r.expected_completed_commit({**state,key:value},worker)
        for key,value in [('phase','restarting'),('reason','unknown'),('service','nginx'),('step_id','c'*32),('lease_id','c'*32)]:
            with self.subTest(key=key),self.assertRaises(r.Deferred):r.expected_completed_commit(state,{**worker,key:value})

    def test_never_cancel_or_steal_native_work(self):
        with patch.object(r,'run',return_value='123 libvirtd restart running'),patch.object(r,'package_database_clean') as db:
            with self.assertRaisesRegex(r.Deferred,'systemd_jobs_pending'):r.native_idle()
            db.assert_not_called()
        with patch.object(r,'run',side_effect=['','MainPID=10\nActiveState=active']),patch.object(r,'package_database_clean') as db:
            with self.assertRaisesRegex(r.Deferred,'executor_still_running'):r.native_idle()
            db.assert_not_called()
    def test_clean_native_idle_checked_without_mutation(self):
        with patch.object(r,'run',side_effect=['','MainPID=0\nActiveState=inactive']) as calls,patch.object(r,'package_database_clean') as db:
            r.native_idle();db.assert_called_once()
            self.assertTrue(all(c.args[0][1] in ('list-jobs','show') for c in calls.call_args_list))

class DescendantDebt(unittest.TestCase):
    def test_managed_guest_debt_is_retained_without_restarting_its_daemon_again(self):
        from host_maintenance.worker import restart_needed
        from host_maintenance.model import service_debt
        old={'pending':True,'first_pending_at':1,'process_started':'old'}
        now={'active':True,'pending':True,'restartable_pending':False,'managed_descendant_pending':True,'process_started':'new'}
        debt=service_debt({'libvirtd':old},{'libvirtd':now},100)['libvirtd']
        self.assertTrue(debt['pending']);self.assertEqual(debt['first_pending_at'],1)
        self.assertFalse(restart_needed(now,debt))
        self.assertTrue(restart_needed({**now,'restartable_pending':True},debt))
    def test_reload_cannot_clear_regular_actionable_debt(self):
        from host_maintenance.worker import restart_needed
        self.assertTrue(restart_needed({'active':True,'pending':False,'restartable_pending':False,'process_started':'same'},{'pending':True,'process_started':'same'}))
    def test_healthy_new_daemon_with_retained_vm_debt_completes_step(self):
        import tempfile
        from host_maintenance.worker import Worker
        from unittest.mock import Mock
        with tempfile.TemporaryDirectory() as directory:
            owner=Worker({'role':'ax41','state_dir':directory,'services':{'libvirtd':{}}},{'local':'a'*64})
            before={'active':True,'pending':True,'restartable_pending':True,'process_started':'old'}
            after={'active':True,'pending':True,'restartable_pending':False,'managed_descendant_pending':True,'process_started':'new'}
            owner.proof=Mock(return_value='step');owner.request=Mock();owner.acknowledge=Mock();owner.state=Mock()
            with patch('host_maintenance.worker.service_runtime',side_effect=[before,after]),patch('host_maintenance.worker.subprocess.run',return_value=Mock(returncode=0)),patch('host_maintenance.collect.run',return_value=''):
                owner.restart_locked('libvirtd')
            owner.acknowledge.assert_called_once_with('/lease/complete-step',step_id='step',success=True)
            owner.state.assert_called_with('verifying',step_id='step',service='libvirtd')
