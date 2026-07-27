#!/usr/bin/env bash
set -euo pipefail

SECRET_NAME="${GAME_ADAPTER_SECRET_NAME:-playsay-game-adapter}"
SOURCE_NAMESPACE="${GAME_ADAPTER_SOURCE_NAMESPACE:-playsay-dev}"
TARGET_NAMESPACES="${GAME_ADAPTER_SECRET_NAMESPACES:-playsay-dev}"

command -v kubectl >/dev/null || { echo "kubectl is required" >&2; exit 1; }
command -v base64 >/dev/null || { echo "base64 is required" >&2; exit 1; }
command -v openssl >/dev/null || { echo "openssl is required" >&2; exit 1; }

kubectl create namespace "$SOURCE_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

if kubectl -n "$SOURCE_NAMESPACE" get secret "$SECRET_NAME" >/dev/null 2>&1; then
  service_token="$(kubectl -n "$SOURCE_NAMESPACE" get secret "$SECRET_NAME" -o jsonpath='{.data.service-token}' | base64 -d)"
else
  service_token="${PLAYSAY_GAME_ADAPTER_SERVICE_TOKEN:-$(openssl rand -hex 32)}"
fi

for namespace in $TARGET_NAMESPACES; do
  kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl -n "$namespace" create secret generic "$SECRET_NAME" \
    --from-literal=service-token="$service_token" \
    --dry-run=client -o yaml \
    | kubectl apply -f - >/dev/null
  kubectl -n "$namespace" label secret "$SECRET_NAME" \
    app.kubernetes.io/name=playsay-game-adapter \
    app.kubernetes.io/managed-by=playsay-infra \
    --overwrite >/dev/null
  echo "Synced $SECRET_NAME in namespace $namespace"
done
