"""Private aggregate metrics; unknown preserves debt and never refreshes a source."""
import json
from pathlib import Path
import subprocess
import time
from .collect import service_runtime
from .model import Journal, atomic_json, service_debt


def observe(config):
    root=Path(config['state_dir']);now=int(time.time());role=config['role']
    readings={unit:service_runtime(unit,options.get('optional',False)) for unit,options in config['services'].items()}
    journal=Journal(root)
    with journal.locked('debt') as state:
        old=state.get('services',{})
        aggregate=root/'state.json'
        prior=json.loads(aggregate.read_text()).get('restart',{}).get('first_pending_at') if aggregate.exists() else None
        if type(prior) is int and 0<prior<=now:
            old={**old}
            for unit,value in readings.items():
                if unit not in old and value and value['pending']:
                    old[unit]={'first_pending_at':prior}
        state['services']=service_debt(old,readings,now)
        services=state['services']
    def read(name):
        path=root/(name+'.json')
        return json.loads(path.read_text()) if path.exists() else {}
    local=read('local');worker=read('worker');lease=read('coordinator');observations=read('observations')
    lines=[]
    def emit(metric,value,**extra):
        labels={'owner':role,**extra}
        # All label values come from the root-owned finite inventory.
        label=','.join(k+'="'+v+'"' for k,v in labels.items())
        lines.append('honey_host_executor_'+metric+'{'+label+'} '+str(value))
    emit('checked_at',now);emit('enabled',int(config.get('enabled') is True))
    emit('lease_claimed_at',lease.get('first_claimed_at',0) if lease.get('phase','idle')!='idle' else 0)
    emit('lease_heartbeat_at',lease.get('heartbeat_at',0) if lease.get('phase','idle')!='idle' else 0)
    emit('recovery_required',int(worker.get('phase') in ('recovery_required','failed_unsafe','overrun')))
    marker=Path('/var/lib/honey-school-maintenance-admission/closed')
    emit('fence_closed_at',int(marker.stat().st_mtime) if marker.exists() else 0)
    emit('last_completed_at',worker.get('last_completed_at',0))
    for unit,value in services.items():
        emit('service_checked_at',now,service=unit)
        emit('service_discovery_healthy',int(value.get('healthy',False)),service=unit)
        emit('service_pending',int(value.get('pending',False)),service=unit)
        emit('service_first_pending_at',value.get('first_pending_at',0),service=unit)
    for source,value in [('ingress',local.get('ingress',{}))]+([('turn',local.get('turn',{}))] if role=='selectel' else [(name,observations.get(name,{})) for name in ('prod','dev')]):
        emit('source_checked_at',value.get('observed_at',0),source=source)
        emit('source_healthy',int(value.get('healthy') is True),source=source)
    payload=''.join(line+' '+str(now*1000)+'\n' for line in lines)
    (root/'executor-metrics.prom').write_text(payload)
    url=('http://10.60.0.20:32085' if role=='ax41' else 'https://ops.honey.school')+'/victoria-metrics/api/v1/import/prometheus'
    args=['/usr/bin/curl','--silent','--fail','--connect-timeout','3','--max-time','15']
    if role=='selectel':args+=['--config','/etc/playsay/rf-edge-observability-curl.conf','--resolve','ops.honey.school:443:65.109.55.110']
    result=subprocess.run(args+['--data-binary','@-',url],input=payload,text=True,capture_output=True,timeout=20)
    if result.returncode:raise SystemExit('publication_failed')
