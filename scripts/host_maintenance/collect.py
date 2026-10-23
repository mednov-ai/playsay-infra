"""Bounded root-local readers. No application writes, identifiers or credentials emitted."""
import hashlib
import ipaddress
import json
from pathlib import Path
import re
import subprocess
import time
import urllib.request

from .model import Deferred, GUEST_FIELDS
from .wire import NoRedirect

METRICS = {'livekit_rooms': 'livekit_room_total', 'livekit_participants': 'livekit_participant_total',
           'collaboration_connections': 'playsay_collaboration_active_connections',
           'game_connections': 'playsay_collaboration_game_active_connections',
           'external_connections': 'playsay_collaboration_external_activity_active_connections',
           'snapshot_queue': 'playsay_collaboration_snapshot_queue_size'}
SQL = """BEGIN READ ONLY; SET LOCAL statement_timeout='3s';
SELECT count(*) FILTER (WHERE scheduled_start IS NOT NULL AND scheduled_end IS NOT NULL
  AND access_extension_seconds IS NOT NULL AND access_extension_seconds >= 0
  AND scheduled_start <= now()+interval '10 minutes'
  AND scheduled_end+make_interval(secs=>access_extension_seconds)+interval '10 minutes'>now()),
 count(*) FILTER (WHERE status IS NULL OR scheduled_start IS NULL OR scheduled_end IS NULL
  OR access_extension_seconds IS NULL OR access_extension_seconds < 0 OR scheduled_end<scheduled_start),
 floor(extract(epoch FROM min(scheduled_start-interval '10 minutes')
  FILTER (WHERE scheduled_start-interval '10 minutes'>now()))),
 floor(extract(epoch FROM now()))
FROM lesson WHERE status IS NULL OR status NOT IN ('COMPLETED','CANCELLED'); COMMIT;"""


def run(argv, timeout=8):
    try:
        result = subprocess.run(argv, text=True, capture_output=True, timeout=timeout, check=False)
        if result.returncode or len(result.stdout) > 8*1024*1024:
            raise Deferred('reader_failed')
        return result.stdout
    except (OSError, subprocess.TimeoutExpired) as error:
        raise Deferred('reader_failed') from error


def synchronized():
    try:
        return run(['/usr/bin/timedatectl', 'show', '-p', 'NTPSynchronized', '--value']).strip() == 'yes'
    except Deferred:
        return False



