#!/usr/bin/env python3
import importlib.util
from pathlib import Path
spec=importlib.util.spec_from_file_location('reconcile',Path(__file__).resolve().parents[1]/'ansible/roles/honey-school-geoip/files/reconcile-prod-geoip.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
def block(host):return 'server {\n    server_name '+host+';\n    location / {\n        proxy_pass http://upstream;\n    }\n}\n'
protected=''.join(block(h) for h in ['ops.honey.school','dev.online.honey.school','dev.key.honey.school','online.honeyschool.ru'])
source=''.join(block(h)*2 for h in sorted(m.HOSTS))+protected
result=m.render(source)
assert result.count(m.INCLUDE)==6 and result.endswith(protected)
assert result.replace(m.INCLUDE,'')==source
assert m.render(result)==result
for invalid in [source.replace(block('honey.school'),'',1),source+block('honey.school'),source.replace('    location / {\n','    location /other {\n',1)]:
 try:m.render(invalid)
 except ValueError:pass
 else:raise AssertionError('Unexpected topology accepted')
print('PASS production-only includes, byte preservation, idempotency and topology rejection')
