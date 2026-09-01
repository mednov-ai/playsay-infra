#!/bin/sh
set -eu

usage() {
  echo 'Usage: scripts/collect-classroom-signaling-nginx-window.sh --rf-log PATH --ax41-log PATH --start EPOCH --end EPOCH' >&2
  exit 2
}

rf_log=""
ax41_log=""
start_epoch=""
end_epoch=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --rf-log) [ "$#" -ge 2 ] || usage; rf_log="$2"; shift 2 ;;
    --ax41-log) [ "$#" -ge 2 ] || usage; ax41_log="$2"; shift 2 ;;
    --start) [ "$#" -ge 2 ] || usage; start_epoch="$2"; shift 2 ;;
    --end) [ "$#" -ge 2 ] || usage; end_epoch="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[ -f "$rf_log" ] && [ -f "$ax41_log" ] || usage
case "$start_epoch:$end_epoch" in *[!0-9:]*|:*|*::*|*:) usage ;; esac
[ "$end_epoch" -gt "$start_epoch" ] || usage
[ $((end_epoch - start_epoch)) -le 21600 ] || { echo 'Window must not exceed six hours.' >&2; exit 2; }

awk_binary="${AWK_BINARY:-/usr/bin/awk}"
[ -x "$awk_binary" ] || { echo 'Configured awk implementation is unavailable.' >&2; exit 1; }

parse_log() {
  contour=$1
  log_file=$2
  "$awk_binary" -v contour="$contour" -v start="$start_epoch" -v end="$end_epoch" '
    function field_value(position, parts) {
      split($position, parts, "=")
      return parts[2]
    }
    {
      timestamp = field_value(1)
      if (timestamp < start || timestamp > end) next
      status = field_value(2) + 0
      duration = field_value(3) + 0
      upstream_status = field_value(4) + 0
      completed++
      if (status == 101 && upstream_status == 101) {
        establishments++
        closures++
      } else {
        non_upgrade++
      }
      if (duration > max_duration) max_duration = duration
    }
    END {
      if (completed == 0) exit 3
      printf "%s_completed_requests,%d\n", contour, completed
      printf "%s_websocket_establishments,%d\n", contour, establishments + 0
      printf "%s_websocket_closures,%d\n", contour, closures + 0
      printf "%s_non_upgrade_responses,%d\n", contour, non_upgrade + 0
      printf "%s_max_duration_seconds,%.3f\n", contour, max_duration + 0
    }
  ' "$log_file" || {
    echo "No privacy-safe $contour signaling samples found in the exact interval." >&2
    exit 1
  }
}

printf 'metric,value\n'
parse_log rf "$rf_log"
parse_log ax41 "$ax41_log"
printf 'summary,complete\n'
