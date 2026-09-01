#!/bin/sh
set -eu

usage() {
  echo 'Usage: scripts/collect-rf-media-relay-window.sh --target USER@HOST --identity PATH [--duration SECONDS] [--interval SECONDS] [--local-port PORT] | --self-test' >&2
  exit 2
}

awk_binary="${AWK_BINARY:-/usr/bin/awk}"
[ -x "$awk_binary" ] || { echo 'Configured awk implementation is unavailable.' >&2; exit 1; }
awk() { "$awk_binary" "$@"; }

if [ "${1:-}" = "--self-test" ] && [ "$#" -eq 1 ]; then
  cpu_fixture="$(awk 'BEGIN { delta=25; idle_delta=20; printf "%.3f", (delta > 0 ? 100 * (delta-idle_delta)/delta : 0) }')"
  zero_fixture="$(awk 'BEGIN { delta=0; idle_delta=0; printf "%.3f", (delta > 0 ? 100 * (delta-idle_delta)/delta : 0) }')"
  [ "$cpu_fixture" = "20.000" ] && [ "$zero_fixture" = "0.000" ] || {
    echo 'awk portability fixture failed.' >&2
    exit 1
  }
  echo 'awk portability fixture passed.'
  exit 0
fi

target=""
identity_path=""
duration=3600
interval=15
local_port=39100
while [ "$#" -gt 0 ]; do
  case "$1" in
    --target) [ "$#" -ge 2 ] || usage; target="$2"; shift 2 ;;
    --identity) [ "$#" -ge 2 ] || usage; identity_path="$2"; shift 2 ;;
    --duration) [ "$#" -ge 2 ] || usage; duration="$2"; shift 2 ;;
    --interval) [ "$#" -ge 2 ] || usage; interval="$2"; shift 2 ;;
    --local-port) [ "$#" -ge 2 ] || usage; local_port="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[ -n "$target" ] && [ -f "$identity_path" ] || usage
case "$duration:$interval:$local_port" in *[!0-9:]*|:*|*::*|*:) usage ;; esac
[ "$duration" -ge "$interval" ] && [ "$interval" -ge 5 ] || usage

ssh -i "$identity_path" -o IdentitiesOnly=yes -o ExitOnForwardFailure=yes \
  -N -L "127.0.0.1:${local_port}:127.0.0.1:9100" "$target" &
tunnel_pid=$!
cleanup() { kill "$tunnel_pid" 2>/dev/null || true; wait "$tunnel_pid" 2>/dev/null || true; }
trap cleanup EXIT HUP INT TERM

metrics_url="http://127.0.0.1:${local_port}/metrics"
ready=0
attempt=0
while [ "$attempt" -lt 10 ]; do
  if curl -fsS "$metrics_url" >/dev/null 2>&1; then ready=1; break; fi
  attempt=$((attempt + 1))
  sleep 1
done
[ "$ready" -eq 1 ] || { echo 'Shared RF-edge metrics tunnel did not become ready.' >&2; exit 1; }

metric_sum() {
  metric_name="$1"
  exclude_loopback="${2:-false}"
  awk -v metric_name="$metric_name" -v exclude_loopback="$exclude_loopback" '
    $1 ~ ("^" metric_name "({|$)") {
      if (exclude_loopback == "true" && $1 ~ /device="lo"/) next
      sum += $NF
    }
    END { printf "%.6f", sum + 0 }
  '
}

