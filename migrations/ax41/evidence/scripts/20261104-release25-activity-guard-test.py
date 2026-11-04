"""Exercise the actual candidate process predicate without contacting a cluster."""
import ast
import copy
import json
from pathlib import Path
from types import SimpleNamespace

source = Path(__file__).with_name('20261104-release25-activity-guard.py')
tree = ast.parse(source.read_text())
selected = [node for node in tree.body if
            isinstance(node, ast.FunctionDef) and node.name == 'verified_restart' or
            isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'planned_images' for t in node.targets)]
module = ast.Module(body=selected, type_ignores=[])
results = []

def check(name, component='collaboration-service', image_index=1, mutate=None, environment='prod', expected=True):
    resources = {
        'application': {'spec': {'source': {'targetRevision': 'release/01.007.25'}},
                        'status': {'sync': {'status': 'Synced'}, 'health': {'status': 'Healthy'}}},
        'deployment': {'metadata': {'generation': 1}, 'spec': {'replicas': 1},
                       'status': {'readyReplicas': 1, 'observedGeneration': 1}},
        'pods': {'items': []},
    }
    def get(args, timeout):
        assert args[-2:] == ['-o', 'json']
        return json.dumps(resources[args[3]]).encode()
    scope = {'environment': environment, 'K': [], 'json': json,
             'subprocess': SimpleNamespace(check_output=get)}
    exec(compile(module, str(source), 'exec'), scope)
    image = scope['planned_images'][component][1][image_index]
    resources['pods']['items'] = [{
        'metadata': {'name': 'synthetic-pod', 'labels': {'app.kubernetes.io/name': component}},
        'spec': {'containers': [{'name': component, 'image': image}]},
        'status': {'phase': 'Running', 'containerStatuses': [{'name': component, 'ready': True, 'restartCount': 0}]},
    }]
    if mutate:
        mutate(resources)
    actual = scope['verified_restart'](component)
    assert actual == expected, name
    results.append({'case': name, 'eligible': actual, 'passed': True})

check('reviewed_original_collaboration', image_index=0)
check('reviewed_corrected_collaboration')
check('reviewed_livekit', component='livekit', image_index=0)
check('unknown_image', mutate=lambda r: r['pods']['items'][0]['spec']['containers'][0].update(image='unreviewed'), expected=False)
check('unhealthy_argo', mutate=lambda r: r['application']['status']['health'].update(status='Degraded'), expected=False)
check('wrong_release', mutate=lambda r: r['application']['spec']['source'].update(targetRevision='develop'), expected=False)
check('duplicate_pod', mutate=lambda r: r['pods']['items'].append(copy.deepcopy(r['pods']['items'][0])), expected=False)
check('unexpected_restart', mutate=lambda r: r['pods']['items'][0]['status']['containerStatuses'][0].update(restartCount=1), expected=False)
check('unready_pod', mutate=lambda r: r['pods']['items'][0]['status']['containerStatuses'][0].update(ready=False), expected=False)
check('unobserved_deployment', mutate=lambda r: r['deployment']['status'].update(observedGeneration=0), expected=False)
check('dev_cannot_use_prod_continuity', environment='dev', expected=False)
print(json.dumps(results, indent=2))