class GuestCollector:
    def __init__(self, environment):
        if environment not in ('prod','dev'):
            raise ValueError('unknown_guest')
        self.environment = environment
        self.kube = ['/usr/local/bin/k3s','kubectl','--kubeconfig=/etc/rancher/k3s/k3s.yaml']
        self.http = urllib.request.build_opener(urllib.request.ProxyHandler({}),NoRedirect())

    def pods(self, namespace, label):
        return json.loads(run(self.kube+['-n',namespace,'get','pods','-l',label,'-o','json']))['items']

    def metrics(self,pod,kind):
        address=ipaddress.ip_address(pod['status']['podIP'])
        expected=ipaddress.ip_address({'prod':'10.60.0.20','dev':'10.60.0.30'}[self.environment])
        network=ipaddress.ip_network({'prod':'10.44.0.0/16','dev':'10.42.0.0/16'}[self.environment])
        if (kind=='livekit' and address!=expected) or (kind=='collaboration' and address not in network):
            raise Deferred('workload_unready')
        port=6789 if kind=='livekit' else 8081
        request=urllib.request.Request('http://'+str(address)+':'+str(port)+'/metrics',headers={'Accept':'text/plain;version=0.0.4'})
        with self.http.open(request,timeout=3) as response:body=response.read(2*1024*1024+1)
        if len(body)>2*1024*1024:raise Deferred('metric_missing')
        text=body.decode('utf-8')
        def values(name):
            if not re.search(r'^# TYPE '+re.escape(name)+r' gauge$',text,re.M):raise Deferred('metric_missing')
            rows=re.findall(r'^'+re.escape(name)+r'(?:\{[^\n]*\})?\s+([^\s]+)\s*$',text,re.M)
            if not rows:raise Deferred('metric_missing')
            return [float(value) for value in rows]
        start_name='process_start_time_seconds' if kind=='livekit' else 'playsay_collaboration_process_start_time_seconds'
        identity=values(start_name)
        if len(identity)!=1 or not 0<identity[0]<=time.time()+1:raise Deferred('metric_stale_or_invalid')
        wanted={key:name for key,name in METRICS.items() if (key.startswith('livekit_'))==(kind=='livekit')}
        counts={}
        for key,name in wanted.items():
            samples=values(name)
            if any(not value.is_integer() or value<0 for value in samples):raise Deferred('metric_stale_or_invalid')
            counts[key]=sum(int(value) for value in samples)
        return counts,str(identity[0])

    def collect(self):
        started=int(time.time())
        sample={'healthy':False,'read_started_at':started,'observed_at':started}
        try:
            if not synchronized():raise Deferred('clock_unknown')
            counts=dict.fromkeys(METRICS,0)
            primary=self.pods('playsay-data','role=primary')
            if len(primary)!=1:raise Deferred('database_primary_unknown')
            pod=primary[0]['metadata']['name']
            result=run(self.kube+['-n','playsay-data','exec',pod,'-c','postgres','--',
                                 'psql','-X','-U','postgres','-d','playsay','-Atq','-v','ON_ERROR_STOP=1','-c',SQL])
            rows=[x.split('|') for x in result.splitlines() if x.count('|')==3]
            if len(rows)!=1:raise Deferred('lesson_window_unknown')
            opened,unknown,future,database_now=rows[0]
            counts.update(lesson_windows=int(opened),unknown_deadlines=int(unknown))
            if abs(int(database_now)-int(time.time()))>5:raise Deferred('source_clock_or_duration_unknown')
            counts.update(direct_turn_snapshot(self.environment))
            generation=[primary[0]['metadata']['uid']]+[str(c.get('containerID',''))+':'+str(c.get('restartCount','')) for c in primary[0]['status'].get('containerStatuses',[])]+[process_generation(int(unit_properties('coturn')['MainPID']))]
            for namespace,label,kind in [('playsay-'+self.environment,'app.kubernetes.io/name=api-gateway',None),
                                         ('playsay-'+self.environment,'app.kubernetes.io/name=collaboration-service','collaboration'),
                                         ('livekit','app.kubernetes.io/name=livekit','livekit')]:
                pods=self.pods(namespace,label)
                if not 1<=len(pods)<=8 or any(p['status'].get('phase')!='Running' or not p['status'].get('containerStatuses') or not all(c.get('ready') and c.get('containerID') for c in p['status']['containerStatuses']) for p in pods):raise Deferred('workload_unready')
                for pod in pods:
                    generation.append(pod['metadata']['uid'])
                    generation += [str(c['containerID'])+':'+str(c.get('restartCount','')) for c in pod['status']['containerStatuses']]
                    if kind:
                        observed,process_start=self.metrics(pod,kind)
                        for key,value in observed.items():counts[key]+=value
                        generation.append(process_start)
            if set(counts)!=GUEST_FIELDS:raise Deferred('source_inventory_invalid')
            if int(time.time())-started>25:raise Deferred('source_clock_or_duration_unknown')
            sample.update(healthy=True,counts=counts,next_opening_known=True,
                          next_opening_at=int(future) if future else None,
                          generation=hashlib.sha256('\n'.join(sorted(generation)).encode()).hexdigest())
        except Deferred as error:sample['reason']=error.code
        except (OSError,ValueError,KeyError,TypeError,StopIteration):sample['reason']='guest_source_unavailable'
        sample['observed_at']=int(time.time())
        return sample


def unit_properties(unit):
    if not re.fullmatch('[a-zA-Z0-9_.@-]+',unit):
        raise Deferred('service_inventory_invalid')
    text=run(['/usr/bin/systemctl','show',unit,'-p','MainPID','-p','ActiveState',
              '-p','LoadState','-p','ControlGroup'])
    return dict(line.split('=',1) for line in text.splitlines() if '=' in line)


