"""Build an ingress candidate by replacing one known HTTP challenge block only."""
import argparse
from pathlib import Path
import re


def patch_config(source, snippet, hostname, webroot):
    servers = list(re.finditer(r'(?ms)^server \{\n.*?^\}', source))
    targets = [s for s in servers if re.search(r'(?m)^    listen 80;$', s.group())
               and re.search(r'(?m)^    server_name ' + re.escape(hostname) + r';$', s.group())]
    if len(targets) != 1:
        raise ValueError('Expected exactly one existing HTTP server for the declared host')
    target = targets[0]
    pattern = r'(?ms)^    location \^~ /\.well-known/acme-challenge/ \{\n.*?^    \}\n(?:    location @ax41_acme_challenge \{\n.*?^    \}\n)?'
    blocks = list(re.finditer(pattern, target.group()))
    if len(blocks) != 1:
        raise ValueError('Expected exactly one HTTP ACME location')
    block = blocks[0]
    legacy = ('    location ^~ /.well-known/acme-challenge/ {\n'
              f'        root {webroot};\n'
              '        default_type text/plain;\n'
              '        try_files $uri =404;\n    }\n')
    snippet = snippet.rstrip() + '\n'
    if block.group() not in (legacy, snippet):
        raise ValueError('Unrecognized ACME location; preserve it for explicit review')
    begin, end = target.start() + block.start(), target.start() + block.end()
    return source[:begin] + snippet + source[end:]


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    for name in ['config', 'snippet', 'hostname', 'webroot', 'output']:
        parser.add_argument('--' + name, required=True)
    args = parser.parse_args()
    result = patch_config(Path(args.config).read_text(), Path(args.snippet).read_text(), args.hostname, args.webroot)
    Path(args.output).write_text(result)
