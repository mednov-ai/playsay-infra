#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
chart="$repo_root/helm-charts/collaboration-service"
render_dir="$(mktemp -d)"
trap 'rm -rf "$render_dir"' EXIT

for environment in dev prod; do
  helm template collaboration-service "$chart" -f "$chart/values-${environment}.yaml" >"$render_dir/${environment}.yaml"
  grep -A1 'name: EXTERNAL_ACTIVITY_REALTIME_ENABLED' "$render_dir/${environment}.yaml" | grep -q 'value: "true"'
  grep -A1 'name: GAME_REALTIME_MODE' "$render_dir/${environment}.yaml" >/dev/null
done

if helm template collaboration-service "$chart" -f "$chart/values-prod.yaml" \
  --set collaboration.externalActivityRealtime.enabled=false >"$render_dir/invalid.yaml" 2>"$render_dir/invalid.err"; then
  echo "production render unexpectedly accepted unavailable external activity realtime" >&2
  exit 1
fi
grep -q 'external activity realtime is required' "$render_dir/invalid.err"

echo "external activity realtime Helm contract passed"