def mapped_runtime_pending(pid):
    pending=False
    for line in Path('/proc',str(pid),'maps').read_text().splitlines():
        values=line.split(None,5)
        if len(values)<6 or 'x' not in values[1] or not values[5].startswith(('/usr/','/lib/','/lib64/','/opt/')):
            continue
        if values[5].endswith(' (deleted)'):
            pending=True
            continue
        info=Path(values[5]).stat()
        major,minor=(int(x,16) for x in values[3].split(':'))
        import os
        if (os.major(info.st_dev),os.minor(info.st_dev),info.st_ino)!=(major,minor,int(values[4])):
            pending=True
    return pending


def process_generation(pid):
    fields=Path('/proc',str(pid),'stat').read_text().rpartition(')')[2].split()
    return hashlib.sha256((Path('/proc/sys/kernel/random/boot_id').read_text().strip()+':'+str(pid)+':'+fields[19]).encode()).hexdigest()


def service_runtime(unit, optional=False):
    try:
        props=unit_properties(unit)
        if optional and (props['LoadState']=='not-found' or (props['ActiveState']=='inactive' and props.get('MainPID')=='0')):
            return {'pending':False,'active':False}
        if props['LoadState']!='loaded' or props['ActiveState']!='active':
            raise Deferred('service_unhealthy')
        pid=int(props['MainPID'])
        group=Path('/sys/fs/cgroup')/props['ControlGroup'].lstrip('/')
        pids={int(x) for path in group.rglob('cgroup.procs') for x in path.read_text().split()}
        if pid<=1 or pid not in pids:
            raise Deferred('service_process_unknown')
        inspected=[mapped_runtime_pending(item) for item in sorted(pids)]
        pending=any(inspected)
        return {'pending':pending,'active':True,'process_started':process_generation(pid)}
    except (Deferred,OSError,ValueError,KeyError):
        return None


def turn_snapshot(config):
    started=int(time.time())
    sample={'healthy':False,'read_started_at':started,'observed_at':started}
    try:
        if not synchronized():
            raise Deferred('clock_unknown')
        counts=dict.fromkeys(('prod_relay_sockets','dev_relay_sockets','control_connections','control_queued_bytes'),0)
        generations=[]
        # Inspect both TCP (including listening relay sockets) and UDP, not just allocations over UDP.
        sockets=run(['/usr/bin/ss','-H','-a','-t','-u','-n','-p']).splitlines()
        turn_pids={int(unit_properties(config['turn'][s]['unit'])['MainPID']) for s in ('prod','dev')}
        from .fence import CONTROL_PORTS
        for row in sockets:
            fields=row.split()
            if len(fields)<6:raise Deferred('turn_socket_invalid')
            try:port=int(fields[4].rsplit(':',1)[1])
            except ValueError:continue
            if port in CONTROL_PORTS and fields[1]!='TIME-WAIT':
                owners={int(p) for p in re.findall(r'pid=(\d+)',row)}
                if not owners or not owners<=turn_pids:raise Deferred('turn_control_owner_unknown')
            if port in CONTROL_PORTS:
                counts['control_queued_bytes']+=int(fields[2])+(int(fields[3]) if fields[1]!='LISTEN' else 0)
                if fields[0]=='tcp' and fields[1] not in ('LISTEN','TIME-WAIT','CLOSE'):counts['control_connections']+=1
        for surface in ('prod','dev'):
            item=config['turn'][surface]
            properties=unit_properties(item['unit'])
            if properties['ActiveState']!='active' or int(properties['MainPID'])<=1:
                raise Deferred('turn_service_unhealthy')
            generations.append(process_generation(int(properties['MainPID'])))
            # Check only named non-secret keys. Unknown/changed ranges deny, never broaden discovery.
            text=Path(item['config']).read_text()
            for key,wanted in [('min-port',item['min_port']),('max-port',item['max_port']),
                               ('listening-port',item['port']),('tls-listening-port',item['tls_port'])]:
                values=re.findall(r'^\s*'+key+r'\s*=\s*(\d+)\s*$',text,re.M)
                if values!=[str(wanted)]:
                    raise Deferred('turn_inventory_changed')
            for directive in ('aux-server','alt-listening-port','alt-tls-listening-port'):
                if re.search(r'^\s*'+directive+r'\s*=',text,re.M):raise Deferred('turn_inventory_changed')
            for row in sockets:
                fields=row.split()
                if len(fields)<6:
                    raise Deferred('turn_socket_invalid')
                try:
                    port=int(fields[4].rsplit(':',1)[1])
                except ValueError:
                    continue
                if item['min_port']<=port<=item['max_port']:
                    counts[surface+'_relay_sockets']+=1
        sample.update(healthy=True,counts=counts,generation=hashlib.sha256(':'.join(generations).encode()).hexdigest())
    except (Deferred,OSError,ValueError,KeyError,TypeError):
        sample['reason']='turn_source_unavailable'
    sample['observed_at']=int(time.time())
    return sample


