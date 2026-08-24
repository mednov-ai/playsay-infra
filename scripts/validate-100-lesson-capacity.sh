#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
render_dir="$(mktemp -d)"
trap 'rm -rf "$render_dir"' EXIT

require_text() {
  local file="$1"
  local text="$2"
  if ! grep -Fq -- "$text" "$file"; then
    echo "capacity contract missing in $file: $text" >&2
    exit 1
  fi
}

helm template livekit "$repo_root/helm-charts/livekit" \
  -f "$repo_root/helm-charts/livekit/values-prod.yaml" \
  >"$render_dir/livekit.yaml"
helm template livekit "$repo_root/helm-charts/livekit" \
  -f "$repo_root/helm-charts/livekit/values-dev.yaml" \
  >"$render_dir/livekit-dev.yaml"
helm template collaboration-service "$repo_root/helm-charts/collaboration-service" \
  -f "$repo_root/helm-charts/collaboration-service/values-prod.yaml" \
  >"$render_dir/collaboration.yaml"
helm template monitoring-lite "$repo_root/helm-charts/monitoring-lite" \
  -f "$repo_root/helm-charts/monitoring-lite/values-prod.yaml" \
  >"$render_dir/monitoring.yaml"

require_text "$render_dir/livekit.yaml" "port_range_start: 50000"
require_text "$render_dir/livekit.yaml" "port_range_end: 50511"
require_text "$render_dir/livekit.yaml" "batch_size: 128"
require_text "$render_dir/livekit.yaml" "max_flush_interval: 2ms"
require_text "$render_dir/livekit.yaml" 'cpu: "6"'
require_text "$render_dir/livekit.yaml" "memory: 4Gi"
require_text "$render_dir/livekit-dev.yaml" 'node_ip: "65.109.55.110"'
require_text "$render_dir/livekit-dev.yaml" "tcp_port: 7882"
require_text "$render_dir/livekit-dev.yaml" "port_range_start: 51000"
require_text "$render_dir/livekit-dev.yaml" "port_range_end: 51049"
require_text "$render_dir/livekit-dev.yaml" 'host: "dev.online.honey.school"'
require_text "$render_dir/livekit-dev.yaml" "port: 3479"
require_text "$render_dir/livekit-dev.yaml" 'protocol: "udp"'
require_text "$render_dir/livekit-dev.yaml" 'protocol: "tcp"'

require_text "$render_dir/collaboration.yaml" 'value: "1048576"'
require_text "$render_dir/collaboration.yaml" 'value: "4194304"'
require_text "$render_dir/collaboration.yaml" 'value: "--max-old-space-size=512"'
require_text "$render_dir/collaboration.yaml" "memory: 768Mi"

require_text "$render_dir/monitoring.yaml" "playsay-collaboration-service"
require_text "$render_dir/monitoring.yaml" "PlaySayLiveKitCpuHigh"
require_text "$render_dir/monitoring.yaml" "PlaySayLiveKitJoinFailures"
require_text "$render_dir/monitoring.yaml" "PlaySayUdpBufferErrors"
require_text "$render_dir/monitoring.yaml" "PlaySayCollaborationBackpressure"
require_text "$render_dir/monitoring.yaml" "-retentionPeriod=7d"

require_text "$repo_root/ansible/group_vars/ax41_hosts.yaml" '"49152:49999"'
require_text "$repo_root/ansible/group_vars/ax41_hosts.yaml" '"50000:50511"'
require_text "$repo_root/ansible/group_vars/ax41_hosts.yaml" '"50600:50999"'
require_text "$repo_root/ansible/group_vars/ax41_hosts.yaml" '"51000:51049"'
require_text "$repo_root/ansible/group_vars/ax41_hosts.yaml" 'realtime_conntrack_max: 524288'
require_text "$repo_root/ansible/group_vars/ax41_hosts.yaml" 'realtime_reserved_ports: "3478-3479,7881-7882,49152-51049"'
require_text "$repo_root/ansible/group_vars/ax41_guests.yaml" "coturn_min_port: 49152"
require_text "$repo_root/ansible/group_vars/ax41_guests.yaml" "coturn_max_port: 49999"
require_text "$repo_root/ansible/group_vars/ax41_guests.yaml" "coturn_listening_port: 3479"
require_text "$repo_root/ansible/group_vars/ax41_guests.yaml" "coturn_external_ip: 65.109.55.110/10.60.0.30"
require_text "$repo_root/ansible/group_vars/ax41_guests.yaml" 'reserved_ports: "3479,7882,50600-51049"'
require_text "$repo_root/ansible/playbooks/ax41-guests.yaml" "inventory_hostname in ['playsay-prod', 'playsay-dev']"
require_text "$repo_root/ansible/group_vars/ax41_hosts.yaml" "livekit_upstream: 10.60.0.30:7880"

lesson_rooms=100
participants_per_room=2
livekit_ports_per_participant=2
relay_participant_percent=30
turn_ports_per_relay_participant=2

livekit_port_start="$(awk '/port_range_start:/ { print $2; exit }' "$render_dir/livekit.yaml")"
livekit_port_end="$(awk '/port_range_end:/ { print $2; exit }' "$render_dir/livekit.yaml")"
livekit_port_count=$((livekit_port_end - livekit_port_start + 1))
livekit_port_required=$((lesson_rooms * participants_per_room * livekit_ports_per_participant))
if (( livekit_port_count < livekit_port_required )); then
  echo "LiveKit UDP range has $livekit_port_count ports; $livekit_port_required are required for $lesson_rooms rooms" >&2
  exit 1
fi

coturn_min_port="$(awk '/^coturn_min_port:/ { print $2; exit }' "$repo_root/ansible/group_vars/ax41_guests.yaml")"
coturn_max_port="$(awk '/^coturn_max_port:/ { print $2; exit }' "$repo_root/ansible/group_vars/ax41_guests.yaml")"
coturn_port_count=$((coturn_max_port - coturn_min_port + 1))
coturn_port_required=$((lesson_rooms * participants_per_room * relay_participant_percent * turn_ports_per_relay_participant / 100))
if (( coturn_port_count < coturn_port_required )); then
  echo "coturn relay range has $coturn_port_count ports; $coturn_port_required are required for the forced-relay profile" >&2
  exit 1
fi

if grep -R -Fq "146.103.126.15" \
  "$repo_root/helm-charts/livekit/values-dev.yaml" \
  "$repo_root/ansible/group_vars/ax41_hosts.yaml"; then
  echo "retired dev LiveKit address is still configured" >&2
  exit 1
fi

require_text "$repo_root/helm-charts/api-gateway/values-prod.yaml" "-Xmx768m"
require_text "$repo_root/helm-charts/ai-tutor-service/values-prod.yaml" "-Xmx384m"
require_text "$repo_root/helm-charts/keyboard-service/values-prod.yaml" "-Xmx512m"
require_text "$repo_root/helm-charts/media-service/values-prod.yaml" "-Xmx512m"
require_text "$repo_root/helm-charts/registration-service/values-prod.yaml" "-Xmx256m"
require_text "$repo_root/helm-charts/vocabulary-service/values-prod.yaml" "-Xmx256m"
require_text "$repo_root/helm-charts/email-service/values-prod.yaml" "-Xmx192m"
require_text "$repo_root/helm-charts/payment-service/values-prod.yaml" "-Xmx192m"
require_text "$repo_root/helm-charts/keycloak/values-prod.yaml" "-Xmx768m"

echo "100-lesson capacity contract is internally consistent: LiveKit ${livekit_port_count}/${livekit_port_required}, coturn ${coturn_port_count}/${coturn_port_required} available/required ports."
