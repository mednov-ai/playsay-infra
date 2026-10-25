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
