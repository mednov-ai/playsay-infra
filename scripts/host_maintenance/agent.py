"""Typed control plane. Remote requests never supply executable commands or paths."""
import copy
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import re
from pathlib import Path
import secrets
import threading
import time

from .collect import ingress_snapshot, package_busy, service_runtime, synchronized, turn_snapshot
from .fence import AdmissionFence
from .model import (Deferred, GUEST_FIELDS, HOST_FIELDS, TURN_FIELDS, HOSTS, Journal, atomic_json, assert_owner,
                    reserve, two_zero_observations, validate_recovery, validate_observation, validate_snapshot, within_window)
from .wire import Authenticator, Client, LIMIT


class Agent:
    def __init__(self,config,keys,clock=time.time,fence=None,peer=None):
        self.config,self.keys,self.clock=config,keys,clock
        self.role=config['role'];self.root=Path(config['state_dir']);self.journal=Journal(self.root)
        self.fence=fence or AdmissionFence(self.role,self.root)
        self.peer=peer
        if self.role=='ax41' and self.peer is None:
            self.peer=Client(config['peer_url'],'ax41',keys['peer'],config['peer_address'])
        self.auth=Authenticator(keys['server'],self.journal)
        self.coordinator=None
        if self.role=='selectel':self.coordinator=Client(config['coordinator_url'],'selectel',keys['coordinator'],config['coordinator_address'])
        self.stopping=threading.Event()

    def require_host(self,actor):
        if actor not in HOSTS:raise Deferred('role_forbidden')

    def read(self,name):
        path=self.root/(name+'.json')
        value=json.loads(path.read_text()) if path.exists() else {}
        if not isinstance(value,dict):raise Deferred('journal_invalid')
        return value

    def local_state(self):
        cached=self.read('local')
        cached.update(fenced=self.fence.closed(),worker=self.read('worker'),package_busy=package_busy())
        return cached

    def snapshot(self):
        if self.role!='ax41':raise Deferred('coordinator_only')
        local=self.local_state();remote=self.peer.request('/state')
        state=self.read('coordinator')
        observations=self.read('observations')
        return {'guests':{name:observations.get(name) for name in ('prod','dev')},
                'hosts':{'ax41':local.get('ingress'),'selectel':remote.get('ingress')},
                'turn':remote.get('turn'),'fences':{'ax41':local.get('fenced') is True,'selectel':remote.get('fenced') is True},
                'lease_phase':state.get('phase','idle'),'lease_id':state.get('lease_id'),
                'fenced_at':state.get('fenced_at')}

    def arm(self,actor,lease_id):
        if not within_window(self.clock(),synchronized(),1020):raise Deferred('outside_window')
        with self.journal.locked('coordinator') as state:
            assert_owner(state,actor,lease_id)
            if state['phase']!='reserved':raise Deferred('lease_phase_invalid')
            state['phase']='fencing'
        # Do not hold coordinator lock during peer I/O. No step is granted in this phase.
        self.fence.close(lease_id,actor)
        self.peer.request('/fence/close',{'lease_id':lease_id,'owner':actor})
        with self.journal.locked('coordinator') as state:
            assert_owner(state,actor,lease_id)
            if state['phase']!='fencing':raise Deferred('lease_phase_invalid')
            state.update(phase='fenced',fenced_at=int(self.clock())+1)
            state.pop('zero_baseline',None)
        return {'phase':'fenced'}

    def observe_zero(self,actor,lease_id,budget):
        snapshot=self.snapshot()
        now=self.clock()
        try:validate_snapshot(snapshot,now,budget)
        except Deferred:
            with self.journal.locked('coordinator') as state:
                assert_owner(state,actor,lease_id);state.pop('zero_baseline',None)
            raise
        failure=None
        with self.journal.locked('coordinator') as state:
            assert_owner(state,actor,lease_id)
            if state['phase'] not in ('fenced','verifying'):raise Deferred('lease_phase_invalid')
            if 'zero_baseline' not in state:
                state['zero_baseline']=snapshot
                return {'eligible':False,'reason':'observation_spacing'}
            try:two_zero_observations(state['zero_baseline'],snapshot,now,budget)
            except Deferred as error:
                if error.code in ('source_stale','source_generation_changed'):
                    state['zero_baseline']=snapshot
                failure=error
        if failure:raise failure
        return {'eligible':True,'snapshot':snapshot}

    def release(self,actor,lease_id):
        with self.journal.locked('coordinator') as state:
            assert_owner(state,actor,lease_id)
            if state['phase']=='step_running':raise Deferred('step_still_running')
            # Aborting pre-install is safe. Destructive completion needs an explicit local worker verification.
            if state.get('destructive_started') and not (state.get('phase')=='verified' or state.get('release_verified') is True):
                raise Deferred('runtime_not_verified')
            state['release_verified']=state.get('phase')=='verified' or state.get('release_verified') is True
            state['phase']='releasing'
        state=self.read('coordinator')
        if not state.get('destructive_started'):self.fence.open(lease_id)
        self.peer.request('/fence/open',{'lease_id':lease_id})
        worker=self.read('worker')
        if package_busy() or worker.get('phase') in ('installing','restarting','overrun','failed_unsafe'):
            raise Deferred('local_worker_not_safe')
        self.fence.open(lease_id)
        with self.journal.locked('coordinator') as state:
            assert_owner(state,actor,lease_id)
            state.update(phase='idle',last_released_at=int(self.clock()))
            state.pop('zero_baseline',None)
        return {'phase':'idle'}

    def dispatch(self,actor,path,data):
        now=int(self.clock())
        if path=='/activity':
            if actor not in ('prod','dev') or self.role!='ax41':raise Deferred('role_forbidden')
            allowed={'healthy','read_started_at','observed_at','counts','generation','next_opening_known','next_opening_at','reason'}
            if not isinstance(data,dict) or set(data)-allowed:raise Deferred('source_schema_invalid')
            if type(data.get('healthy')) is not bool:raise Deferred('source_schema_invalid')
            if data['healthy'] is False and set(data)!={'healthy','read_started_at','observed_at','reason'}:raise Deferred('source_schema_invalid')
            if 'reason' in data and data['reason'] not in ('direct_turn_unknown','clock_unknown','reader_failed','metric_missing','metric_stale_or_invalid','database_primary_unknown','lesson_window_unknown','source_clock_or_duration_unknown','source_inventory_invalid','workload_unready','guest_source_unavailable'):
                raise Deferred('source_schema_invalid')
            stamp=data.get('observed_at')
            if type(stamp) is not int or not 0<=now-stamp<=30:raise Deferred('source_stale')
            if data.get('healthy') is True:
                validate_observation(data,GUEST_FIELDS,now,require_zero=False)
                counts=data.get('counts')
                if not isinstance(counts,dict) or set(counts)!=GUEST_FIELDS or any(type(v) is not int or v<0 for v in counts.values()):raise Deferred('source_schema_invalid')
                if data.get('next_opening_known') is not True or (data.get('next_opening_at') is not None and (type(data['next_opening_at']) is not int or data['next_opening_at']<0)):
                    raise Deferred('source_schema_invalid')
                if type(data.get('generation')) is not str or not re.fullmatch('[0-9a-f]{64}',data['generation']):raise Deferred('source_schema_invalid')
            with self.journal.locked('observations') as state:
                previous=state.get(actor,{})
                if stamp<=previous.get('observed_at',0):raise Deferred('source_did_not_advance')
                state[actor]=data
            return {'accepted':True}
        self.require_host(actor)
        if path=='/state':return self.local_state()
        if path in ('/fence/close','/fence/open','/fence/hold'):
            if actor!='ax41' or self.role!='selectel':raise Deferred('role_forbidden')
            assertion=self.coordinator.request('/lease/assert',{'lease_id':data['lease_id']})
            expected={'/fence/close':('fencing',),'/fence/hold':('committing',),'/fence/open':('releasing',)}[path]
            if assertion.get('phase') not in expected:raise Deferred('lease_phase_invalid')
            if path!='/fence/open' and not within_window(now,synchronized(),120):raise Deferred('outside_window')
            if path=='/fence/close' and assertion.get('owner')!=data.get('owner'):raise Deferred('lease_owner_mismatch')
            worker=self.read('worker')
            if path=='/fence/open':
                if package_busy() or worker.get('phase') in ('installing','restarting','overrun','failed_unsafe'):raise Deferred('local_worker_not_safe')
                self.fence.open(data['lease_id'])
            elif path=='/fence/hold':self.fence.hold(data['lease_id'])
            else:
                if data.get('owner') not in HOSTS:raise Deferred('lease_request_invalid')
                self.fence.close(data['lease_id'],data['owner'])
            return {'fenced':self.fence.closed()}
        if self.role!='ax41':raise Deferred('coordinator_only')
        if path=='/readiness':
            snapshot=self.snapshot()
            for guest in ('prod','dev'):
                sample=snapshot['guests'][guest]
                validate_observation(sample,GUEST_FIELDS,now,require_zero=False)
                if sample.get('next_opening_known') is not True:raise Deferred('lesson_opening_unknown')
            for host in HOSTS:validate_observation(snapshot['hosts'][host],HOST_FIELDS,now,require_zero=False)
            validate_observation(snapshot['turn'],TURN_FIELDS,now,require_zero=False)
            for host,value in (('ax41',self.local_state()),('selectel',self.peer.request('/state'))):
                services=value.get('services',{})
                if set(services)!=set(self.config['restart_units'][host]) or any(v is None for v in services.values()):raise Deferred('service_inventory_unknown')
            return {'complete':True,'snapshot':snapshot}
        if path=='/lease/assert':
            if actor!='selectel':raise Deferred('role_forbidden')
            state=self.read('coordinator')
            if state.get('lease_id')!=data.get('lease_id') or state.get('phase','idle')=='idle':raise Deferred('lease_owner_mismatch')
            return {'owner':state['owner'],'phase':state['phase']}
        if path=='/lease/claim':
            if self.config.get('enabled') is not True:raise Deferred('execution_disabled')
            snapshot=self.snapshot()
            validate_snapshot(snapshot,now,900,require_fence=False)
            reserve(self.journal,actor,data['lease_id'],now,synchronized())
            return {'phase':'reserved'}
        if path=='/lease/fence':return self.arm(actor,data['lease_id'])
        if path=='/snapshot':
            return self.observe_zero(actor,data['lease_id'],900)
        if path=='/lease/release':return self.release(actor,data['lease_id'])
        if path=='/lease/heartbeat':
            with self.journal.locked('coordinator') as state:
                assert_owner(state,actor,data['lease_id']);state['heartbeat_at']=now
            return {'alive':True}
        if path=='/lease/verify':
            state=self.read('coordinator');assert_owner(state,actor,data['lease_id'])
            completed=state.get('last_step_completed_at',0)
            snapshot=self.snapshot();validate_recovery(snapshot,now)
            samples=[*snapshot['guests'].values(),*snapshot['hosts'].values(),snapshot['turn']]
            if any(item['read_started_at']<completed for item in samples):raise Deferred('post_step_observation_pending')
            local=self.local_state();remote=self.peer.request('/state')
            for host,value in (('ax41',local),('selectel',remote)):
                if value.get('observed_at',0)<completed:raise Deferred('post_step_observation_pending')
                if value.get('package_busy') is not False:raise Deferred('package_lock_busy')
                services=value.get('services',{})
                if set(services)!=set(self.config['restart_units'][host]):raise Deferred('service_inventory_unknown')
                if any(v is None for v in services.values()):raise Deferred('service_health_unknown')
            with self.journal.locked('coordinator') as state:
                assert_owner(state,actor,data['lease_id'])
                if state['phase'] not in ('fenced','verifying'):raise Deferred('lease_phase_invalid')
                state['phase']='verified'
            return {'verified':True}
        if path=='/lease/preflight':
            state=self.read('coordinator');assert_owner(state,actor,data['lease_id'])
            if state.get('phase')!='step_running' or state.get('step_id')!=data.get('step_id') or state.get('operation')!=data.get('operation'):raise Deferred('step_identity_mismatch')
            if not 0<=now-state.get('step_granted_at',0)<=15:raise Deferred('step_grant_stale')
            budget=900 if state['operation']=='install' else 120
            if not within_window(now,synchronized(),budget+120):raise Deferred('outside_window')
            _,generation=validate_snapshot(self.snapshot(),now,budget)
            if list(generation)!=state.get('proof_generation'):raise Deferred('source_generation_changed')
            return {'ready':True}
        if path=='/lease/step':
            operation=data.get('operation')
            service=data.get('service')
            if operation not in ('install','restart'):raise Deferred('operation_not_allowed')
            if operation=='restart' and service not in self.config['restart_units'][actor]:raise Deferred('service_not_allowed')
            budget=900 if operation=='install' else 120
            if not within_window(now,synchronized(),budget+120):raise Deferred('outside_window')
            proof=self.observe_zero(actor,data['lease_id'],budget)
            if not proof['eligible']:return proof
            with self.journal.locked('coordinator') as state:
                assert_owner(state,actor,data['lease_id'])
                if state['phase'] not in ('fenced','verifying'):raise Deferred('lease_phase_invalid')
                state['phase']='committing'
            self.fence.hold(data['lease_id'])
            self.peer.request('/fence/hold',{'lease_id':data['lease_id']})
            now=int(self.clock())
            if not within_window(now,synchronized(),budget+120):raise Deferred('outside_window')
            stamps,generation=validate_snapshot(self.snapshot(),now,budget)
            previous_stamps,previous_generation=validate_snapshot(proof['snapshot'],now,budget)
            if generation!=previous_generation or any(stamps[k]<previous_stamps[k] for k in stamps):raise Deferred('source_generation_changed')
            with self.journal.locked('coordinator') as state:
                assert_owner(state,actor,data['lease_id'])
                if state['phase']!='committing':raise Deferred('lease_phase_invalid')
                token=secrets.token_hex(16)
                state.update(phase='step_running',operation=operation,service=service,step_id=token,
                             step_granted_at=now,destructive_started=True,proof_generation=list(generation))
                state.pop('zero_baseline',None)
            return {'eligible':True,'step_id':token,'granted_at':now}
        if path=='/lease/complete-step':
            with self.journal.locked('coordinator') as state:
                assert_owner(state,actor,data['lease_id'])
                if state.get('step_id')!=data.get('step_id') or state['phase']!='step_running':raise Deferred('step_identity_mismatch')
                if data.get('success') is not True:
                    state['phase']='failed_unsafe'
                else:
                    state['phase']='verifying'
                    state['last_step_completed_at']=now
                state.pop('zero_baseline',None)
            return {'completed':True}
        raise Deferred('request_invalid')

    def collect_loop(self):
        while not self.stopping.is_set():
            try:
                self.fence.expire_uncommitted(int(self.clock()))
                value={'observed_at':int(self.clock()),'ingress':ingress_snapshot()}
                if self.role=='selectel':value['turn']=turn_snapshot(self.config)
                value['services']={unit:service_runtime(unit,options.get('optional',False)) for unit,options in self.config['services'].items()}
                atomic_json(self.root/'local.json',value)
            except Exception:
                # Old observation times are retained on failure; never refresh a fabricated zero.
                pass
            self.stopping.wait(3)

    def serve(self):
        agent=self
        class Handler(BaseHTTPRequestHandler):
            protocol_version='HTTP/1.1'
            def log_message(self,*args):pass
            def handle_request(self):
                try:
                    length=int(self.headers.get('Content-Length','0'))
                    if not 0<=length<=LIMIT or self.headers.get('Transfer-Encoding'):raise Deferred('request_invalid')
                    self.connection.settimeout(5)
                    body=self.rfile.read(length)
                    actor=agent.auth.verify(self.command,self.path,self.headers,body,int(agent.clock()))
                    data=json.loads(body) if body else {}
                    if not isinstance(data,dict):raise Deferred('request_invalid')
                    result=agent.dispatch(actor,self.path,data);status=200
                except Deferred as error:
                    result={'error':error.code};status=409
                except Exception:
                    result={'error':'control_failure'};status=503
                raw=json.dumps(result,allow_nan=False).encode()
                self.send_response(status);self.send_header('Content-Type','application/json')
                self.send_header('Content-Length',str(len(raw)));self.send_header('Connection','close')
                self.end_headers();self.wfile.write(raw);self.close_connection=True
            do_GET=handle_request
            do_POST=handle_request
        class BoundedServer(ThreadingHTTPServer):
            slots=threading.BoundedSemaphore(16)
            def get_request(self):
                connection,address=super().get_request();connection.settimeout(5)
                return connection,address
            def process_request(self,request,address):
                if not self.slots.acquire(blocking=False):self.shutdown_request(request);return
                try:super().process_request(request,address)
                except Exception:self.slots.release();raise
            def process_request_thread(self,request,address):
                try:super().process_request_thread(request,address)
                finally:self.slots.release()
        server=BoundedServer(('127.0.0.1',9276),Handler)
        server.daemon_threads=True
        thread=threading.Thread(target=self.collect_loop,daemon=True);thread.start()
        try:server.serve_forever()
        finally:self.stopping.set();server.server_close()
