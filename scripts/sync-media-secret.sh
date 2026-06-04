#!/usr/bin/env bash
set -euo pipefail

SECRET_NAME="${MEDIA_SECRET_NAME:-playsay-media}"
SOURCE_NAMESPACE="${MEDIA_SOURCE_NAMESPACE:-playsay-dev}"
TARGET_NAMESPACES="${MEDIA_SECRET_NAMESPACES:-playsay-dev}"

require() {
  command -v "$1" >/dev/null || { echo "$1 is required" >&2; exit 1; }
}

usage() {
  cat <<USAGE
Usage:
  MEDIA_SECRET_NAMESPACES="playsay-dev" $0

Creates or syncs the internal media-service token used by api-gateway.
Secret values are never printed. If the source namespace secret already exists, its value
is reused. Otherwise a new dev value is generated.
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
  service_token="$(kubectl -n "$SOURCE_NAMESPACE" get secret "$SECRET_NAME" -o jsonpath='{.data.service-token}' | base64 -d)"
else
  service_token="${PLAYSAY_MEDIA_SERVICE_TOKEN:-$(openssl rand -hex 32)}"
fi

for namespace in $TARGET_NAMESPACES; do
  kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl -n "$namespace" create secret generic "$SECRET_NAME" \
    --from-literal=service-token="$service_token" \
    --dry-run=client -o yaml \
    | kubectl apply -f - >/dev/null
  kubectl -n "$namespace" label secret "$SECRET_NAME" \
    app.kubernetes.io/name=playsay-media \
    app.kubernetes.io/managed-by=playsay-infra \
    --overwrite >/dev/null
  echo "Synced $SECRET_NAME in namespace $namespace"
done
