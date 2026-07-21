#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LEGACY_BRANCH="legacy/play-and-say-vps"
OLD_ISSUER="https://ops.play-and-say.ru:18443/keycloak/realms/playsay"

cd "$REPO_ROOT"

app_manifest_count="$(find argocd-apps/dev -type f -name '*.yaml' | wc -l | tr -d ' ')"
if [[ "$app_manifest_count" -ne 18 ]]; then
  echo "Expected 18 legacy ArgoCD manifests, found $app_manifest_count" >&2
  exit 1
fi

while IFS= read -r manifest; do
  if ! grep -Fq "targetRevision: $LEGACY_BRANCH" "$manifest"; then
    echo "ArgoCD manifest is not pinned to $LEGACY_BRANCH: $manifest" >&2
    exit 1
  fi
done < <(find argocd-apps/dev -type f -name '*.yaml' | sort)

job_config_count="$(find jenkins/jobs -type f -name '*.xml' | wc -l | tr -d ' ')"
if [[ "$job_config_count" -ne 13 ]]; then
  echo "Expected 13 legacy Jenkins job configs, found $job_config_count" >&2
  exit 1
fi

while IFS= read -r config; do
  if grep -Fq '<name>BRANCH_NAME</name>' "$config"; then
    echo "Mutable BRANCH_NAME remains in $config" >&2
    exit 1
  fi
  grep -Fq '<name>*/legacy/play-and-say-vps</name>' "$config"
  grep -Fq '<triggers/>' "$config"
done < <(find jenkins/jobs -type f -name '*.xml' | sort)

grep -Fq "issuerUri: $OLD_ISSUER" helm-charts/api-gateway/values-dev.yaml
grep -Fq "$OLD_ISSUER" helm-charts/keyboard-service/values.yaml
grep -Fq 'appBaseUrl: https://online.play-and-say.ru' helm-charts/keycloak/values-dev.yaml

if grep -R -n -F 'honey.school' argocd-apps/dev helm-charts/*/values-dev.yaml scripts/configure-keycloak-dev.sh; then
  echo "Honey runtime reference found in the isolated legacy contour" >&2
  exit 1
fi

echo "Legacy VPS isolation verified: ArgoCD, Jenkins and Keycloak are pinned to the old contour."
