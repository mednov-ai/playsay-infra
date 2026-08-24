#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
daemon_source="$repo_root/scripts/macos/honey-school-wireguard-dns-sync.sh"
plist_source="$repo_root/scripts/macos/school.honey.wireguard-split-dns.plist"
daemon_destination="/usr/local/libexec/honey-school-wireguard-dns-sync"
plist_destination="/Library/LaunchDaemons/school.honey.wireguard-split-dns.plist"
resolver_file="/etc/resolver/honey.school"
service_label="school.honey.wireguard-split-dns"
wireguard_dns="10.250.0.1"
action="${1:-install}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This helper configures the macOS resolver only." >&2
  exit 1
fi

case "$action" in
  install)
    ;;
  status)
    launchctl print "system/$service_label"
    if [[ -f "$resolver_file" ]]; then
      sed -n '1,20p' "$resolver_file"
    else
      echo "$resolver_file is absent because the WireGuard route is inactive."
    fi
    exit 0
    ;;
  uninstall)
    sudo launchctl bootout "system/$service_label" 2>/dev/null || true
    sudo rm -f "$plist_destination" "$daemon_destination" "$resolver_file"
    sudo dscacheutil -flushcache
    sudo killall -HUP mDNSResponder
    echo "Removed the Honey School macOS split DNS service."
    exit 0
    ;;
  *)
    echo "Usage: $0 [install|status|uninstall]" >&2
    exit 2
    ;;
esac

private_hostnames=(
  ops.honey.school
  dev.ops.honey.school
  jenkins.honey.school
)

for hostname in "${private_hostnames[@]}"; do
  answer="$(dig +short "@$wireguard_dns" "$hostname" A | paste -sd ',' -)"
  if [[ "$answer" != "$wireguard_dns" ]]; then
    echo "WireGuard DNS preflight failed for $hostname: ${answer:-no answer}" >&2
    exit 1
  fi
done

public_answer="$(dig +short "@$wireguard_dns" honey.school A | head -n 1)"
if [[ -z "$public_answer" || "$public_answer" == "$wireguard_dns" ]]; then
  echo "WireGuard DNS public forwarding preflight failed." >&2
  exit 1
fi

sudo install -d -o root -g wheel -m 0755 /usr/local/libexec
sudo install -o root -g wheel -m 0755 "$daemon_source" "$daemon_destination"
sudo install -o root -g wheel -m 0644 "$plist_source" "$plist_destination"

if sudo launchctl print "system/$service_label" >/dev/null 2>&1; then
  sudo launchctl bootout "system/$service_label"
fi
sudo launchctl bootstrap system "$plist_destination"
sudo launchctl kickstart -k "system/$service_label"

for _ in 1 2 3 4 5; do
  if [[ -f "$resolver_file" ]] && grep -Fq "nameserver $wireguard_dns" "$resolver_file"; then
    echo "Installed the VPN-aware Honey School macOS split DNS service."
    exit 0
  fi
  sleep 1
done

echo "The service was installed, but $resolver_file was not activated." >&2
exit 1
