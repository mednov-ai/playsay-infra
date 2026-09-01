#!/bin/sh
set -eu

usage() {
  echo 'Usage: bounded LiveKit logs | scripts/collect-livekit-signaling-window.sh --signaling-contour rf-two-hop|direct-school' >&2
  exit 2
}

contour=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --signaling-contour) [ "$#" -ge 2 ] || usage; contour="$2"; shift 2 ;;
    *) usage ;;
  esac
done
case "$contour" in rf-two-hop|direct-school) ;; *) usage ;; esac

umask 077
input_file=$(mktemp)
cleanup() { rm -f "$input_file"; }
trap cleanup EXIT HUP INT TERM
tee "$input_file" >/dev/null
[ -s "$input_file" ] || { echo 'Bounded LiveKit log source is empty.' >&2; exit 1; }

count() {
  pattern=$1
  grep -Eci -- "$pattern" "$input_file" || true
}

printf 'metric,value\n'
printf 'selected_signaling_contour,%s\n' "$contour"
printf 'participant_start_events,%s\n' "$(count 'start(ing|ed) participant|participant.*start')"
printf 'participant_resume_events,%s\n' "$(count 'resum(e|ing|ed)|resume connection')"
printf 'signal_source_close_events,%s\n' "$(count 'SIGNAL_SOURCE_CLOSE')"
printf 'duplicate_identity_events,%s\n' "$(count 'DUPLICATE_IDENTITY')"
printf 'peer_connection_disconnected_events,%s\n' "$(count 'PEER_CONNECTION_DISCONNECTED')"
printf 'relay_candidate_events,%s\n' "$(count 'relay.*(udp|UDP)|(udp|UDP).*relay')"
printf 'summary,complete\n'
