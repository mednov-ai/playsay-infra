#!/usr/bin/env bash
set -euo pipefail

SECRET_NAME="${LIVEKIT_SECRET_NAME:-livekit-keys}"
SOURCE_NAMESPACE="${LIVEKIT_SOURCE_NAMESPACE:-livekit}"
TARGET_NAMESPACES="${LIVEKIT_SECRET_NAMESPACES:-livekit playsay-dev}"

require() {
  command -v "$1" >/dev/null || { echo "$1 is required" >&2; exit 1; }
}

usage() {
  cat <<USAGE
Usage:
  LIVEKIT_SECRET_NAMESPACES="livekit playsay-dev" $0

Creates or syncs the LiveKit API key/secret Kubernetes secret for LiveKit and api-gateway.
Secret values are never printed. If the source namespace secret already exists, its values
are reused. Otherwise a new dev key pair is generated.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require kubectl
require base64
require openssl

if kubectl -n "$SOURCE_NAMESPACE" get secret "$SECRET_NAME" >/dev/null 2>&1; then
  api_key="$(kubectl -n "$SOURCE_NAMESPACE" get secret "$SECRET_NAME" -o jsonpath='{.data.api-key}' | base64 -d)"
  api_secret="$(kubectl -n "$SOURCE_NAMESPACE" get secret "$SECRET_NAME" -o jsonpath='{.data.api-secret}' | base64 -d)"
else
  api_key="${LIVEKIT_API_KEY:-playsay-dev-$(openssl rand -hex 4)}"
  api_secret="${LIVEKIT_API_SECRET:-$(openssl rand -hex 32)}"
fi

for namespace in $TARGET_NAMESPACES; do
  kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl -n "$namespace" create secret generic "$SECRET_NAME" \
    --from-literal=api-key="$api_key" \
    --from-literal=api-secret="$api_secret" \
    --dry-run=client -o yaml \
    | kubectl apply -f - >/dev/null
  kubectl -n "$namespace" label secret "$SECRET_NAME" \
    app.kubernetes.io/name=livekit-keys \
    app.kubernetes.io/managed-by=playsay-infra \
    --overwrite >/dev/null
  echo "Synced $SECRET_NAME in namespace $namespace"
done
