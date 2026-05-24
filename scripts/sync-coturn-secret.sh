#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${1:-livekit}"
SECRET_NAME="${COTURN_SECRET_NAME:-coturn-auth-secret}"
SECRET_FILE="${COTURN_STATIC_AUTH_SECRET_FILE:-/etc/playsay/coturn-auth-secret}"

if [[ ! -r "$SECRET_FILE" ]]; then
  echo "coturn shared secret file is missing: $SECRET_FILE" >&2
  exit 1
fi

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NAMESPACE" create secret generic "$SECRET_NAME" \
  --from-file=static-auth-secret="$SECRET_FILE" \
  --dry-run=client -o yaml | kubectl apply -f -
