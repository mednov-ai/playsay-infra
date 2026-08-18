#!/usr/bin/env bash
set -euo pipefail

SECRET_NAME="${YOUTUBE_DATA_API_SECRET_NAME:-playsay-youtube-data-api}"
TARGET_NAMESPACE="${TARGET_NAMESPACE:-}"

if [[ "$TARGET_NAMESPACE" != "playsay-dev" && "$TARGET_NAMESPACE" != "playsay-prod" ]]; then
  echo "TARGET_NAMESPACE must be exactly playsay-dev or playsay-prod" >&2
  exit 1
fi

if ! command -v kubectl >/dev/null; then
  echo "kubectl is required" >&2
  exit 1
fi

api_key="${PLAYSAY_YOUTUBE_DATA_API_KEY:-}"
if [[ -z "$api_key" ]]; then
  read -r -s -p "YouTube Data API key for $TARGET_NAMESPACE: " api_key
  echo
fi
if [[ -z "$api_key" ]]; then
  echo "YouTube Data API key must not be empty" >&2
  exit 1
fi

kubectl -n "$TARGET_NAMESPACE" create secret generic "$SECRET_NAME" \
  --from-literal=api-key="$api_key" \
  --dry-run=client -o yaml \
  | kubectl apply -f - >/dev/null
kubectl -n "$TARGET_NAMESPACE" label secret "$SECRET_NAME" \
  app.kubernetes.io/name=playsay-youtube-data-api \
  app.kubernetes.io/managed-by=playsay-infra \
  --overwrite >/dev/null

unset api_key
echo "Synced $SECRET_NAME in namespace $TARGET_NAMESPACE"
