"""Local privileged nightly owner; no network request can name a command to execute."""
import fcntl
import json
import os
from pathlib import Path
import secrets
import subprocess
import threading
import time

from .collect import package_busy, service_runtime, synchronized
from .model import Deferred, Journal, atomic_json, within_window
from .packages import Planner, audit_archive, apt_hook_fingerprint, digest, package_database_clean
from .wire import Client

UNSAFE_PHASES=('installing','restarting','overrun','failed_unsafe')


class Worker:
    def __init__(self,config,keys):
        self.config=config;self.role=config['role'];self.root=Path(config['state_dir'])
        self.local=Client('http://127.0.0.1:9276',self.role,keys['local'])
        self.coordinator=self.local if self.role=='ax41' else Client(config['coordinator_url'],self.role,keys['coordinator'],config['coordinator_address'])
        self.lease=None;self.claimed=False;self.stopping=threading.Event();self.failure=None

    def state(self,phase,**fields):
        path=self.root/'worker.json'
        previous=json.loads(path.read_text()) if path.exists() else {}
        atomic_json(path,{**previous,'phase':phase,'observed_at':int(time.time()),'lease_id':self.lease,**fields})

    def record_deferral(self,reason):
        if self.claimed:return
        with (self.root/'executor.lock').open('a') as lock:
            try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
            except BlockingIOError:return
            path=self.root/'worker.json';previous=json.loads(path.read_text()) if path.exists() else {}
            if previous.get('phase','idle') not in ('idle','deferred'):return
            atomic_json(path,{**previous,'phase':'deferred','reason':reason,'observed_at':int(time.time()),'lease_id':None})

    def heartbeat(self):
        while not self.stopping.wait(5):
            try:self.coordinator.request('/lease/heartbeat',{'lease_id':self.lease})
            except Deferred:self.failure='coordinator_unavailable'

    def request(self,path,**data):
        return self.coordinator.request(path,{'lease_id':self.lease,**data})

    def proof(self,operation,service=None):
        deadline=time.monotonic()+45
        while True:
            if self.failure:raise Deferred(self.failure)
            budget=1020 if operation=='install' else 240
            if not within_window(time.time(),synchronized(),budget):raise Deferred('outside_window')
            try:
                result=self.request('/lease/step',operation=operation,service=service)
                if result.get('eligible') is True:
                    # The step token cannot be queued for a later timer or resumed after a process crash.
                    if not 0<=time.time()-result['granted_at']<=5:
                        self.request('/lease/complete-step',step_id=result['step_id'],success=True)
                        raise Deferred('step_grant_stale')
                    return result['step_id']
            except Deferred as error:
                if error.code not in ('observation_spacing','observations_precede_fence','source_generation_changed'):raise
            if time.monotonic()>=deadline:raise Deferred('observation_timeout')
            time.sleep(3)

    def install(self,plan,policy):
        if not plan['allowed']:return
        if package_busy():raise Deferred('package_lock_busy')
        if apt_hook_fingerprint()!=policy['apt_hook_fingerprint']:raise Deferred('apt_hook_inventory_changed')
        for item in plan['allowed']:
            if digest(item['archive'])!=item['sha256']:raise Deferred('package_integrity_failed')
            audit_archive(item['archive'],policy)
        cache=self.root/'apt-archives';cache.mkdir(mode=0o700,exist_ok=True)
        (cache/'partial').mkdir(mode=0o700,exist_ok=True)
        for item in plan['allowed']:
            destination=cache/item['archive_name']
            if destination.exists():
                if destination.is_symlink() or digest(destination)!=item['sha256']:raise Deferred('package_integrity_failed')
            else:os.link(item['archive'],destination)
        token=self.proof('install')
        self.state('installing',step_id=token)
        # Native APT holds its real frontend/dpkg locks. Never disable locking, kill a
        # transaction at 05:00, broaden to upgrade-all, fetch unaudited dependencies,
        # or allow package hooks to choose a protected service restart.
        environment={**os.environ,'DEBIAN_FRONTEND':'noninteractive','NEEDRESTART_MODE':'l','NEEDRESTART_SUSPEND':'1'}
        args=['/usr/bin/apt-get','-y','--no-download','--no-remove','--no-install-recommends',
              '--only-upgrade','-o','DPkg::Pre-Invoke::=/usr/local/sbin/honey-school-maintenance-package-preflight','-o','DPkg::Lock::Timeout=0','-o','Dpkg::Options::=--force-confold',
              '-o','Dir::Cache::archives='+str(cache),
              'install',*[item['name']+'='+item['version'] for item in plan['allowed']]]
        with (self.root/'transaction.log').open('ab') as log:
            process=subprocess.Popen(args,env=environment,stdout=log,stderr=log)
            while process.poll() is None:
                if not within_window(time.time(),synchronized()):self.state('overrun',step_id=token)
                time.sleep(2)
        good=process.returncode==0
        permit=self.root/'transaction-permit.json'
        entered=permit.exists() and json.loads(permit.read_text()).get('step_id')==token
        if not good and not entered:
            package_database_clean()
            unchanged=True
            for item in plan['allowed']:
                check=subprocess.run(['/usr/bin/dpkg-query','-W','-f=${Version}',item['name']],capture_output=True,text=True)
                if check.returncode or check.stdout!=item['old_version']:unchanged=False
            if unchanged:
                self.state('verifying',step_id=token,reason='native_preinstall_deferred')
                self.request('/lease/complete-step',step_id=token,success=True)
                raise Deferred('native_preinstall_deferred')
        if good:
            # Verify exactly the audited installed versions, never infer success from a log line.
            for item in plan['allowed']:
                result=subprocess.run(['/usr/bin/dpkg-query','-W','-f=${Version}',item['name']],capture_output=True,text=True)
                if result.returncode or result.stdout!=item['version']:good=False
        self.state('verifying' if good else 'failed_unsafe',step_id=token)
        self.request('/lease/complete-step',step_id=token,success=good)
        if not good:raise Deferred('package_transaction_failed')

    def restart(self,unit):
        options=self.config['services'][unit]
        before=service_runtime(unit,options.get('optional',False))
        if before is None:raise Deferred('service_health_unknown')
        debt_path=self.root/'debt.json'
        old=json.loads(debt_path.read_text()).get('services',{}).get(unit,{}) if debt_path.exists() else {}
        aged=old.get('pending') and old.get('process_started')==before.get('process_started')
        if not before.get('active') or (not before['pending'] and not aged):return
        token=self.proof('restart',unit)
        self.state('preparing_restart',step_id=token,service=unit)
        # Service names come only from the root-owned deployment inventory.
        # --no-block avoids systemctl timeout/cancellation of an already started job.
        try:self.request('/lease/preflight',step_id=token,operation='restart')
        except Deferred:
            self.state('verifying',step_id=token)
            self.request('/lease/complete-step',step_id=token,success=True)
            raise
        self.state('restarting',step_id=token,service=unit)
        job=subprocess.run(['/usr/bin/systemctl','--no-block','restart',unit],capture_output=True)
        good=False
        deadline=time.monotonic()+120
        while job.returncode==0 and time.monotonic()<deadline:
            after=service_runtime(unit,options.get('optional',False))
            if after and after.get('active') and not after['pending'] and after.get('process_started')!=before.get('process_started'):
                if self.role=='ax41' and unit in ('libvirtd','systemd-networkd','nginx'):
                    from .collect import run
                    try:run(['/usr/local/sbin/playsay-validate-livekit-firewall'],timeout=15)
                    except Deferred:time.sleep(2);continue
                good=True;break
            time.sleep(2)
        self.state('verifying' if good else 'failed_unsafe',step_id=token,service=unit)
        self.request('/lease/complete-step',step_id=token,success=good)
        if not good:raise Deferred('service_restart_not_verified')

    def verify_release(self):
        deadline=time.monotonic()+60
        while True:
            try:
                self.request('/lease/verify');break
            except Deferred as error:
                if error.code not in ('source_stale','source_unhealthy','activity_busy','observations_precede_fence','post_step_observation_pending') or time.monotonic()>=deadline:raise
                time.sleep(3)
        self.state('verified')
        self.request('/lease/release')
        self.state('idle',last_completed_at=int(time.time()))

    def run(self):
        with (self.root/'executor.lock').open('a') as lock:
            try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
            except BlockingIOError:raise Deferred('local_owner_busy')
            previous=json.loads((self.root/'worker.json').read_text()) if (self.root/'worker.json').exists() else {}
            if previous.get('phase') not in (None,'idle','deferred'):
                # No automatic takeover of an abandoned or partitioned transaction.
                raise Deferred('prior_transaction_requires_recovery')
            if not self.config.get('enabled'):raise Deferred('execution_disabled')
            if not within_window(time.time(),synchronized(),1020):raise Deferred('outside_window')
            policy=json.loads(Path(self.config['package_policy']).read_text())
            plan=Planner(self.root,policy).plan()
            atomic_json(self.root/'package-plan.json',plan)
            observations={u:service_runtime(u,o.get('optional',False)) for u,o in self.config['services'].items()}
            if any(v is None for v in observations.values()):raise Deferred('service_health_unknown')
            debt_path=self.root/'debt.json'
            debt=json.loads(debt_path.read_text()).get('services',{}) if debt_path.exists() else {}
            if not plan['allowed'] and not any(v['pending'] or (v.get('active') and debt.get(u,{}).get('pending') and debt[u].get('process_started')==v.get('process_started')) for u,v in observations.items()):
                self.state('idle',last_completed_at=int(time.time()),reason='no_eligible_debt');return
            self.lease=secrets.token_hex(16)
            self.request('/lease/claim')
            self.claimed=True
            self.state('reserved')
            threading.Thread(target=self.heartbeat,daemon=True).start()
            destructive=False
            try:
                self.request('/lease/fence')
                self.state('fenced')
                try:
                    self.install(plan,policy)
                    for unit in self.config['services']:self.restart(unit)
                finally:
                    local=json.loads((self.root/'worker.json').read_text())
                    destructive=local.get('phase') not in ('reserved','fenced')
                self.verify_release()
            except Deferred as error:
                if not destructive:
                    # No install/restart was started: promptly reopen on new activity,
                    # source failure or a partial fence acknowledgement.
                    try:self.request('/lease/release');self.state('deferred',reason=error.code)
                    except Deferred:self.state('recovery_required',reason='release_unavailable')
                elif json.loads((self.root/'worker.json').read_text()).get('phase') not in UNSAFE_PHASES:
                    try:self.verify_release()
                    except Deferred:self.state('recovery_required',reason='runtime_not_verified')
                raise
            finally:self.stopping.set()