def direct_turn_snapshot(environment):
    """AX41 guests run native TURN as well as the independent Selectel relays."""
    port,low,high=(3478,49152,49999) if environment=='prod' else (3479,50600,50999)
    props=unit_properties('coturn')
    if props.get('ActiveState')!='active' or int(props.get('MainPID','0'))<=1:raise Deferred('direct_turn_unknown')
    text=Path('/etc/turnserver.conf').read_text()
    for key,wanted in (('listening-port',port),('min-port',low),('max-port',high)):
        if re.findall(r'^\s*'+key+r'\s*=\s*(\d+)\s*$',text,re.M)!=[str(wanted)]:raise Deferred('direct_turn_unknown')
    # Only the reviewed plain control port is public in this contour.
    if re.search(r'^\s*(?:aux-server|alt-listening-port|alt-tls-listening-port|tls-listening-port)\s*=',text,re.M):raise Deferred('direct_turn_unknown')
    counts={'direct_turn_relay_sockets':0,'direct_turn_control_connections':0,'direct_turn_control_queued_bytes':0}
    for row in run(['/usr/bin/ss','-H','-a','-t','-u','-n']).splitlines():
        fields=row.split()
        if len(fields)<6:raise Deferred('direct_turn_unknown')
        try:local=int(fields[4].rsplit(':',1)[1])
        except ValueError:continue
        if low<=local<=high:counts['direct_turn_relay_sockets']+=1
        if local in (port,port+1,5349,5350):
            counts['direct_turn_control_queued_bytes']+=int(fields[2])+(int(fields[3]) if fields[1]!='LISTEN' else 0)
            if fields[0]=='tcp' and fields[1] not in ('LISTEN','TIME-WAIT','CLOSE'):counts['direct_turn_control_connections']+=1
    return counts


def ingress_snapshot():
    """Global active nginx requests include upgraded tunnels; idle keep-alive is excluded.

    Exactly this status request contributes one Writing request. No generic upstream
    socket is subtracted or treated as idle. Every other Reading/Writing request,
    including unrelated co-hosted traffic, conservatively denies maintenance.
    """
    sample={'healthy':False,'read_started_at':int(time.time()),'observed_at':int(time.time())}
    try:
        if not synchronized():
            raise Deferred('clock_unknown')
        opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with opener.open('http://127.0.0.1:9277/status',timeout=2) as response:
            text=response.read(4096).decode('ascii')
        rows=re.findall(r'Reading: (\d+) Writing: (\d+) Waiting: (\d+)',text)
        if len(rows)!=1 or int(rows[0][1])<1:
            raise Deferred('ingress_status_invalid')
        props=unit_properties('nginx')
        if props['ActiveState']!='active' or int(props['MainPID'])<=1:
            raise Deferred('ingress_unhealthy')
        sample.update(healthy=True,generation=process_generation(int(props['MainPID'])),
                      counts={'ingress_reading':int(rows[0][0]),'ingress_writing':int(rows[0][1])-1})
    except (Deferred,OSError,ValueError,KeyError):
        sample['reason']='ingress_source_unavailable'
    sample['observed_at']=int(time.time())
    return sample



def package_busy():
    """Read locks conflict with native apt/dpkg write locks without changing files."""
    import fcntl
    handles=[]
    try:
        for filename in ('/var/lib/dpkg/lock-frontend','/var/lib/dpkg/lock'):
            stream=open(filename,'rb');handles.append(stream)
            fcntl.lockf(stream,fcntl.LOCK_SH|fcntl.LOCK_NB)
        return False
    except (BlockingIOError,OSError):return True
    finally:
        for stream in handles:stream.close()
