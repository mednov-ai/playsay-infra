#!/bin/sh
set -eu

usage() { echo 'Usage: scripts/collect-classroom-route-incident.sh --base-url URL --alert-epoch EPOCH --output DIRECTORY' >&2; exit 2; }
base_url=""; alert_epoch=""; output_directory=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --base-url) [ "$#" -ge 2 ] || usage; base_url="$2"; shift 2 ;;
    --alert-epoch) [ "$#" -ge 2 ] || usage; alert_epoch="$2"; shift 2 ;;
    --output) [ "$#" -ge 2 ] || usage; output_directory="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[ -n "$base_url" ] && [ -n "$alert_epoch" ] && [ -n "$output_directory" ] || usage
case "$alert_epoch" in *[!0-9]*|'') usage ;; esac
window_start=$((alert_epoch - 600)); window_end=$((alert_epoch + 300))
[ "$(date +%s)" -ge "$window_end" ] || { echo 'Wait until five minutes after the alert.' >&2; exit 2; }
[ ! -e "$output_directory" ] || { echo 'Output path already exists.' >&2; exit 2; }
mkdir -m 0700 "$output_directory"
query_url="${base_url%/}/api/v1/query"; summary_file="$output_directory/aggregate.csv"
printf 'metric,value\n' >"$summary_file"
query_value() {
  name="$1"; expression="$2"
  response="$(curl --fail --silent --show-error --get --data-urlencode "query=$expression" --data-urlencode "time=$window_end" "$query_url")"
  value="$(printf '%s' "$response" | jq -er 'if .status != "success" then error("query failed") elif (.data.result|length)==0 then "NaN" elif (.data.result|length)!=1 then error("query was not aggregate") else .data.result[0].value[1] end')"
  printf '%s,%s\n' "$name" "$value" >>"$summary_file"
}
query_value rf_to_ax41_tcp_min 'min(min_over_time(playsay_path_probe_success{direction="rf_to_ax41",phase="tcp"}[900s]))'
query_value rf_to_ax41_tls_min 'min(min_over_time(playsay_path_probe_success{direction="rf_to_ax41",phase="tls"}[900s]))'
query_value rf_to_ax41_http_min 'min(min_over_time(playsay_path_probe_success{direction="rf_to_ax41",phase="http"}[900s]))'
query_value ax41_to_rf_min 'min(min_over_time(probe_success{direction="ax41_to_rf"}[900s]))'
query_value ax41_nginx_to_livekit_min 'min(min_over_time(probe_success{direction="ax41_nginx_to_livekit"}[900s]))'
query_value rf_nginx_101 'sum(increase(playsay_nginx_signal_outcomes_total{edge="rf",outcome="101"}[900s]))'
query_value rf_nginx_499 'sum(increase(playsay_nginx_signal_outcomes_total{edge="rf",outcome="499"}[900s]))'
query_value rf_nginx_upstream_connect_failures 'sum(increase(playsay_nginx_signal_outcomes_total{edge="rf",outcome="upstream_connect_failure"}[900s]))'
query_value ax41_nginx_101 'sum(increase(playsay_nginx_signal_outcomes_total{edge="ax41",outcome="101"}[900s]))'
query_value ax41_nginx_502_504 'sum(increase(playsay_nginx_signal_outcomes_total{edge="ax41",outcome=~"502|504"}[900s]))'
query_value livekit_participants_max 'max_over_time((sum(livekit_participant_total))[900s:5s])'
query_value livekit_signal_rtc_join_gap '(sum(increase(livekit_participant_join_total{state="signal_connected"}[900s])) or vector(0)) - (sum(increase(livekit_participant_join_total{state="rtc_connected"}[900s])) or vector(0))'
query_value turn_allocation_failures_max 'max_over_time(playsay_rf_edge_media_relay_allocation_failures[900s])'
query_value turn_auth_failures_max 'max_over_time(playsay_rf_edge_media_relay_auth_failures[900s])'
query_value rf_memory_available_min 'min_over_time(playsay_rf_host_memory_available_bytes[900s])'
query_value rf_conntrack_ratio_max 'max_over_time((playsay_rf_host_conntrack_entries / playsay_rf_host_conntrack_limit)[900s:5s])'
query_value rf_nic_error_drop_increase 'increase(playsay_rf_host_nic_error_drop_total[900s])'
query_value rf_udp_error_increase 'increase(playsay_rf_host_udp_error_total[900s])'
query_value rf_clock_synchronized_min 'min_over_time(playsay_rf_host_clock_synchronized[900s])'
query_value rf_clock_offset_seconds_abs_max 'max_over_time(abs(playsay_rf_host_clock_offset_seconds)[900s:5s])'
query_value ax41_udp_receive_errors 'sum(increase(node_netstat_Udp_RcvbufErrors[900s]))'
query_value ax41_udp_send_errors 'sum(increase(node_netstat_Udp_SndbufErrors[900s]))'

start_iso="$(date -u -d "@$window_start" '+%Y-%m-%dT%H:%M:%SZ')"; end_iso="$(date -u -d "@$window_end" '+%Y-%m-%dT%H:%M:%SZ')"
disconnect_file="$output_directory/livekit-disconnect-reasons.csv"; printf 'reason,count\n' >"$disconnect_file"
livekit_log="$(mktemp)"; trap 'rm -f "$livekit_log"' EXIT HUP INT TERM
kubectl -n livekit logs -l app.kubernetes.io/name=livekit --since-time="$start_iso" --timestamps >"$livekit_log"
for reason in PEER_CONNECTION_DISCONNECTED DTLS_TIMEOUT SIGNAL_SOURCE_CLOSE ROOM_CLOSED; do
  pattern="$(printf '%s' "$reason" | sed 's/_/[ _-]/g')"
  count="$(awk -v end="$end_iso" '$1 <= end' "$livekit_log" | grep -Eci "$pattern" || true)"
  printf '%s,%s\n' "$reason" "$count" >>"$disconnect_file"
done
{
  printf 'window_start_epoch=%s\nalert_epoch=%s\nwindow_end_epoch=%s\n' "$window_start" "$alert_epoch" "$window_end"
  printf '%s\n' 'retention=delete within seven days after incident review' 'privacy=no identities rooms addresses URIs query strings tokens SDP ICE candidates or raw logs retained'
} >"$output_directory/window.txt"
chmod 0600 "$output_directory"/*
