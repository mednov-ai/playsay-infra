#!/bin/sh
set -eu

trusted_origin='https://online.honeyschool.ru'
trusted_signaling_url='wss://online.honeyschool.ru/livekit'
trusted_turn_host='turn.honeyschool.ru'

usage() {
  echo 'Usage: scripts/verify-authorized-rf-turn-route.sh --token-url URL --bearer-token-file PATH --target USER@HOST --identity PATH | --self-test' >&2
  exit 2
}

validate_response() {
  response="$1"
  now_epoch="$2"
  printf '%s' "$response" | jq -e --arg signaling "$trusted_signaling_url" --argjson now "$now_epoch" '
    .serverUrl == $signaling and
    .mediaRouting.policy == "REGIONAL_RELAY" and
    .mediaRouting.revision == "selectel-rf-v1" and
    .mediaRouting.iceTransportPolicy == "relay" and
    (.mediaRouting.expiresAt | fromdateiso8601) > $now and
    (.mediaRouting.expiresAt | fromdateiso8601) <= ($now + 900) and
    (.mediaRouting.iceServers | length) == 1 and
    (.mediaRouting.iceServers[0].urls | sort) == ([
      "turn:turn.honeyschool.ru:3478?transport=tcp",
      "turn:turn.honeyschool.ru:3478?transport=udp",
      "turns:turn.honeyschool.ru:5349?transport=tcp"
    ] | sort) and
    (.mediaRouting.iceServers[0].username | type == "string" and length > 1) and
    (.mediaRouting.iceServers[0].credential | type == "string" and length > 1)
  ' >/dev/null
}

if [ "${1:-}" = '--self-test' ] && [ "$#" -eq 1 ]; then
  fixture='{"serverUrl":"wss://online.honeyschool.ru/livekit","mediaRouting":{"policy":"REGIONAL_RELAY","revision":"selectel-rf-v1","iceTransportPolicy":"relay","iceServers":[{"urls":["turn:turn.honeyschool.ru:3478?transport=udp","turn:turn.honeyschool.ru:3478?transport=tcp","turns:turn.honeyschool.ru:5349?transport=tcp"],"username":"future:test","credential":"redacted-fixture"}],"expiresAt":"2030-01-01T00:05:00Z"}}'
  validate_response "$fixture" 1893456000
  echo 'Authorized RF TURN response-shape self-test passed.'
  exit 0
fi

token_url=''
bearer_token_file=''
target=''
identity_path=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --token-url) [ "$#" -ge 2 ] || usage; token_url="$2"; shift 2 ;;
    --bearer-token-file) [ "$#" -ge 2 ] || usage; bearer_token_file="$2"; shift 2 ;;
    --target) [ "$#" -ge 2 ] || usage; target="$2"; shift 2 ;;
    --identity) [ "$#" -ge 2 ] || usage; identity_path="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[ -n "$token_url" ] && [ -n "$bearer_token_file" ] && [ -n "$target" ] && [ -n "$identity_path" ] || usage
[ -f "$bearer_token_file" ] && [ -f "$identity_path" ] || usage
case "$token_url" in
  https://online.honeyschool.ru/api/schedule/lessons/*/room-token) ;;
  *) echo 'Token URL must use the exact trusted RF origin and room-token path.' >&2; exit 1 ;;
esac

token_mode="$(stat -f '%Lp' "$bearer_token_file" 2>/dev/null || stat -c '%a' "$bearer_token_file")"
[ "$token_mode" = '600' ] || { echo 'Bearer token file must have mode 0600.' >&2; exit 1; }

bearer_token="$(tr -d '\r\n' < "$bearer_token_file")"
[ -n "$bearer_token" ] || { echo 'Bearer token file is empty.' >&2; exit 1; }
response="$(printf 'header = "Authorization: Bearer %s"\nheader = "Origin: %s"\nheader = "Accept: application/json"\n' \
  "$bearer_token" "$trusted_origin" | curl --fail --silent --show-error \
  --request POST \
  --config - \
  "$token_url")"
unset bearer_token

now_epoch="$(date -u '+%s')"
validate_response "$response" "$now_epoch" || {
  echo 'Authorized room-token response did not contain the required RF signaling and media policy.' >&2
  exit 1
}
echo 'PASS authorized room-token routing shape'

printf '%s' "$response" | jq -c '{
  username: .mediaRouting.iceServers[0].username,
  credential: .mediaRouting.iceServers[0].credential
}' | ssh -i "$identity_path" -o IdentitiesOnly=yes -o BatchMode=yes "$target" \
  /usr/bin/python3 -c '
import json
import os
import subprocess
import sys

payload = json.load(sys.stdin)
username = payload.get("username", "")
credential = payload.get("credential", "")
if not username or not credential:
    raise SystemExit("Authorized TURN credential input is invalid")

base = ["/usr/bin/turnutils_uclient", "-u", username, "-w", credential, "-n", "3", "-y", "-c"]
probes = [
    ("authorized TURN/UDP allocation and data", base + ["-p", "3478", "turn.honeyschool.ru"]),
    ("authorized TURN/TCP allocation and data", base + ["-t", "-p", "3478", "turn.honeyschool.ru"]),
    ("authorized TURN/TLS allocation and data", base + ["-t", "-S", "-p", "5349", "turn.honeyschool.ru"]),
]
environment = {**os.environ, "LC_ALL": "C"}
for label, command in probes:
    result = subprocess.run(
        command,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        env=environment,
        timeout=30,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(f"{label} failed")
    print(f"PASS {label}")
'
unset response
echo 'summary,complete'
