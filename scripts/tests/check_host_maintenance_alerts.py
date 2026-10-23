#!/usr/bin/env python3
"""Render exact chart rules and exercise debt firing/resolution without remote calls."""
import argparse
from pathlib import Path
import subprocess
import tempfile
import yaml

parser = argparse.ArgumentParser()
parser.add_argument('--promtool', required=True)
parser.add_argument('--executor', action='store_true')
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
rendered = subprocess.check_output(['helm', 'template', 'maintenance-test', str(repo/'helm-charts/monitoring-lite'),
                                    '-f', str(repo/'helm-charts/monitoring-lite/values-prod.yaml'), '--set', 'hostMaintenance.executorEnabled='+str(args.executor).lower()], text=True)
config = next(x for x in yaml.safe_load_all(rendered) if x and x.get('kind') == 'ConfigMap' and 'host-maintenance.yaml' in x.get('data', {}))
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    (root/'rules.yaml').write_text(config['data']['host-maintenance.yaml'])
    fixture = {
        'rule_files': ['rules.yaml'], 'evaluation_interval': '1h',
        'tests': [{'interval': '1h', 'input_series': [
            {'series': 'honey_host_maintenance_installation_first_pending_at{owner="ax41"}',
             'values': '1+0x74 stale'},
        ], 'alert_rule_test': [
            {'eval_time': '24h', 'alertname': 'HoneyHostMaintenanceDebtWarning', 'exp_alerts': []},
            {'eval_time': '25h', 'alertname': 'HoneyHostMaintenanceDebtWarning', 'exp_alerts': [
                {'exp_labels': {'owner': 'ax41', 'severity': 'warning'}, 'exp_annotations':
                 {'summary': 'Security work deferred for more than 24 hours'}}]},
            {'eval_time': '73h', 'alertname': 'HoneyHostMaintenanceDebtCritical', 'exp_alerts': [
                {'exp_labels': {'owner': 'ax41', 'severity': 'critical'}, 'exp_annotations':
                 {'summary': 'Security work deferred for more than 72 hours'}}]},
            {'eval_time': '75h', 'alertname': 'HoneyHostMaintenanceDebtWarning', 'exp_alerts': []},
        ]}]
    }
    if args.executor:
        fixture['tests'][0]['input_series'].append({'series':'honey_host_executor_service_first_pending_at{owner="selectel",service="nginx"}','values':'1+0x74 0'})
        for hour,name,severity in [(25,'HoneyHostExecutorRuntimeDebtWarning','warning'),(73,'HoneyHostExecutorRuntimeDebtCritical','critical')]:
            fixture['tests'][0]['alert_rule_test'].append({'eval_time':str(hour)+'h','alertname':name,'exp_alerts':[{'exp_labels':{'owner':'selectel','service':'nginx','severity':severity},'exp_annotations':{'summary':'Service runtime restart deferred for more than '+('24' if severity=='warning' else '72')+' hours'}}]})
        fixture['tests'][0]['alert_rule_test'].append({'eval_time':'75h','alertname':'HoneyHostExecutorRuntimeDebtWarning','exp_alerts':[]})
    fixture['tests'].append({'interval':'1m','input_series':[
        {'series':'honey_host_maintenance_discovery_healthy{owner="selectel"}','values':'0+0x15'},
        {'series':'honey_host_executor_enabled{owner="selectel"}','values':'1+0x15'}],
        'alert_rule_test':[{'eval_time':'15m','alertname':'HoneyHostMaintenanceDiscoveryFailed','exp_alerts':[]}]})
    import shlex
    expression = next(shlex.split(line)[2] for line in (repo/'scripts/collect-classroom-route-incident.sh').read_text().splitlines()
                      if line.startswith('query_value rf_nic_error_drop_increase '))
    for counter, expected in [('0+0x180', True), ('10+0x89 0+0x90', True), ('_x170 0+0x9', False)]:
        fixture['tests'].append({'interval': '5s', 'input_series': [
            {'series': 'playsay_rf_host_nic_error_drop_total{semantics_version="2"}', 'values': counter},
            {'series': 'playsay_rf_host_nic_error_drop_total', 'values': '100000+10000x180'},
            {'series': 'playsay_rf_host_nic_collection_healthy{semantics_version="2"}', 'values': '1+0x180'},
            {'series': 'playsay_rf_host_nic_checked_at{semantics_version="2"}', 'values': '0+5x180'},
        ], 'promql_expr_test': [{'eval_time': '15m', 'expr': expression,
                                'exp_samples': [{'labels': '{semantics_version="2"}', 'value': 0}] if expected else []}]})
    nic_fixture = {'rule_files': ['rules.yaml'], 'evaluation_interval': '5s', 'tests': fixture['tests'][1:]}
    fixture['tests'] = fixture['tests'][:1]
    if args.executor:
        sources={'ax41':['ingress','prod','dev'],'selectel':['ingress','turn']}
        series=[]
        for owner,items in sources.items():
            for source in items:
                labels='{owner="'+owner+'",source="'+source+'"}'
                series.append({'series':'honey_host_executor_source_checked_at'+labels,'values':'0+60x5'})
                series.append({'series':'honey_host_executor_source_healthy'+labels,'values':'0+0x2 1+0x2' if (owner,source)==('ax41','prod') else '1+0x5'})
        extra={'rule_files':['rules.yaml'],'evaluation_interval':'1m','tests':[{'interval':'1m','input_series':series,'alert_rule_test':[
            {'eval_time':'2m','alertname':'HoneyHostExecutorSourceUnavailable','exp_alerts':[{'exp_labels':{'owner':'ax41','source':'prod','severity':'critical'},'exp_annotations':{'summary':'Required maintenance activity source unavailable'}}]},
            {'eval_time':'4m','alertname':'HoneyHostExecutorSourceUnavailable','exp_alerts':[]}
        ]}]}
        (root/'executor-tests.yaml').write_text(yaml.safe_dump(extra))
        subprocess.run([args.promtool,'test','rules','executor-tests.yaml'],cwd=root,check=True)
    (root/'nic-tests.yaml').write_text(yaml.safe_dump(nic_fixture))
    (root/'tests.yaml').write_text(yaml.safe_dump(fixture))
    subprocess.run([args.promtool, 'check', 'rules', 'rules.yaml'], cwd=root, check=True)
    subprocess.run([args.promtool, 'test', 'rules', 'tests.yaml', 'nic-tests.yaml'], cwd=root, check=True)
