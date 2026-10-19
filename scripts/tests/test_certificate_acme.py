"""Exercise the rendered production template against real isolated nginx."""
import contextlib
import json
from pathlib import Path
import subprocess
import tempfile
import time
import unittest
import urllib.error
import urllib.request

import jinja2
import yaml

ROOT = Path(__file__).resolve().parents[2]
TEMPLATES = ROOT / 'ansible/roles/rf-edge-proxy/templates'


def render(routes):
    env = jinja2.Environment(loader=jinja2.FileSystemLoader(TEMPLATES), undefined=jinja2.StrictUndefined)
    env.filters['bool'] = bool
    return env.get_template('playsay-honey-rf-edge.conf.j2').render(
        rf_edge_routes=routes, rf_edge_render_globals=True, rf_edge_dev_bootstrap=True,
        rf_edge_origin_address='127.0.0.1:8081', rf_edge_acme_webroot='/fixtures/local',
        rf_edge_certificate_directory='/not-used', rf_edge_tls_enabled=False, ansible_host='127.0.0.1')


class AcmeRuntime(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='hs-acme-')
        cls.directory = Path(cls.temp.name)
        variables = yaml.safe_load((ROOT / 'ansible/group_vars/rf_edges.yaml').read_text())
        cls.routes = [r for r in variables['rf_edge_production_routes'] + variables['rf_edge_development_routes'] if r['kind'] == 'keycloak']
        cls.routes += [{'hostname': 'other.honey.school', 'kind': 'keycloak', 'realm': 'playsay'}]
        text = render(cls.routes).replace('listen 80;', 'listen 8080;').replace('listen [::]:80;', 'listen [::]:8080;')
        for side in ['local', 'origin']:
            directory = cls.directory / side / '.well-known/acme-challenge'
            directory.mkdir(parents=True)
            (directory / 'collision').write_text(side)
        (cls.directory / 'origin/.well-known/acme-challenge/origin_only').write_text('origin')
        (cls.directory / 'local/.well-known/acme-challenge/unreachable').write_text('local')
        config = '''events {}\nhttp { default_type text/plain;
server { listen 8081; root /fixtures/origin;
 location = /.well-known/acme-challenge/unreachable { return 502; }
 location / { try_files $uri =404; add_header X-Fixture-Headers "$http_authorization|$http_cookie|$http_x_forwarded_for|$http_host|$content_length" always; }
}\n''' + text + '\n}\n'
        (cls.directory / 'nginx.conf').write_text(config)
        cmd = ['docker','run','--pull=never','--rm','-d','-p','127.0.0.1::8080','-v',str(cls.directory)+':/fixtures:ro','nginx:stable-alpine','nginx','-c','/fixtures/nginx.conf','-g','daemon off;']
        cls.container = subprocess.check_output(cmd, text=True).strip()
        try:
            port = subprocess.check_output(['docker','port',cls.container,'8080/tcp'],text=True).strip().rsplit(':',1)[1]
            cls.base = 'http://127.0.0.1:'+port
            for _ in range(30):
                try:
                    cls.request('origin_only'); break
                except OSError:
                    time.sleep(.1)
            else:
                raise RuntimeError('fixture_nginx_unavailable')
        except Exception:
            subprocess.run(['docker','rm','-f',cls.container],capture_output=True)
            cls.temp.cleanup()
            raise

    @classmethod
    def tearDownClass(cls):
        subprocess.run(['docker','rm','-f',cls.container],capture_output=True)
        cls.temp.cleanup()

    @classmethod
    def request(cls, token, host='ops.honey.school', method='GET', headers=None):
        request = urllib.request.Request(cls.base+'/.well-known/acme-challenge/'+token,
            method=method, headers={'Host':host, **(headers or {})})
        try:
            response = urllib.request.urlopen(request,timeout=7)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            return response.status, response.read(), response.headers

    def test_local_wins_collision_and_origin_failure(self):
        for token in ['collision','unreachable']:
            status, body, _ = self.request(token)
            self.assertEqual((status,body),(200,b'local'))

    def test_origin_fallback_prod_and_dev(self):
        for host in ['ops.honey.school','dev.ops.honey.school']:
            self.assertEqual(self.request('origin_only',host)[:2],(200,b'origin'))

    def test_no_fallback_for_unrelated_host(self):
        self.assertEqual(self.request('origin_only','other.honey.school')[0],404)

    def test_missing_and_invalid_paths(self):
        for token in ['absent','%6frigin_only','origin_only/extra','../outside','origin_only?x=1','']:
            self.assertEqual(self.request(token)[0],404,token)

    def test_methods_and_head(self):
        self.assertEqual(self.request('origin_only',method='HEAD')[:2],(200,b''))
        for method in ['POST','PUT','DELETE']:
            self.assertEqual(self.request('origin_only',method=method)[0],403)

    def test_credentials_not_forwarded(self):
        status, _, headers = self.request('origin_only',headers={'Authorization':'Basic fixture','Cookie':'fixture=1','X-Forwarded-For':'fixture','Content-Length':'0'})
        self.assertEqual(status,200)
        self.assertEqual(headers.get('X-Fixture-Headers'),'|||ops.honey.school|')
        self.assertEqual(headers.get('Cache-Control'),'no-store')

    def test_nginx_syntax_and_invalid_configuration(self):
        run = subprocess.run(['docker','exec',self.container,'nginx','-t','-c','/fixtures/nginx.conf'],capture_output=True)
        self.assertEqual(run.returncode,0,run.stderr)
        (self.directory / 'invalid.conf').write_text('invalid_nginx_directive;')
        run = subprocess.run(['docker','exec',self.container,'nginx','-t','-c','/fixtures/invalid.conf'],capture_output=True)
        self.assertNotEqual(run.returncode,0)
        self.assertEqual(self.request('origin_only')[0],200)


