#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
group_vars="$repo_root/ansible/group_vars/ax41_hosts.yaml"
role_dir="$repo_root/ansible/roles/wireguard-dns"
playbook="$repo_root/ansible/playbooks/ax41-host.yaml"
macos_helper="$repo_root/scripts/configure-macos-wireguard-split-dns.sh"
macos_sync="$repo_root/scripts/macos/honey-school-wireguard-dns-sync.sh"
macos_plist="$repo_root/scripts/macos/school.honey.wireguard-split-dns.plist"

require_text() {
  local file="$1"
  local text="$2"
  if ! grep -Fq -- "$text" "$file"; then
    echo "split DNS contract missing in $file: $text" >&2
    exit 1
  fi
}

require_text "$group_vars" "wireguard_dns_listen_address: 10.250.0.1"
require_text "$group_vars" "- ops.honey.school"
require_text "$group_vars" "- dev.ops.honey.school"
require_text "$group_vars" "- jenkins.honey.school"
require_text "$playbook" "- role: wireguard-dns"
require_text "$role_dir/templates/playsay-wireguard-split-dns.conf.j2" "listen-address={{ wireguard_dns_listen_address }}"
require_text "$role_dir/templates/playsay-wireguard-split-dns.conf.j2" "bind-interfaces"
require_text "$role_dir/templates/playsay-wireguard-split-dns.conf.j2" "no-resolv"
require_text "$role_dir/templates/playsay-wireguard-split-dns.conf.j2" "host-record={{ hostname }},{{ wireguard_dns_listen_address }}"
require_text "$role_dir/templates/playsay-wireguard-dns.service.j2" "After=network-online.target wg-quick@{{ wireguard_interface }}.service"
require_text "$role_dir/templates/playsay-wireguard-dns.service.j2" "User=dnsmasq"
require_text "$role_dir/templates/playsay-wireguard-dns.service.j2" "AmbientCapabilities=CAP_NET_BIND_SERVICE"
require_text "$role_dir/templates/playsay-wireguard-dns.service.j2" "ProtectSystem=strict"
require_text "$role_dir/templates/playsay-wireguard-dns.service.j2" "RestrictAddressFamilies=AF_INET AF_NETLINK AF_UNIX"
require_text "$role_dir/tasks/main.yaml" "'hooks.honey.school' not in wireguard_dns_private_hostnames"
require_text "$role_dir/tasks/main.yaml" "validate: /usr/bin/systemd-analyze verify %s"
require_text "$role_dir/tasks/main.yaml" "ss -H -lntup sport = :53"
require_text "$macos_helper" 'service_label="school.honey.wireguard-split-dns"'
require_text "$macos_helper" 'action="${1:-install}"'
require_text "$macos_sync" 'resolver_file="$resolver_directory/honey.school"'
require_text "$macos_sync" "nameserver 10.250.0.1"
require_text "$macos_sync" 'elif [[ -e "$resolver_file" ]]'
require_text "$macos_plist" "school.honey.wireguard-split-dns"
require_text "$macos_plist" "<key>StartInterval</key>"

if sed -n '/wireguard_dns_private_hostnames:/,/^[^ ]/p' "$group_vars" |
  grep -Eq 'hooks\.honey\.school|(^|[.-])online\.honey\.school'; then
  echo "public application or webhook hostname leaked into split DNS" >&2
  exit 1
fi

echo "WireGuard split DNS contract is internally consistent."
