#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
chart="$repo_dir/helm-charts/api-gateway"
render_dir=$(mktemp -d)
trap 'rm -rf "$render_dir"' EXIT HUP INT TERM

helm template api-gateway "$chart" -f "$chart/values-prod.yaml" >"$render_dir/prod-active.yaml"
helm template api-gateway "$chart" -f "$chart/values-dev.yaml" >"$render_dir/dev-off.yaml"
helm template api-gateway "$chart" -f "$chart/values-prod.yaml" \
  --set collaboration.regionalRouting.mode=off >"$render_dir/prod-rollback.yaml"

require_pair() {
  file=$1
  name=$2
  value=$3
  awk -v name="$name" -v value="$value" '
    $1 == "-" && $2 == "name:" {
      if ($3 == name) { found=1; next }
      if (found) exit
    }
    found && $1 == "value:" {
      gsub(/^"|"$/, "", $2)
      if ($2 == value) matched=1
      exit
    }
    END { exit matched ? 0 : 1 }
  ' "$file" || { echo "Missing rendered environment pair: $name=$value" >&2; exit 1; }
}

require_pair "$render_dir/prod-active.yaml" PLAYSAY_COLLABORATION_REGIONAL_ROUTING_ENVIRONMENT prod
require_pair "$render_dir/prod-active.yaml" PLAYSAY_COLLABORATION_REGIONAL_ROUTING_MODE rf-two-hop
require_pair "$render_dir/prod-active.yaml" PLAYSAY_COLLABORATION_REGIONAL_WEBSOCKET_URL wss://online.honeyschool.ru/collab/ws
require_pair "$render_dir/dev-off.yaml" PLAYSAY_COLLABORATION_REGIONAL_ROUTING_ENVIRONMENT dev
require_pair "$render_dir/dev-off.yaml" PLAYSAY_COLLABORATION_REGIONAL_ROUTING_MODE off
require_pair "$render_dir/prod-rollback.yaml" PLAYSAY_COLLABORATION_REGIONAL_ROUTING_MODE off
require_pair "$render_dir/prod-active.yaml" PLAYSAY_REGIONAL_SIGNALING_MODE rf-two-hop
require_pair "$render_dir/prod-active.yaml" PLAYSAY_REGIONAL_MEDIA_MODE rf-turn-relay

if helm template api-gateway "$chart" -f "$chart/values-dev.yaml" \
  --set collaboration.regionalRouting.mode=rf-two-hop \
  --set collaboration.regionalRouting.websocketUrl=wss://online.honeyschool.ru/collab/ws \
  >"$render_dir/invalid.yaml" 2>/dev/null; then
  echo 'Dev regional collaboration routing must fail closed.' >&2
  exit 1
fi
if grep -E '(token-secret|service-token|shared-secret)[[:space:]]*:' "$render_dir/prod-active.yaml" >/dev/null; then
  echo 'Rendered manifest appears to contain a secret value.' >&2
  exit 1
fi

echo 'Independent collaboration Helm routing contract passed for prod active/rollback and dev off.'
