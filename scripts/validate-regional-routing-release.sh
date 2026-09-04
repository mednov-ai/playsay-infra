#!/bin/sh
# Read-only release gate. Run from the exact candidate infra checkout.
set -eu
platform_dir=${1:?Usage: sh validate-regional-routing-release.sh PLATFORM_DIR PLATFORM_REF BASE_INFRA_REF [--media-rollback]}
platform_ref=${2:?Candidate platform ref required}
base_ref=${3:?Current production infra ref required}
rollback=${4:-}
case "$rollback" in ''|--media-rollback) ;; *) echo 'Unknown routing review option' >&2; exit 1;; esac
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
values=helm-charts/api-gateway/values-prod.yaml
cd "$repo_dir"
candidate_signaling=$(yq -r '.livekit.regionalRelay.signalingMode // "off"' "$values")
candidate_media=$(yq -r '.livekit.regionalRelay.mediaMode // "off"' "$values")
base_values=$(git show "$base_ref:$values")
base_signaling=$(printf '%s\n' "$base_values" | yq -r '.livekit.regionalRelay.signalingMode // "off"')
base_media=$(printf '%s\n' "$base_values" | yq -r '.livekit.regionalRelay.mediaMode // "off"')
case "$candidate_signaling/$candidate_media" in off/off|rf-two-hop/off|rf-two-hop/rf-turn-relay) ;;
  *) echo 'Invalid independent regional routing controls' >&2; exit 1;; esac
if [ "$base_signaling" = rf-two-hop ] && [ "$candidate_signaling" != rf-two-hop ]; then
  echo 'Regional signaling regression requires a separately reviewed change' >&2; exit 1
fi
if [ "$base_media" = rf-turn-relay ] && [ "$candidate_media" != rf-turn-relay ] && [ "$rollback" != --media-rollback ]; then
  echo 'Regional media regression: explicit media rollback review required' >&2; exit 1
fi
if [ "$candidate_signaling" = rf-two-hop ]; then
  if [ "$platform_ref" = WORKTREE ]; then
    source=$(cat "$platform_dir/backend/api-gateway/src/main/resources/application.yaml")
  else
    source=$(git -C "$platform_dir" show "$platform_ref:backend/api-gateway/src/main/resources/application.yaml")
  fi
  printf '%s\n' "$source" | grep -F 'signaling-mode: ${PLAYSAY_REGIONAL_SIGNALING_MODE:' >/dev/null || {
    echo 'Candidate API lacks regional signaling environment binding' >&2; exit 1;
  }
  printf '%s\n' "$source" | grep -F 'media-mode: ${PLAYSAY_REGIONAL_MEDIA_MODE:' >/dev/null || {
    echo 'Candidate API lacks regional media environment binding' >&2; exit 1;
  }
  test_path=backend/api-gateway/src/test/kotlin/com/playsay/gateway/service/RegionalMediaRoutingBindingTest.kt
  if [ "$platform_ref" = WORKTREE ]; then
    test -f "$platform_dir/$test_path"
  else
    git -C "$platform_dir" cat-file -e "$platform_ref:$test_path"
  fi || {
    echo 'Candidate lacks executable regional binding regression tests' >&2; exit 1;
  }
fi
echo 'Regional routing source/config preservation gate passed; API behavioral tests and live media acceptance remain mandatory.'
