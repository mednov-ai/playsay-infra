"""Run with Ansible's Python (PyYAML/Jinja2); local docker smoke is separate."""
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
import jinja2
import yaml

ROOT=Path(__file__).resolve().parents[2]
class IngressTest(unittest.TestCase):
    def test_rendered_scope(self):
        values=yaml.safe_load((ROOT/'ansible/group_vars/ax41_hosts.yaml').read_text())
        route=next(r for r in values['edge_routes'] if r['hostname']=='ops.honey.school')
        env=jinja2.Environment(loader=jinja2.FileSystemLoader(ROOT/'ansible/roles/edge-proxy/templates'))
        rendered=env.get_template('production-log-ingress.conf.j2').render(route=route,edge_vpn_subnet=values['edge_vpn_subnet'])
        self.assertIn('deny all;',rendered); self.assertIn('limit_except POST { deny all; }',rendered)
        self.assertIn('production-log-ingest.htpasswd',rendered); self.assertNotIn('edge-log-ingest.htpasswd',rendered)
        self.assertIn('_time_field=timestamp',rendered); self.assertIn('/select/vmalert/ { return 403; }',rendered)
        self.assertNotIn('/livekit',rendered); self.assertNotIn('/collaboration',rendered)
        route['victoria_logs_ingress_enabled']=False
        rollback=env.get_template('production-log-ingress.conf.j2').render(route=route,edge_vpn_subnet=values['edge_vpn_subnet'])
        self.assertNotIn('proxy_pass',rollback); self.assertNotIn('auth_basic',rollback)
        self.assertIn('return 403',rollback)

    def test_scoped_include_idempotence_and_ambiguous_rejection(self):
        config='''server { listen 80; server_name ops.honey.school; location / { return 301 https://$host$request_uri; } }
server { listen 443 ssl; server_name dev.ops.honey.school; location / { return 200; } }
server { listen 443 ssl; server_name ops.honey.school; location ~ "^/item/[a-z]{2}$" { return 200; } }
'''
        script=ROOT/'ansible/roles/production-log-ingress/files/install-include.py'
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'nginx.conf'; path.write_text(config)
            first=subprocess.check_output(['python3',str(script),str(path)]).decode()
            self.assertEqual(first.count('honey-production-logs.conf'),1)
            self.assertIn(config.splitlines()[0],first); self.assertIn(config.splitlines()[1],first)
            path.write_text(first); self.assertEqual(first,subprocess.check_output(['python3',str(script),str(path)]).decode())
            path.write_text(config+config.splitlines()[2]+'\n')
            result=subprocess.run(['python3',str(script),str(path)],capture_output=True)
            self.assertNotEqual(result.returncode,0)

    def test_prod_helm_and_unchanged_dev_render(self):
        for chart in ('monitoring-lite','collaboration-service'):
            base=subprocess.check_output(['git','show',f'HEAD:helm-charts/{chart}/values-prod.yaml'],cwd=ROOT).decode()
            current=(ROOT/f'helm-charts/{chart}/values-prod.yaml').read_text()
            b=yaml.safe_load(base); a=yaml.safe_load(current)
            if 'image' in b: self.assertEqual(b['image'],a['image'])
        rendered=subprocess.check_output(['helm','template','monitoring-lite',str(ROOT/'helm-charts/monitoring-lite'),'-f',str(ROOT/'helm-charts/monitoring-lite/values-prod.yaml')]).decode()
        docs=list(yaml.safe_load_all(rendered))
        vl=next(x for x in docs if x['kind']=='Deployment' and x['metadata']['name'].endswith('victoria-logs'))
        container=vl['spec']['template']['spec']['containers'][0]
        self.assertIn('@sha256:',container['image']); self.assertIn('-retentionPeriod=7d',container['args'])
        self.assertEqual(container['resources']['limits']['memory'],'512Mi')
        rules=next(x for x in docs if x['kind']=='ConfigMap' and x['metadata']['name'].endswith('vmalert-rules'))
        alerts=yaml.safe_load(rules['data']['alerts.yaml'])
        group=next(x for x in alerts['groups'] if x['name']=='honey-production-logs')
        self.assertEqual(len([x for x in group['rules'] if x['alert']=='HoneyProductionLogSourceMissing']),6)
        with tempfile.TemporaryDirectory() as directory:
            old=Path(directory)/'chart'; old.mkdir()
            files=subprocess.check_output(['git','ls-tree','-r','--name-only','HEAD','helm-charts/monitoring-lite'],cwd=ROOT).decode().splitlines()
            for file in files:
                path=old/Path(file).relative_to('helm-charts/monitoring-lite'); path.parent.mkdir(parents=True,exist_ok=True)
                path.write_bytes(subprocess.check_output(['git','show','HEAD:'+file],cwd=ROOT))
            before=subprocess.check_output(['helm','template','monitoring-lite',str(old),'-f',str(old/'values-dev.yaml')])
            after=subprocess.check_output(['helm','template','monitoring-lite',str(ROOT/'helm-charts/monitoring-lite'),'-f',str(ROOT/'helm-charts/monitoring-lite/values-dev.yaml')])
            self.assertEqual(before,after)

if __name__=='__main__': unittest.main()
