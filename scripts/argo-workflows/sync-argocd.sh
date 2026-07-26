#!/usr/bin/env bash
set -Eeuo pipefail

: "${TARGET_RELEASE:?TARGET_RELEASE is required}"
: "${ARGOCD_NAMESPACE:=argocd}"
: "${SYNC_TIMEOUT_SECONDS:=1200}"

[[ "${TARGET_RELEASE}" =~ ^release/[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "Invalid ArgoCD target release: ${TARGET_RELEASE}" >&2
  exit 2
}

sync_application() {
  local application="$1"
  local revision="$2"
  local deadline phase sync health
  kubectl -n "${ARGOCD_NAMESPACE}" patch application "${application}" --type merge -p "$(
    jq -cn \
      --arg revision "${revision}" \
      '{
        operation: {
          initiatedBy: {username: "argo-workflows"},
          sync: {
            revision: $revision,
            prune: false,
            syncOptions: ["CreateNamespace=true"]
          }
        }
      }'
  )" >/dev/null

  deadline="$((SECONDS + SYNC_TIMEOUT_SECONDS))"
  while (( SECONDS < deadline )); do
    phase="$(
      kubectl -n "${ARGOCD_NAMESPACE}" get application "${application}" \
        -o jsonpath='{.status.operationState.phase}' 2>/dev/null || true
    )"
    sync="$(
      kubectl -n "${ARGOCD_NAMESPACE}" get application "${application}" \
        -o jsonpath='{.status.sync.status}' 2>/dev/null || true
    )"
    health="$(
      kubectl -n "${ARGOCD_NAMESPACE}" get application "${application}" \
        -o jsonpath='{.status.health.status}' 2>/dev/null || true
    )"
    if [[ "${phase}" == "Failed" || "${phase}" == "Error" ]]; then
      echo "ArgoCD sync failed for ${application}: ${phase}." >&2
      return 1
    fi
    if [[ "${phase}" == "Succeeded" && "${sync}" == "Synced" && "${health}" == "Healthy" ]]; then
      echo "${application}: Synced/Healthy"
      return 0
    fi
    sleep 5
  done
  echo "Timed out waiting for ${application} to become Synced/Healthy." >&2
  return 1
}

kubectl -n "${ARGOCD_NAMESPACE}" patch application playsay-prod-root --type merge -p "$(
  jq -cn --arg revision "${TARGET_RELEASE}" \
    '{spec:{source:{targetRevision:$revision}}}'
)" >/dev/null
kubectl -n "${ARGOCD_NAMESPACE}" annotate application playsay-prod-root \
  argocd.argoproj.io/refresh=hard --overwrite >/dev/null
sync_application playsay-prod-root "${TARGET_RELEASE}"

children=(
  ai-tutor-service
  api-gateway
  app-postgres
  cloudnative-pg
  collaboration-service
  keyboard-app
  keyboard-service
  keycloak
  livekit
  media-service
  minio
  registration-service
  vocabulary-service
  web-app
)
deadline="$((SECONDS + SYNC_TIMEOUT_SECONDS))"
for application in "${children[@]}"; do
  while (( SECONDS < deadline )); do
    revision="$(
      kubectl -n "${ARGOCD_NAMESPACE}" get application "${application}" \
        -o jsonpath='{.spec.source.targetRevision}' 2>/dev/null || true
    )"
    [[ "${revision}" == "${TARGET_RELEASE}" ]] && break
    sleep 3
  done
  [[ "${revision:-}" == "${TARGET_RELEASE}" ]] || {
    echo "${application} did not receive targetRevision ${TARGET_RELEASE}." >&2
    exit 1
  }
done

for group in \
  "cloudnative-pg app-postgres minio keycloak livekit" \
  "ai-tutor-service collaboration-service keyboard-service media-service registration-service vocabulary-service" \
  "api-gateway" \
  "web-app keyboard-app"
do
  pids=()
  for application in ${group}; do
    sync_application "${application}" "${TARGET_RELEASE}" &
    pids+=("$!")
  done
  group_status=0
  for pid in "${pids[@]}"; do
    wait "${pid}" || group_status=1
  done
  (( group_status == 0 )) || exit 1
done

echo "Production ArgoCD applications are Synced/Healthy on ${TARGET_RELEASE}."