capture_sample() {
  sample="$(curl -fsS "$metrics_url")"
  for required_metric in \
    playsay_rf_edge_media_relay_active_udp_allocations \
    playsay_rf_edge_media_relay_allocation_failures \
    playsay_rf_edge_media_relay_auth_failures \
    playsay_rf_edge_coturn_up \
    playsay_rf_edge_nginx_up
  do
    printf '%s\n' "$sample" | grep -q "^${required_metric} " || {
      echo "Required aggregate metric is unavailable: ${required_metric}" >&2
      exit 1
    }
  done
  cpu_total="$(printf '%s\n' "$sample" | metric_sum node_cpu_seconds_total)"
  cpu_idle="$(printf '%s\n' "$sample" | awk '$1 ~ /^node_cpu_seconds_total\{/ && $1 ~ /mode="idle"/ { sum += $NF } END { printf "%.6f", sum + 0 }')"
  memory_available="$(printf '%s\n' "$sample" | metric_sum node_memory_MemAvailable_bytes)"
  rx_bytes="$(printf '%s\n' "$sample" | metric_sum node_network_receive_bytes_total true)"
  tx_bytes="$(printf '%s\n' "$sample" | metric_sum node_network_transmit_bytes_total true)"
  swap_total="$(printf '%s\n' "$sample" | metric_sum node_memory_SwapTotal_bytes)"
  swap_free="$(printf '%s\n' "$sample" | metric_sum node_memory_SwapFree_bytes)"
  oom_total="$(printf '%s\n' "$sample" | metric_sum node_vmstat_oom_kill)"
  udp_errors="$(printf '%s\n' "$sample" | awk '$1 ~ /^node_netstat_Udp_(InErrors|RcvbufErrors|SndbufErrors)(\{|$)/ { sum += $NF } END { printf "%.0f", sum + 0 }')"
  coturn_up="$(printf '%s\n' "$sample" | metric_sum playsay_rf_edge_coturn_up)"
  nginx_up="$(printf '%s\n' "$sample" | metric_sum playsay_rf_edge_nginx_up)"
  coturn_restarts="$(printf '%s\n' "$sample" | metric_sum playsay_rf_edge_coturn_restarts_total)"
  nginx_restarts="$(printf '%s\n' "$sample" | metric_sum playsay_rf_edge_nginx_restarts_total)"
  active_allocations="$(printf '%s\n' "$sample" | metric_sum playsay_rf_edge_media_relay_active_udp_allocations)"
  allocation_failures="$(printf '%s\n' "$sample" | metric_sum playsay_rf_edge_media_relay_allocation_failures)"
  auth_failures="$(printf '%s\n' "$sample" | metric_sum playsay_rf_edge_media_relay_auth_failures)"
}

float_max() { awk -v left="$1" -v right="$2" 'BEGIN { print (left > right ? left : right) }'; }
float_min() { awk -v left="$1" -v right="$2" 'BEGIN { print (left < right ? left : right) }'; }

capture_sample
previous_cpu_total="$cpu_total"
previous_cpu_idle="$cpu_idle"
previous_rx_bytes="$rx_bytes"
previous_tx_bytes="$tx_bytes"
initial_oom="$oom_total"
initial_udp_errors="$udp_errors"
max_cpu=0
min_memory_available="$memory_available"
max_rx_mbps=0
max_tx_mbps=0
max_active_allocations="$active_allocations"
max_allocation_failures="$allocation_failures"
max_auth_failures="$auth_failures"
max_swap_used=0
coturn_down_samples=0
nginx_down_samples=0
initial_coturn_restarts="$coturn_restarts"
initial_nginx_restarts="$nginx_restarts"
elapsed=0

