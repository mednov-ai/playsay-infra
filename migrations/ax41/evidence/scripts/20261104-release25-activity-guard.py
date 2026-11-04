"""Fail closed unless one contour is idle for 10m and clear for 60m."""
import json
import math
from pathlib import Path
import subprocess
import sys
import time
import urllib.parse
import urllib.request

K = ['sudo', 'kubectl']
namespaces = json.loads(subprocess.check_output(K + ['get', 'ns', '-o', 'json'], timeout=30))
namespace_names = {p['metadata']['name'] for p in namespaces['items']}
if ('playsay-prod' in namespace_names) == ('playsay-dev' in namespace_names):
    raise SystemExit('environment_not_identified')
environment = 'prod' if 'playsay-prod' in namespace_names else 'dev'
metrics = ['livekit_participant_total', 'livekit_room_total',
           'playsay_collaboration_active_connections',
           'playsay_collaboration_game_active_connections',
           'playsay_collaboration_snapshot_queue_size']

def query(expression):
    url = 'http://127.0.0.1:32085/victoria-metrics/api/v1/query?' + urllib.parse.urlencode({'query': expression})
    with urllib.request.urlopen(url, timeout=10) as response:
        data = json.load(response)
    if data.get('status') != 'success':
        raise RuntimeError('metric_query_failed')
    rows = data['data']['result']
    if len(rows) != 1:
        return None
    value = float(rows[0]['value'][1])
    return value if math.isfinite(value) else None


# A verified one-pod rollout retires telemetry labels. Keep all observed zero
# history; require a fresh current source and the independent actual reader.
planned_images = {
 'livekit': ('livekit', ('ghcr.io/mednov-ai/playsay-livekit-server@sha256:5bd1c9b8248dd70583d63fa1462104efd41f5d077d9cc7f16135cbb83932e6fe',)),
 'collaboration-service': ('playsay-prod', (
  'ghcr.io/mednov-ai/playsay-collaboration-service@sha256:52937581101f4d8e5ce6540256524620e7bd5ebb1dd9e292ee38779b74a067f5',
  'ghcr.io/mednov-ai/playsay-collaboration-service@sha256:60f457b06919bcca2f22678dd1556c85a3cd6b37bd122e7a05444ddadf55de2a',
 )),
}
def verified_restart(component):
    if environment != 'prod': return False
    ns, images = planned_images[component]
    def get(*args):
        return json.loads(subprocess.check_output(K + list(args) + ['-o','json'], timeout=30))
    app = get('-n','argocd','get','application',component)
    if app['spec']['source']['targetRevision'] != 'release/01.007.25' or app['status']['sync']['status'] != 'Synced' or app['status']['health']['status'] != 'Healthy': return False
    d = get('-n',ns,'get','deployment',component)
    if d['spec'].get('replicas',1) != 1 or d['status'].get('readyReplicas',0) != 1 or d['status'].get('observedGeneration',0) < d['metadata']['generation']: return False
    pods = [p for p in get('-n',ns,'get','pods')['items'] if p['metadata'].get('labels',{}).get('app.kubernetes.io/name') == component and p['status']['phase'] == 'Running']
    if len(pods) != 1 or pods[0]['metadata'].get('deletionTimestamp'): return False
    statuses = pods[0]['status'].get('containerStatuses',[])
    return bool(statuses) and all(c.get('ready') and c.get('restartCount') == 0 for c in statuses) and any(c['name'] == component and c['image'] in images for c in pods[0]['spec']['containers'])
restarted = {c: verified_restart(c) for c in planned_images}

safe = True
for name in metrics:
    row = {'metric': name, 'maxLast10Minutes': query('max(max_over_time(' + name + '[10m]))'),
           'minimumSampleCount': query('min(count_over_time(' + name + '[10m]))'),
           'maxAgeLast10Minutes': query('max(max_over_time((time()-timestamp(' + name + '))[10m:15s]))'),
           'age': query('max(time()-timestamp(' + name + '))')}
    component = 'livekit' if name.startswith('livekit_') else 'collaboration-service'
    if restarted[component]:
        row['verifiedCandidateProcessRestart'] = True
        row['historySampleCount'] = query('sum(count_over_time(' + name + '[10m]))')
        row['currentAge'] = query('min(time()-timestamp(' + name + '))')
        if row['maxLast10Minutes'] != 0 or row['historySampleCount'] is None or row['historySampleCount'] < 18 or row['currentAge'] is None or not 0 <= row['currentAge'] <= 30:
            safe = False
    elif (row['maxLast10Minutes'] != 0 or row['minimumSampleCount'] is None
            or row['minimumSampleCount'] < 18 or row['age'] is None or not 0 <= row['age'] <= 30
            or row['maxAgeLast10Minutes'] is None or not 0 <= row['maxAgeLast10Minutes'] <= 45):
        safe = False
    # Report the actual retired-series ages as well as the current-source proof.
    print(json.dumps(row), flush=True)

pods = json.loads(subprocess.check_output(K + ['-n', 'playsay-data', 'get', 'pods', '-o', 'json'], timeout=30))
primary = next(p['metadata']['name'] for p in pods['items'] if p['metadata'].get('labels', {}).get('role') == 'primary')
sql = """
SELECT count(*) FROM lesson WHERE status IS NULL OR (status <> 'CANCELLED' AND (
    scheduled_start IS NULL OR scheduled_end IS NULL OR access_extension_seconds IS NULL
    OR (scheduled_start <= now() + interval '60 minutes'
        AND scheduled_end + make_interval(secs => access_extension_seconds) + interval '10 minutes' > now())
))
"""
# Only operator-approved erroneous IDs are excluded; new/unknown windows block.
if environment == 'prod':
    approval=Path('/tmp/honey-stack-release25-tools-20261104/approved-error-lesson-ids.json')
    if approval.exists():
        approved=json.loads(approval.read_text())
        import re
        assert len(approved)==3 and all(re.fullmatch(r'[0-9a-f-]{36}', x) for x in approved)
        literals=','.join("'"+x+"'::uuid" for x in approved)
        sql=sql.replace("SELECT count(*) FROM lesson WHERE", "SELECT count(*) FROM lesson WHERE id NOT IN ("+literals+") AND (")+ ")"
count = int(subprocess.check_output(K + ['-n', 'playsay-data', 'exec', primary, '-c', 'postgres', '--',
                                         'psql', '-U', 'postgres', '-d', 'playsay', '-Atqc', sql], text=True, timeout=30).strip())
print(json.dumps({'environment': environment, 'protectedOrNextHourLessons': count,
                  'observedAt': int(time.time()), 'safe': safe and count == 0}), flush=True)
if not safe or count:
    sys.exit(1)

reader=json.loads(subprocess.check_output(['sudo','-n','/usr/local/sbin/honey-school-maintenance-guest-read'],text=True,timeout=40))
assert reader.get('healthy') is True and 0<=time.time()-reader['observed_at']<=30
assert reader.get('next_opening_known') is True
assert reader.get('counts') and all(isinstance(v,int) and v==0 for k,v in reader['counts'].items() if k!='lesson_windows')
print(json.dumps({'environment':environment,'freshGuestActivityZero':True}))
