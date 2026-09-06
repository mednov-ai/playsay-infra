#!/usr/bin/env python3
"""Add only dev location includes to existing routes; preserve other bytes."""
import argparse
from pathlib import Path
import re
import subprocess

INCLUDE = '        include /etc/nginx/snippets/honey-school-browser-entry.conf;\n'
HOSTS = {'dev.online.honey.school', 'dev.key.honey.school'}

def render(source):
    sections = re.split(r'(?=^server \{)', source, flags=re.M)
    count = 0
    for i, section in enumerate(sections):
        names = re.findall(r'^    server_name ([^;]+);', section, re.M)
        if not names or names[0] not in HOSTS:
            continue
        if len(names) != 1 or section.count('    location / {\n') != 1:
            raise ValueError('Unexpected dev vhost structure')
        count += 1
        if INCLUDE not in section:
            sections[i] = section.replace('    location / {\n', '    location / {\n' + INCLUDE)
    if count != 4:
        raise ValueError('Expected exactly four HTTP/HTTPS dev vhosts')
    return ''.join(sections)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    target = Path('/etc/nginx/conf.d/playsay-honey.conf')
    before = target.read_text()
    after = render(before)
    if before == after:
        print('unchanged')
    elif args.check:
        print('changed')
    else:
        try:
            target.write_text(after)
            subprocess.run(['nginx', '-t'], check=True, capture_output=True)
        except Exception:
            target.write_text(before)
            raise SystemExit('Dev route validation failed; previous routes restored')
        print('changed')
