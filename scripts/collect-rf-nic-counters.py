#!/usr/bin/env python3
"""Owned-interface kernel counters. No packet/byte fields or inferred loss rates."""
import argparse
from pathlib import Path
import re
import time

FIELDS = ('rx_errors', 'rx_dropped', 'tx_errors', 'tx_dropped')


def collect(root, interfaces, now):
    if not interfaces or len(set(interfaces)) != len(interfaces) or any(not re.fullmatch(r'[A-Za-z0-9_.-]+', i) or i == 'lo' for i in interfaces):
        raise ValueError('interface_inventory')
    rows = []
    try:
        for interface in interfaces:
            values = {}
            for field in FIELDS:
                text = (Path(root) / interface / 'statistics' / field).read_text().strip()
                if not re.fullmatch(r'[0-9]+', text):
                    raise ValueError('invalid_counter')
                values[field] = int(text)
            rows.append((interface, values))
    except (OSError, ValueError):
        return 'playsay_rf_host_nic_collection_healthy{semantics_version="2"} 0\n', False
    lines = ['playsay_rf_host_nic_collection_healthy{semantics_version="2"} 1',
             f'playsay_rf_host_nic_checked_at{{semantics_version="2"}} {now}']
    for interface, values in rows:
        for field, value in values.items():
            lines.append(f'playsay_rf_host_nic_{field}_total{{semantics_version="2",interface="{interface}"}} {value}')
    lines.append('playsay_rf_host_nic_error_drop_total{semantics_version="2"} ' + str(sum(sum(v.values()) for _, v in rows)))
    return '\n'.join(lines) + '\n', True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', default='/sys/class/net')
    parser.add_argument('--interface', action='append', required=True)
    args = parser.parse_args()
    output, healthy = collect(args.root, args.interface, int(time.time()))
    print(output, end='')
    return 0 if healthy else 1


if __name__ == '__main__':
    raise SystemExit(main())