printf 'timestamp_utc,cpu_percent,memory_available_bytes,rx_mbps,tx_mbps,active_turn_allocations,allocation_failures,auth_failures,swap_used_bytes,coturn_up,nginx_up,coturn_restarts,nginx_restarts\n'
while [ "$elapsed" -lt "$duration" ]; do
  sleep "$interval"
  elapsed=$((elapsed + interval))
  capture_sample
  cpu_percent="$(awk -v total="$cpu_total" -v idle="$cpu_idle" -v previous_total="$previous_cpu_total" -v previous_idle="$previous_cpu_idle" 'BEGIN { delta=total-previous_total; idle_delta=idle-previous_idle; printf "%.3f", (delta > 0 ? 100 * (delta-idle_delta)/delta : 0) }')"
  rx_mbps="$(awk -v value="$rx_bytes" -v previous="$previous_rx_bytes" -v seconds="$interval" 'BEGIN { printf "%.3f", (value-previous)*8/seconds/1000000 }')"
  tx_mbps="$(awk -v value="$tx_bytes" -v previous="$previous_tx_bytes" -v seconds="$interval" 'BEGIN { printf "%.3f", (value-previous)*8/seconds/1000000 }')"
  swap_used="$(awk -v total="$swap_total" -v free="$swap_free" 'BEGIN { printf "%.0f", total-free }')"
  timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' "$timestamp" "$cpu_percent" "$memory_available" "$rx_mbps" "$tx_mbps" "$active_allocations" "$allocation_failures" "$auth_failures" "$swap_used" "$coturn_up" "$nginx_up" "$coturn_restarts" "$nginx_restarts"

  max_cpu="$(float_max "$max_cpu" "$cpu_percent")"
  min_memory_available="$(float_min "$min_memory_available" "$memory_available")"
  max_rx_mbps="$(float_max "$max_rx_mbps" "$rx_mbps")"
  max_tx_mbps="$(float_max "$max_tx_mbps" "$tx_mbps")"
  max_active_allocations="$(float_max "$max_active_allocations" "$active_allocations")"
  max_allocation_failures="$(float_max "$max_allocation_failures" "$allocation_failures")"
  max_auth_failures="$(float_max "$max_auth_failures" "$auth_failures")"
  max_swap_used="$(float_max "$max_swap_used" "$swap_used")"
  if [ "$coturn_up" != "1.000000" ]; then coturn_down_samples=$((coturn_down_samples + 1)); fi
  if [ "$nginx_up" != "1.000000" ]; then nginx_down_samples=$((nginx_down_samples + 1)); fi
  previous_cpu_total="$cpu_total"
  previous_cpu_idle="$cpu_idle"
  previous_rx_bytes="$rx_bytes"
  previous_tx_bytes="$tx_bytes"
done

oom_delta="$(awk -v final="$oom_total" -v initial="$initial_oom" 'BEGIN { printf "%.0f", final-initial }')"
udp_error_delta="$(awk -v final="$udp_errors" -v initial="$initial_udp_errors" 'BEGIN { printf "%.0f", final-initial }')"
coturn_restart_delta="$(awk -v final="$coturn_restarts" -v initial="$initial_coturn_restarts" 'BEGIN { printf "%.0f", final-initial }')"
nginx_restart_delta="$(awk -v final="$nginx_restarts" -v initial="$initial_nginx_restarts" 'BEGIN { printf "%.0f", final-initial }')"
threshold_pass="$(awk -v cpu="$max_cpu" -v memory="$min_memory_available" -v rx="$max_rx_mbps" -v tx="$max_tx_mbps" -v swap="$max_swap_used" -v oom="$oom_delta" -v udp="$udp_error_delta" -v allocations="$max_allocation_failures" -v coturn_down="$coturn_down_samples" -v nginx_down="$nginx_down_samples" -v coturn_restarts="$coturn_restart_delta" -v nginx_restarts="$nginx_restart_delta" 'BEGIN { print (cpu < 70 && memory >= 536870912 && rx < 30 && tx < 30 && swap == 0 && oom == 0 && udp == 0 && allocations == 0 && coturn_down == 0 && nginx_down == 0 && coturn_restarts == 0 && nginx_restarts == 0) ? "PASS" : "FAIL" }')"
printf 'summary,max_cpu_percent=%s,min_memory_available_bytes=%s,max_rx_mbps=%s,max_tx_mbps=%s,max_active_turn_allocations=%s,max_allocation_failures=%s,max_auth_failures=%s,max_swap_used_bytes=%s,oom_delta=%s,udp_error_delta=%s,coturn_down_samples=%s,nginx_down_samples=%s,coturn_restart_delta=%s,nginx_restart_delta=%s,shared_host_gate=%s\n' \
  "$max_cpu" "$min_memory_available" "$max_rx_mbps" "$max_tx_mbps" "$max_active_allocations" "$max_allocation_failures" "$max_auth_failures" "$max_swap_used" "$oom_delta" "$udp_error_delta" "$coturn_down_samples" "$nginx_down_samples" "$coturn_restart_delta" "$nginx_restart_delta" "$threshold_pass"
