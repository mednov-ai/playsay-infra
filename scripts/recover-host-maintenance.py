#!/usr/bin/python3
"""Reviewed root-only forward recovery; never takes over or replays a transaction."""
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import time
sys.path.insert(0,'/usr/local/lib/honey-school-maintenance')
from host_maintenance.collect import package_read_lock, run, service_runtime
from host_maintenance.model import Deferred, Journal, atomic_json, assert_owner, validate_recovery
from host_maintenance.packages import package_database_clean
from host_maintenance.worker import Worker
from host_maintenance.wire import Client

CONFIG=Path('/etc/honey-school-maintenance/config.json')

def read(root,name):
    p=root/(name+'.json');return json.loads(p.read_text()) if p.exists() else {}

def native_idle():
    if run(['/usr/bin/systemctl','list-jobs','--no-legend','--no-pager']).strip():raise Deferred('systemd_jobs_pending')
    props=run(['/usr/bin/systemctl','show','honey-school-maintenance-execute.service','-p','MainPID','-p','ActiveState'])
    values=dict(x.split('=',1) for x in props.splitlines() if '=' in x)
    if values.get('MainPID')!='0' or values.get('ActiveState') not in ('inactive','failed'):raise Deferred('executor_still_running')
    package_database_clean()

def expected_failure(state,worker):
    if (state.get('owner')!='ax41' or state.get('phase')!='failed_unsafe' or
        state.get('operation')!='restart' or state.get('service')!='libvirtd' or
        worker.get('phase')!='failed_unsafe' or worker.get('service')!='libvirtd' or
        worker.get('lease_id')!=state.get('lease_id') or worker.get('step_id')!=state.get('step_id')):
        raise Deferred('recovery_identity_not_supported')
    assert_owner(state,'ax41',worker['lease_id'])

def expected_completed_commit(state,worker):
    # Only the observed Selectel coturn completion followed by an ungranted
    # commit is recoverable. A current/unacknowledged native step never is.
    if (state.get('owner')!='selectel' or state.get('phase')!='committing' or
        state.get('operation')!='restart' or state.get('service')!='coturn' or
        state.get('last_completed_success') is not True or not state.get('step_id') or
        state.get('last_completed_step_id')!=state.get('step_id') or
        worker.get('phase')!='recovery_required' or worker.get('reason')!='runtime_not_verified' or
        worker.get('service')!='coturn' or worker.get('step_id')!=state.get('step_id') or
        worker.get('lease_id')!=state.get('lease_id')):
        raise Deferred('recovery_identity_not_supported')
    assert_owner(state,'selectel',worker['lease_id'])

