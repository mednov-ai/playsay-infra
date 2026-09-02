#!/bin/sh
set -eu

usage() {
  echo 'Usage: scripts/validate-rf-classroom-collaboration-route.sh --static | --probe' >&2
  exit 2
}

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
rf_template="$repo_dir/ansible/roles/rf-edge-proxy/templates/playsay-honey-rf-edge.conf.j2"
ax41_template="$repo_dir/ansible/roles/edge-proxy/templates/playsay-honey.conf.j2"
rf_vars="$repo_dir/ansible/group_vars/rf_edges.yaml"

require_literal() {
  grep -F -- "$2" "$1" >/dev/null || {
    echo "Static collaboration-route contract is missing: $2" >&2
    exit 1
  }
}

static_check() {
  require_literal "$rf_vars" 'collaboration_proxy: true'
  require_literal "$rf_template" 'location = /collab/ws {'
  require_literal "$rf_template" 'access_log off;'
  require_literal "$rf_template" 'proxy_pass https://{{ rf_edge_origin_address }};'
  require_literal "$rf_template" 'proxy_ssl_name {{ route.origin_tls_hostname | default(route.origin_hostname) }};'
  require_literal "$rf_template" 'proxy_ssl_verify on;'
  require_literal "$rf_template" 'proxy_ssl_trusted_certificate /etc/ssl/certs/ca-certificates.crt;'
  require_literal "$rf_template" 'proxy_set_header Upgrade $http_upgrade;'
  require_literal "$rf_template" 'proxy_set_header Connection $playsay_rf_connection_upgrade;'
  require_literal "$rf_template" 'proxy_read_timeout 7200s;'
  require_literal "$rf_template" 'proxy_send_timeout 7200s;'
  require_literal "$rf_template" 'proxy_request_buffering off;'
  require_literal "$rf_template" 'proxy_buffering off;'
  require_literal "$ax41_template" 'location = /collab/ws {'
  require_literal "$ax41_template" 'access_log off;'

  collaboration_call_line=$(grep -nF -- "{{ collaboration_location(route, 'https') }}" "$rf_template" | cut -d: -f1)
  generic_location_line=$(grep -nF -- '    location / {' "$rf_template" | tail -1 | cut -d: -f1)
  [ "$collaboration_call_line" -lt "$generic_location_line" ] || {
    echo 'Dedicated collaboration route must precede the generic application route.' >&2
    exit 1
  }
  if awk '
    /macro collaboration_location/ { inside=1 }
    inside && /(\$request|\$request_uri|\$uri|\$args|\$remote_addr|\$proxy_add_x_forwarded_for|access_log \/var)/ { found=1 }
    inside && /endmacro/ { exit }
    END { exit found ? 0 : 1 }
  ' "$rf_template"; then
    echo 'Dedicated collaboration route exposes a forbidden request or identity field.' >&2
    exit 1
  fi
  echo 'Static RF and AX41 collaboration-route privacy contract passed.'
}

probe_check() {
  for url in https://online.honeyschool.ru/collab/ws https://online.honey.school/collab/ws; do
    status=$(curl --http1.1 --silent --show-error --output /dev/null \
      --connect-timeout 10 --max-time 15 \
      --header 'Connection: Upgrade' --header 'Upgrade: websocket' \
      --write-out '%{http_code}' "$url") || {
        echo 'Collaboration WebSocket-path transport or certificate probe failed.' >&2
        exit 1
      }
    case "$status" in 400|401|403|404|426) ;; *) echo "Unexpected collaboration probe status: $status" >&2; exit 1 ;; esac
  done
  echo 'Unauthenticated direct and RF collaboration probes reached the expected authorization boundary.'
}

case "${1:-}" in
  --static) [ "$#" -eq 1 ] || usage; static_check ;;
  --probe) [ "$#" -eq 1 ] || usage; probe_check ;;
  *) usage ;;
esac
