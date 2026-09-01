#!/bin/sh
set -eu

usage() {
  echo 'Usage: scripts/collect-production-media-window.sh --base-url URL --start EPOCH --end EPOCH' >&2
  exit 2
}

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
  printf '%s' "$response" | jq -er '
    if .status != "success" then error("query failed")
    elif (.data.result | length) == 0 then error("aggregate source unavailable")
    elif (.data.result | length) != 1 then error("query was not aggregate")
    else .data.result[0].value[1]
    end
  ' | awk -v name="$metric_name" '{ print name "," $0 }'
}

printf 'metric,value\n'
query_value direct_school_route_selections "sum(increase(playsay_classroom_route_selections_total{route=\"direct-school\"}[$range]))"
query_value rf_two_hop_route_selections "sum(increase(playsay_classroom_route_selections_total{route=\"rf-two-hop\"}[$range]))"
query_value signal_connected_joins "sum(increase(livekit_participant_join_total{state=\"signal_connected\"}[$range]))"
query_value rtc_connected_joins "sum(increase(livekit_participant_join_total{state=\"rtc_connected\"}[$range]))"
query_value participants_min "min_over_time((sum(livekit_participant_total))[$range:15s])"
query_value participants_max "max_over_time((sum(livekit_participant_total))[$range:15s])"
query_value rtt_p95_ms "histogram_quantile(0.95, sum(increase(livekit_rtt_ms_bucket[$range])) by (le))"
query_value jitter_p95_ms "histogram_quantile(0.95, sum(increase(livekit_jitter_us_bucket[$range])) by (le)) / 1000"
query_value packet_loss_p95_percent "histogram_quantile(0.95, sum(increase(livekit_packet_loss_percent_bucket[$range])) by (le))"
query_value packet_loss_increase "sum(increase(livekit_packet_loss_total[$range]))"
query_value nack_increase "sum(increase(livekit_nack_total[$range]))"
query_value pod_restart_increase "sum(increase(kube_pod_container_status_restarts_total{namespace=~\"playsay-prod|livekit|keycloak|playsay-data|monitoring\"}[$range]))"
query_value udp_receive_error_increase "sum(increase(node_netstat_Udp_RcvbufErrors[$range]))"
query_value udp_send_error_increase "sum(increase(node_netstat_Udp_SndbufErrors[$range]))"
query_value core_targets_min_up "min(min_over_time(up{job=~\"livekit|playsay-api-gateway|playsay-collaboration-service\"}[$range]))"
query_value rf_endpoints_min_up "min(min_over_time(probe_success{instance=~\"https://(online|key)[.]honeyschool[.]ru/\"}[$range]))"
query_value collaboration_connections_min "min_over_time((sum(playsay_collaboration_active_connections))[$range:15s])"
query_value collaboration_connections_max "max_over_time((sum(playsay_collaboration_active_connections))[$range:15s])"
query_value collaboration_forced_close_increase "sum(increase(playsay_collaboration_backpressure_forced_closes_total[$range]))"
printf 'chat_websocket_reconnects,not_available\n'
