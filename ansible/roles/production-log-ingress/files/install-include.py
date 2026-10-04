#!/usr/bin/env python3
"""Return only the existing AX41 config plus one scoped include in prod ops TLS."""
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text()
include = '    include /etc/nginx/snippets/honey-production-logs.conf;\n'
# Tokenize braces while ignoring comments and quoted regex/body strings.
tokens = re.finditer(r'#[^\n]*|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|[{}]', text)
stack = []; blocks = []
for token in tokens:
    if token[0] == '{': stack.append(token.start())
    elif token[0] == '}':
        start = stack.pop()
        prefix = text[max(0,start-30):start]
        if re.search(r'\bserver\s*$', prefix): blocks.append((start, token.end()))
selected = []
for start,end in blocks:
    body=text[start:end]
    if re.search(r'\bserver_name\s+ops\.honey\.school\s*;',body) and re.search(r'\blisten\s+[^;]*443[^;]*ssl',body): selected.append((start,end))
if len(selected)!=1: raise SystemExit('expected exactly one production ops TLS server')
start,end=selected[0]
if include.strip() in text[start:end]: sys.stdout.write(text); raise SystemExit(0)
if '/victoria-logs/' in text[start:end] or '/production-log-metrics' in text[start:end]: raise SystemExit('production logging routes already exist; reconcile reviewed template first')
text=text[:end-1]+include+text[end-1:]
sys.stdout.write(text)