def main(mode):
    if os.geteuid()!=0:raise Deferred('privilege_required')
    config=json.loads(CONFIG.read_text());role=config['role'];root=Path(config['state_dir'])
    if role not in ('ax41','selectel'):raise Deferred('role_forbidden')
    with (root/'executor.lock').open('a') as lock:
        try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:raise Deferred('local_owner_busy')
        with package_read_lock():
            native_idle();worker=read(root,'worker');coordinator=read(root,'coordinator')
            selectel_recovery=role=='selectel' and worker.get('phase')=='recovery_required'
            if role=='selectel' and worker.get('phase','idle') not in ('idle','deferred') and not selectel_recovery:raise Deferred('peer_worker_not_safe')
            keys=json.loads((CONFIG.parent/'keys.json').read_text())
            client=Client('http://127.0.0.1:9276',role,keys['local'])
            local=client.request('/state')
            completed_commit=False
            if role=='ax41':
                if coordinator.get('owner')=='selectel':
                    peer=Client(config['peer_url'],'ax41',keys['peer'],config['peer_address'])
                    peer_worker=peer.request('/state')['worker']
                    expected_completed_commit(coordinator,peer_worker);completed_commit=True
                    if worker.get('phase','idle') not in ('idle','deferred'):raise Deferred('peer_worker_not_safe')
                else:expected_failure(coordinator,worker)
            if selectel_recovery:
                if worker.get('reason')!='runtime_not_verified' or worker.get('service')!='coturn' or not worker.get('step_id'):raise Deferred('recovery_identity_not_supported')
                assertion=Client(config['coordinator_url'],'selectel',keys['coordinator'],config['coordinator_address']).request('/lease/assert',{'lease_id':worker['lease_id']})
                if assertion.get('owner')!='selectel' or assertion.get('phase') not in ('committing','verifying'):raise Deferred('recovery_identity_not_supported')
                coturn=service_runtime('coturn')
                if not coturn or not coturn.get('active') or coturn.get('restartable_pending',coturn['pending']):raise Deferred('service_health_unknown')
            if mode=='--finish-selectel' and (not selectel_recovery or config.get('enabled') or assertion.get('phase')!='verifying'):raise Deferred('recovery_identity_not_supported')
            if local.get('package_busy') is not False:raise Deferred('package_lock_busy')
            if set(local.get('services',{}))!=set(config['restart_units'][role]) or any(v is None for v in local['services'].values()):raise Deferred('service_health_unknown')
            if role=='ax41':
                validate_recovery(client.request('/readiness')['snapshot'],int(time.time()))
                run(['/usr/local/sbin/playsay-validate-livekit-firewall'],timeout=15)
            if mode=='--finish-selectel':
                owner=Worker(config,keys);owner.lease=worker['lease_id'];owner.claimed=True
                owner.state('verifying',recovery_reason='completed_step_ungranted_commit')
                owner.verify_release()
                print(json.dumps({'role':role,'same_lease_recovered':True,'runtime_debt_preserved':True}));return
            if mode=='--check':print(json.dumps({'role':role,'recovery_preflight':True}));return
            backup=root/('recovery-'+str(time.time_ns()));backup.mkdir(mode=0o700)
            for name in ('worker','coordinator','fence','debt'):atomic_json(backup/(name+'.json'),read(root,name))
            atomic_json(backup/'config.json',config)
            # Quarantine only the new executing scheduler, preserving suppression,
            # aggregate readers, observers, ordinary crash recovery and all debt.
            run(['/usr/bin/systemctl','disable','--now','honey-school-maintenance-execute.timer'])
            config['enabled']=False;atomic_json(CONFIG,config)
            run(['/usr/bin/systemctl','restart','honey-school-maintenance-agent.service'])
            if role=='selectel':print(json.dumps({'role':role,'scheduler_quarantined':True}));return
            # Same lease/step, no takeover. No native operation is repeated and no
            # restart debt is cleared. Verify fresh complete serving health before
            # the existing authenticated release protocol opens either barrier.
            with Journal(root).locked('coordinator') as state:
                if completed_commit:expected_completed_commit(state,peer.request('/state')['worker'])
                else:expected_failure(state,read(root,'worker'))
                state.update(phase='verifying',recovery_reason='completed_step_ungranted_commit' if completed_commit else 'healthy_restart_with_descendant_debt',last_step_completed_at=int(time.time()))
            if completed_commit:
                print(json.dumps({'role':role,'scheduler_quarantined':True,'same_lease_prepared':True,'runtime_debt_preserved':True}));return
            owner=Worker(config,keys);owner.lease=worker['lease_id'];owner.claimed=True
            owner.state('verifying',recovery_reason='healthy_restart_with_descendant_debt')
            owner.verify_release()
            print(json.dumps({'role':role,'scheduler_quarantined':True,'same_lease_recovered':True,'runtime_debt_preserved':True}))

if __name__=='__main__':
    try:
        if len(sys.argv)!=2 or sys.argv[1] not in ('--check','--recover','--finish-selectel'):raise Deferred('arguments_not_allowed')
        main(sys.argv[1])
    except Deferred as error:raise SystemExit('deferred='+error.code)
