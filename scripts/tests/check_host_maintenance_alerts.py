#!/usr/bin/env python3
"""Render exact chart rules and exercise debt firing/resolution without remote calls."""
import argparse
from pathlib import Path
import subprocess
import tempfile
import yaml

parser = argparse.ArgumentParser()
parser.add_argument('--promtool', required=True)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
rendered = subprocess.check_output(['helm', 'template', 'maintenance-test', str(repo/'helm-charts/monitoring-lite'),
                                    '-f', str(repo/'helm-charts/monitoring-lite/values-prod.yaml')], text=True)
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
    (root/'tests.yaml').write_text(yaml.safe_dump(fixture))
    subprocess.run([args.promtool, 'check', 'rules', 'rules.yaml'], cwd=root, check=True)
    subprocess.run([args.promtool, 'test', 'rules', 'tests.yaml'], cwd=root, check=True)
