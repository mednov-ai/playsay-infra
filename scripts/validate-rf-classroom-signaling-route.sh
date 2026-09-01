#!/bin/sh
set -eu

usage() {
  echo 'Usage: scripts/validate-rf-classroom-signaling-route.sh --static | --probe' >&2
  exit 2
}

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
rf_template="$repo_dir/ansible/roles/rf-edge-proxy/templates/playsay-honey-rf-edge.conf.j2"
ax41_template="$repo_dir/ansible/roles/edge-proxy/templates/playsay-honey.conf.j2"
rf_vars="$repo_dir/ansible/group_vars/rf_edges.yaml"

require_literal() {
  file=$1
  literal=$2
  grep -F -- "$literal" "$file" >/dev/null || {
    echo "Static signaling-route contract is missing: $literal" >&2
    exit 1
  }
}

static_check() {
  require_literal "$rf_vars" 'livekit_signaling_proxy: true'
  require_literal "$rf_template" 'location = /livekit {'
  require_literal "$rf_template" 'location ^~ /livekit/ {'
  require_literal "$rf_template" 'proxy_ssl_name {{ route.origin_tls_hostname | default(route.origin_hostname) }};'
  require_literal "$rf_template" 'proxy_ssl_protocols TLSv1.2;'
  require_literal "$rf_template" 'proxy_ssl_verify on;'
  require_literal "$rf_template" 'proxy_set_header Upgrade $http_upgrade;'
  require_literal "$rf_template" 'proxy_set_header Connection $playsay_rf_connection_upgrade;'
  require_literal "$rf_template" 'proxy_read_timeout 7200s;'
  require_literal "$rf_template" 'proxy_send_timeout 7200s;'
  require_literal "$rf_template" 'proxy_request_buffering off;'
  require_literal "$rf_template" 'proxy_buffering off;'
  require_literal "$rf_template" "log_format playsay_livekit_signal 'msec=\$msec status=\$status duration=\$request_time upstream_status=\$upstream_status upstream_duration=\$upstream_response_time';"
  require_literal "$rf_template" 'access_log /var/log/nginx/playsay-rf-livekit-signaling.log playsay_livekit_signal;'
  require_literal "$ax41_template" 'location = /livekit {'
  require_literal "$ax41_template" 'location /livekit/ {'
  require_literal "$ax41_template" 'access_log /var/log/nginx/playsay-livekit-signaling.log playsay_livekit_signal;'
  require_literal "$ax41_template" 'proxy_set_header Upgrade $http_upgrade;'
  require_literal "$ax41_template" 'proxy_set_header Connection $playsay_connection_upgrade;'
  require_literal "$ax41_template" 'proxy_buffering off;'
  signaling_call_line=$(grep -nF -- "{{ livekit_signaling_locations(route, 'https') }}" "$rf_template" | cut -d: -f1)
  generic_location_line=$(grep -nF -- '    location / {' "$rf_template" | tail -1 | cut -d: -f1)
  [ "$signaling_call_line" -lt "$generic_location_line" ] || {
    echo 'Dedicated signaling route must precede the generic application route.' >&2
    exit 1
  }
  if awk '
    /macro livekit_signaling_locations/ { inside=1 }
    inside && /sub_filter/ { found=1 }
    inside && /endmacro/ { exit }
    END { exit found ? 0 : 1 }
  ' "$rf_template"; then
    echo 'Dedicated signaling route must not contain response substitution.' >&2
    exit 1
  fi
  echo 'Static RF and AX41 signaling-route contract passed.'
}

probe_one() {
  url=$1
  status=$(curl --http1.1 --silent --show-error --output /dev/null \
    --connect-timeout 10 --max-time 15 \
    --header 'Connection: Upgrade' \
    --header 'Upgrade: websocket' \
    --write-out '%{http_code}' "$url") || {
      echo 'WebSocket-path probe transport or certificate validation failed.' >&2
      exit 1
    }
  case "$status" in
    301|400|401|404|426) ;;
    *) echo "Unexpected unauthenticated WebSocket-path status: $status" >&2; exit 1 ;;
  esac
  printf '%s' "$status"
}

probe_check() {
  rf_status=$(probe_one 'https://online.honeyschool.ru/livekit')
  direct_status=$(probe_one 'https://online.honey.school/livekit')
  printf 'Unauthenticated signaling probes passed: rf_status=%s,direct_status=%s\n' "$rf_status" "$direct_status"
}

case "${1:-}" in
  --static) [ "$#" -eq 1 ] || usage; static_check ;;
  --probe) [ "$#" -eq 1 ] || usage; probe_check ;;
  *) usage ;;
esac
