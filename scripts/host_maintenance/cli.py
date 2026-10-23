"""Fixed entrypoints; guest read helper intentionally accepts no caller input."""
import json
import os
from pathlib import Path
import sys
import time

from .model import Deferred, atomic_json

CONFIG=Path('/etc/honey-school-maintenance/config.json')


def keys():
    directory=os.environ.get('CREDENTIALS_DIRECTORY')
    path=Path(directory)/'keys' if directory else CONFIG.parent/'keys.json'
    return json.loads(path.read_text())


def main(operation):
    config=json.loads(CONFIG.read_text())
    if len(sys.argv)!=1:raise SystemExit('arguments_not_allowed')
    if operation=='guest-read':
        if os.geteuid()!=0:raise SystemExit('privilege_required')
        from .collect import GuestCollector
        print(json.dumps(GuestCollector(config['role']).collect(),allow_nan=False))
    elif operation=='producer':
        from .collect import run
        from .wire import Client
        client=Client(config['coordinator_url'],config['role'],keys()['producer'],config['coordinator_address'])
        while True:
            try:
                sample=json.loads(run(['/usr/bin/sudo','-n','/usr/local/sbin/honey-school-maintenance-guest-read'],timeout=27))
                client.request('/activity',sample)
            except (Deferred,ValueError):pass
            time.sleep(3)
    elif operation=='agent':
        from .agent import Agent
        Agent(config,keys()).serve()
    elif operation=='plan':
        import fcntl
        from .packages import Planner
        if os.geteuid()!=0:raise SystemExit('privilege_required')
        root=Path(config['state_dir'])
        with (root/'executor.lock').open('a') as lock:
            try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
            except BlockingIOError:raise Deferred('local_owner_busy')
            path=root/'worker.json';state=json.loads(path.read_text()) if path.exists() else {}
            if state.get('phase','idle') not in ('idle','deferred'):raise Deferred('prior_transaction_requires_recovery')
            plan=Planner(root,json.loads(Path(config['package_policy']).read_text())).plan()
            atomic_json(root/'package-plan.json',plan)
            print(json.dumps({'eligible_count':len(plan['allowed']),'blocked_count':len(plan['blocked']),'pending_count':plan['pending_count']}))
    elif operation=='package-preflight':
        from .packages import installation_preflight
        installation_preflight(config,keys())
    elif operation=='execute':
        from .worker import Worker
        worker=Worker(config,keys())
        try:worker.run()
        except Deferred as error:
            worker.record_deferral(error.code);print('deferred='+error.code)
    elif operation=='restore':
        from .fence import AdmissionFence
        AdmissionFence(config['role'],config['state_dir']).restore()
    elif operation=='observe':
        from .monitor import observe
        observe(config)
    else:raise SystemExit('entrypoint_not_allowed')