class RouteBoundary(unittest.TestCase):
    def test_https_routes_unchanged_in_both_contours(self):
        variables=yaml.safe_load((ROOT/'ansible/group_vars/rf_edges.yaml').read_text())
        old=subprocess.check_output(['git','show','HEAD:ansible/roles/rf-edge-proxy/templates/playsay-honey-rf-edge.conf.j2'],cwd=ROOT,text=True)
        env=jinja2.Environment(loader=jinja2.FileSystemLoader(TEMPLATES),undefined=jinja2.StrictUndefined);env.filters['bool']=bool
        for key,globals_enabled in [('rf_edge_production_routes',True),('rf_edge_development_routes',False)]:
            context={**variables,'rf_edge_routes':variables[key],'rf_edge_render_globals':globals_enabled,'ansible_host':'94.102.89.213'}
            before=env.from_string(old).render(context);after=env.get_template('playsay-honey-rf-edge.conf.j2').render(context)
            before_tls=[x.strip() for x in before.split('server {') if 'listen 443 ssl;' in x]
            after_tls=[x.strip() for x in after.split('server {') if 'listen 443 ssl;' in x]
            self.assertEqual(before_tls,after_tls)

    def test_ansible_shared_template_include_resolves_for_dev(self):
        with tempfile.TemporaryDirectory() as directory:
            play=Path(directory)/'template.yaml';dest=Path(directory)/'dev.conf'
            variables={'rf_edge_routes':[{'hostname':'dev.ops.honey.school','origin_hostname':'dev.ops.honey.school','kind':'keycloak','realm':'playsay','origin_acme_fallback':True}],
                'rf_edge_render_globals':False,'rf_edge_dev_bootstrap':True,'rf_edge_origin_address':'65.109.55.110',
                'rf_edge_acme_webroot':'/fixture','rf_edge_certificate_directory':'/unused','rf_edge_tls_enabled':False}
            play.write_text(yaml.safe_dump([{'hosts':'localhost','gather_facts':False,'vars':variables,'tasks':[{'ansible.builtin.template':{'src':str(TEMPLATES/'playsay-honey-rf-edge.conf.j2'),'dest':str(dest)}}]}]))
            run=subprocess.run(['ansible-playbook','-i','localhost,','-c','local',str(play)],capture_output=True)
            self.assertEqual(run.returncode,0,run.stdout.decode())
            self.assertIn('proxy_set_header Host dev.ops.honey.school;',dest.read_text())

    def test_ansible_assertions_reject_unowned_routes(self):
        good={'hostname':'ops.honey.school','origin_hostname':'ops.honey.school','kind':'keycloak','origin_acme_fallback':True}
        cases=[(good,'65.109.55.110',0),({**good,'hostname':'other.honey.school'},'65.109.55.110',2),
               (good,'127.0.0.1',2),({**good,'aliases':['other.honey.school']},'65.109.55.110',2),
               ({**good,'origin_hostname':'other.honey.school'},'65.109.55.110',2)]
        with tempfile.TemporaryDirectory() as directory:
            play=Path(directory)/'test.yaml'
            for route,origin,expected in cases:
                play.write_text(yaml.safe_dump([{'hosts':'localhost','gather_facts':False,'vars':{'rf_edge_routes':[route],'rf_edge_origin_address':origin},
                    'tasks':[{'ansible.builtin.import_tasks':str(ROOT/'ansible/roles/rf-edge-proxy/tasks/validate-acme.yaml')}]}]))
                run=subprocess.run(['ansible-playbook','-i','localhost,','-c','local',str(play)],capture_output=True)
                self.assertEqual(run.returncode,expected,run.stdout.decode())


if __name__ == '__main__':
    unittest.main()
