#!/bin/bash
set -euo pipefail

resolver_directory="/etc/resolver"
resolver_file="$resolver_directory/honey.school"
wireguard_dns="10.250.0.1"
wireguard_client_address="10.250.0.2"

route_interface="$(/sbin/route -n get "$wireguard_dns" 2>/dev/null | /usr/bin/awk '/interface:/{print $2; exit}')"
wireguard_active=false

if [[ "$route_interface" == utun* ]] &&
  /sbin/ifconfig "$route_interface" | /usr/bin/grep -Eq "inet[[:space:]]+$wireguard_client_address([[:space:]]|$)"; then
  wireguard_active=true
fi

resolver_changed=false

if [[ "$wireguard_active" == true ]]; then
  temporary_file="$(/usr/bin/mktemp -t honey-school-wireguard-dns)"
  trap '/bin/rm -f "$temporary_file"' EXIT

  /bin/cat >"$temporary_file" <<'EOF'
# Managed by school.honey.wireguard-split-dns.
nameserver 10.250.0.1
timeout 2
options attempts:1
EOF

  /bin/mkdir -p "$resolver_directory"
  /bin/chmod 0755 "$resolver_directory"
  if [[ ! -f "$resolver_file" ]] || ! /usr/bin/cmp -s "$temporary_file" "$resolver_file"; then
    /usr/bin/install -o root -g wheel -m 0644 "$temporary_file" "$resolver_file"
    resolver_changed=true
  fi
elif [[ -e "$resolver_file" ]]; then
  /bin/rm -f "$resolver_file"
  resolver_changed=true
fi

if [[ "$resolver_changed" == true ]]; then
  /usr/bin/dscacheutil -flushcache
  /usr/bin/killall -HUP mDNSResponder || true
fi
