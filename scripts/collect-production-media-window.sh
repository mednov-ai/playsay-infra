#!/bin/sh
set -eu

usage() {
  echo 'Usage: scripts/collect-production-media-window.sh --base-url URL --start EPOCH --end EPOCH | --self-test' >&2
  exit 2
}

parse_aggregate() {
  jq -er '
    if .status != "success" then error("query failed")
    elif (.data.result | length) == 0 then error("aggregate source unavailable")
    elif (.data.result | length) != 1 then error("query was not aggregate")
    else .data.result[0].value[1]
    end
  '
}

self_test() {
  value=$(printf '%s' '{"status":"success","data":{"result":[{"value":[1,"2"]}]}}' | parse_aggregate)
  [ "$value" = "2" ] || { echo 'Single aggregate fixture was not parsed.' >&2; exit 1; }
  if printf '%s' '{"status":"success","data":{"result":[]}}' | parse_aggregate >/dev/null 2>&1; then
    echo 'Empty aggregate fixture must fail closed.' >&2
    exit 1
  fi
  if printf '%s' '{"status":"success","data":{"result":[{"value":[1,"1"]},{"value":[1,"2"]}]}}' | parse_aggregate >/dev/null 2>&1; then
    echo 'Multi-series fixture must fail closed.' >&2
    exit 1
  fi
  echo 'Production metric aggregate parser fixtures passed.'
}

if [ "${1:-}" = "--self-test" ]; then [ "$#" -eq 1 ] || usage; self_test; exit 0; fi

base_url=""
start_epoch=""
end_epoch=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --base-url) [ "$#" -ge 2 ] || usage; base_url="$2"; shift 2 ;;
    --start) [ "$#" -ge 2 ] || usage; start_epoch="$2"; shift 2 ;;
    --end) [ "$#" -ge 2 ] || usage; end_epoch="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[ -n "$base_url" ] && [ -n "$start_epoch" ] && [ -n "$end_epoch" ] || usage
case "$start_epoch:$end_epoch" in *[!0-9:]*|:*|*::*|*:) usage ;; esac
[ "$end_epoch" -gt "$start_epoch" ] || usage
window_seconds=$((end_epoch - start_epoch))
[ "$window_seconds" -le 21600 ] || { echo 'Window must not exceed six hours.' >&2; exit 2; }
range="${window_seconds}s"
query_url="${base_url%/}/api/v1/query"

query_value() {
  metric_name="$1"
  expression="$2"
  response="$(curl --fail --silent --show-error --get \
    --data-urlencode "query=$expression" \
    --data-urlencode "time=$end_epoch" \
    "$query_url")"
  printf '%s' "$response" | parse_aggregate | awk -v name="$metric_name" '{ print name "," $0 }'
}

printf 'metric,value\n'
idle_zero='((sum(livekit_participant_total) == 0) * 0)'
query_value direct_school_signaling_selections "sum(increase(playsay_classroom_signaling_route_selections_total{route=\"direct-school\"}[$range])) or $idle_zero"
query_value rf_two_hop_signaling_selections "sum(increase(playsay_classroom_signaling_route_selections_total{route=\"rf-two-hop\"}[$range])) or $idle_zero"
query_value baseline_media_policy_selections "sum(increase(playsay_classroom_media_policy_selections_total{policy=\"baseline\"}[$range])) or $idle_zero"
query_value rf_turn_media_policy_selections "sum(increase(playsay_classroom_media_policy_selections_total{policy=\"rf-turn-relay\"}[$range])) or $idle_zero"
query_value signal_connected_joins "sum(increase(livekit_participant_join_total{state=\"signal_connected\"}[$range]))"
query_value rtc_connected_joins "sum(increase(livekit_participant_join_total{state=\"rtc_connected\"}[$range]))"
query_value participants_min "min_over_time((sum(livekit_participant_total))[$range:15s])"
query_value participants_max "max_over_time((sum(livekit_participant_total))[$range:15s])"
query_value rtt_p95_ms "histogram_quantile(0.95, sum(increase(livekit_rtt_ms_bucket[$range])) by (le)) or $idle_zero"
query_value jitter_p95_ms "(histogram_quantile(0.95, sum(increase(livekit_jitter_us_bucket[$range])) by (le)) / 1000) or $idle_zero"
query_value packet_loss_p95_percent "histogram_quantile(0.95, sum(increase(livekit_packet_loss_percent_bucket[$range])) by (le)) or $idle_zero"
query_value packet_loss_increase "sum(increase(livekit_packet_loss_total[$range]))"
query_value nack_increase "sum(increase(livekit_nack_total[$range]))"
query_value pod_restart_increase "sum(increase(kube_pod_container_status_restarts_total{namespace=~\"playsay-prod|livekit|keycloak|playsay-data|monitoring\"}[$range]))"
query_value udp_receive_error_increase "sum(increase(node_netstat_Udp_RcvbufErrors[$range]))"
query_value udp_send_error_increase "sum(increase(node_netstat_Udp_SndbufErrors[$range]))"
query_value core_targets_min_up "min(min_over_time(up{job=~\"livekit|playsay-api-gateway|playsay-collaboration-service\"}[$range]))"
query_value rf_endpoints_min_up "min(min_over_time(probe_success{instance=~\"https://(online|key)[.]honeyschool[.]ru/\"}[$range]))"
query_value collaboration_connections_min "min_over_time((sum(playsay_collaboration_active_connections))[$range:15s])"
query_value collaboration_connections_max "max_over_time((sum(playsay_collaboration_active_connections))[$range:15s])"
query_value direct_school_collaboration_selections "sum(increase(playsay_classroom_collaboration_route_selections_total{route=\"direct-school\"}[$range])) or $idle_zero"
query_value rf_two_hop_collaboration_selections "sum(increase(playsay_classroom_collaboration_route_selections_total{route=\"rf-two-hop\"}[$range])) or $idle_zero"
query_value yjs_connections_min "min_over_time((sum(playsay_collaboration_channel_active_connections{channel=\"yjs\"}))[$range:15s])"
query_value yjs_connections_max "max_over_time((sum(playsay_collaboration_channel_active_connections{channel=\"yjs\"}))[$range:15s])"
query_value yjs_connection_open_increase "sum(increase(playsay_collaboration_connection_opens_total{channel=\"yjs\"}[$range]))"
query_value yjs_connection_close_increase "sum(increase(playsay_collaboration_connection_closes_total{channel=\"yjs\"}[$range]))"
query_value yjs_heartbeat_termination_increase "sum(increase(playsay_collaboration_heartbeat_terminations_total{channel=\"yjs\"}[$range]))"
query_value collaboration_buffered_bytes_max "max_over_time((sum(playsay_collaboration_websocket_buffered_bytes))[$range:15s])"
query_value collaboration_snapshot_retry_increase "sum(increase(playsay_collaboration_snapshot_flush_duration_seconds_count{outcome=\"retry\"}[$range]))"
query_value collaboration_forced_close_increase "sum(increase(playsay_collaboration_backpressure_forced_closes_total[$range]))"
printf 'chat_websocket_reconnects,not_available\n'
