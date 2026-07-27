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

require_text "$render_dir/collaboration.yaml" 'value: "1048576"'
require_text "$render_dir/collaboration.yaml" 'value: "4194304"'
require_text "$render_dir/collaboration.yaml" 'value: "--max-old-space-size=512"'
require_text "$render_dir/collaboration.yaml" "memory: 768Mi"

require_text "$render_dir/monitoring.yaml" "playsay-collaboration-service"
require_text "$render_dir/monitoring.yaml" "PlaySayLiveKitCpuHigh"
require_text "$render_dir/monitoring.yaml" "PlaySayUdpBufferErrors"
require_text "$render_dir/monitoring.yaml" "PlaySayCollaborationBackpressure"
require_text "$render_dir/monitoring.yaml" "-retentionPeriod=7d"

require_text "$repo_root/ansible/group_vars/ax41_hosts.yaml" '"49152:49999"'
require_text "$repo_root/ansible/group_vars/ax41_hosts.yaml" '"50000:50511"'
require_text "$repo_root/ansible/group_vars/ax41_hosts.yaml" 'realtime_conntrack_max: 524288'
require_text "$repo_root/ansible/group_vars/ax41_hosts.yaml" 'realtime_reserved_ports: "3478,7881,49152-50511"'
require_text "$repo_root/ansible/group_vars/ax41_guests.yaml" "coturn_min_port: 49152"
require_text "$repo_root/ansible/group_vars/ax41_guests.yaml" "coturn_max_port: 49999"

require_text "$repo_root/helm-charts/api-gateway/values-prod.yaml" "-Xmx768m"
require_text "$repo_root/helm-charts/ai-tutor-service/values-prod.yaml" "-Xmx384m"
require_text "$repo_root/helm-charts/keyboard-service/values-prod.yaml" "-Xmx512m"
require_text "$repo_root/helm-charts/media-service/values-prod.yaml" "-Xmx512m"
require_text "$repo_root/helm-charts/registration-service/values-prod.yaml" "-Xmx256m"
require_text "$repo_root/helm-charts/vocabulary-service/values-prod.yaml" "-Xmx256m"
require_text "$repo_root/helm-charts/email-service/values-prod.yaml" "-Xmx192m"
require_text "$repo_root/helm-charts/payment-service/values-prod.yaml" "-Xmx192m"
require_text "$repo_root/helm-charts/keycloak/values-prod.yaml" "-Xmx768m"

echo "100-lesson capacity contract is internally consistent."
