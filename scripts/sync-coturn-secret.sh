#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="livekit"
RESTART_LIVEKIT=false
SECRET_NAME="${COTURN_SECRET_NAME:-coturn-auth-secret}"
SECRET_FILE="${COTURN_STATIC_AUTH_SECRET_FILE:-/etc/playsay/coturn-auth-secret}"

for argument in "$@"; do
  case "$argument" in
    --restart-livekit)
      RESTART_LIVEKIT=true
      ;;
    --*)
      echo "unknown option: $argument" >&2
      exit 2
      ;;
    *)
      NAMESPACE="$argument"
      ;;
  esac
done

if [[ ! -r "$SECRET_FILE" ]]; then
  echo "coturn shared secret file is missing: $SECRET_FILE" >&2
  exit 1
fi

COTURN_SECRET="$(tr -d '\r\n' < "$SECRET_FILE")"
if [[ ! "$COTURN_SECRET" =~ ^[[:xdigit:]]{64}$ ]]; then
  echo "coturn shared secret must be exactly 64 hexadecimal characters" >&2
  exit 1
fi

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"; unset COTURN_SECRET CURRENT_SECRET_DATA DESIRED_SECRET_DATA' EXIT
SECRET_VALUE_FILE="$TEMP_DIR/static-auth-secret"
printf '%s' "$COTURN_SECRET" > "$SECRET_VALUE_FILE"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
CURRENT_SECRET_DATA="$(kubectl -n "$NAMESPACE" get secret "$SECRET_NAME" -o 'go-template={{index .data "static-auth-secret"}}' 2>/dev/null || true)"
DESIRED_SECRET_DATA="$(base64 < "$SECRET_VALUE_FILE" | tr -d '\r\n')"
SECRET_CHANGED=false
if [[ "$CURRENT_SECRET_DATA" != "$DESIRED_SECRET_DATA" ]]; then
  SECRET_CHANGED=true
fi
kubectl -n "$NAMESPACE" create secret generic "$SECRET_NAME" \
  --from-file=static-auth-secret="$SECRET_VALUE_FILE" \
  --dry-run=client -o yaml | kubectl apply -f -

if [[ "$SECRET_CHANGED" == true && "$RESTART_LIVEKIT" == true ]] && \
  kubectl -n "$NAMESPACE" get deployment livekit >/dev/null 2>&1; then
  kubectl -n "$NAMESPACE" rollout restart deployment/livekit
  kubectl -n "$NAMESPACE" rollout status deployment/livekit --timeout=180s
fi
