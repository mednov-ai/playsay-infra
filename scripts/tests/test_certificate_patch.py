import importlib.util
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('patcher',ROOT/'scripts/patch-certificate-acme-ingress.py')
patcher=importlib.util.module_from_spec(spec);spec.loader.exec_module(patcher)


class ScopedIngress(unittest.TestCase):
    def test_preserves_unrelated_bytes_and_is_idempotent(self):
        old='    location ^~ /.well-known/acme-challenge/ {\n        root /acme;\n        default_type text/plain;\n        try_files $uri =404;\n    }\n'
        before='server {\n    listen 80;\n    server_name ops.honey.school;\n\n'+old+'    location / { return 301 https://$host$request_uri; }\n}\nserver {\n    listen 443 ssl;\n    server_name ops.honey.school;\n    # preserve operator HTTPS configuration byte for byte\n}\n'
        snippet=old.replace('try_files $uri =404;', 'try_files $uri @ax41_acme_challenge;')+'    location @ax41_acme_challenge {\n        internal;\n        proxy_pass http://65.109.55.110;\n    }\n'
        result=patcher.patch_config(before,snippet,'ops.honey.school','/acme')
        self.assertEqual(result,before.replace(old,snippet,1))
        self.assertEqual(patcher.patch_config(result,snippet,'ops.honey.school','/acme'),result)
        for source,hostname in [(before,'other.honey.school'),(before+before,'ops.honey.school'),(before.replace('root /acme;', 'root /custom;'),'ops.honey.school')]:
            with self.assertRaises(ValueError):patcher.patch_config(source,snippet,hostname,'/acme')
