#!/usr/bin/env bash
set -euo pipefail

SECRET_NAME="${COLLABORATION_SECRET_NAME:-playsay-collaboration}"
SOURCE_NAMESPACE="${COLLABORATION_SOURCE_NAMESPACE:-playsay-dev}"
TARGET_NAMESPACES="${COLLABORATION_SECRET_NAMESPACES:-playsay-dev}"

require() {
  command -v "$1" >/dev/null || { echo "$1 is required" >&2; exit 1; }
}

usage() {
  cat <<USAGE
Usage:
  COLLABORATION_SECRET_NAMESPACES="playsay-dev" $0

Creates or syncs the collaboration JWT signing secret and service snapshot token.
Secret values are never printed. If the source namespace secret already exists, its values
are reused. Otherwise new dev values are generated.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require kubectl
require base64
require openssl

kubectl create namespace "$SOURCE_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

if kubectl -n "$SOURCE_NAMESPACE" get secret "$SECRET_NAME" >/dev/null 2>&1; then
  token_secret="$(kubectl -n "$SOURCE_NAMESPACE" get secret "$SECRET_NAME" -o jsonpath='{.data.token-secret}' | base64 -d)"
  service_token="$(kubectl -n "$SOURCE_NAMESPACE" get secret "$SECRET_NAME" -o jsonpath='{.data.service-token}' | base64 -d)"
else
  token_secret="${PLAYSAY_COLLABORATION_TOKEN_SECRET:-$(openssl rand -hex 32)}"
  service_token="${PLAYSAY_COLLABORATION_SERVICE_TOKEN:-$(openssl rand -hex 32)}"
fi

for namespace in $TARGET_NAMESPACES; do
  kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl -n "$namespace" create secret generic "$SECRET_NAME" \
    --from-literal=token-secret="$token_secret" \
    --from-literal=service-token="$service_token" \
    --dry-run=client -o yaml \
    | kubectl apply -f - >/dev/null
  kubectl -n "$namespace" label secret "$SECRET_NAME" \
    app.kubernetes.io/name=playsay-collaboration \
    app.kubernetes.io/managed-by=playsay-infra \
    --overwrite >/dev/null
  echo "Synced $SECRET_NAME in namespace $namespace"
done
