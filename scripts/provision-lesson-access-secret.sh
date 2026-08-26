#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${LESSON_ACCESS_NAMESPACE:-playsay-dev}"
SECRET_NAME="${LESSON_ACCESS_SECRET_NAME:-playsay-lesson-access}"

require() {
  command -v "$1" >/dev/null || { echo "$1 is required" >&2; exit 1; }
}

usage() {
  cat <<USAGE
Usage:
  LESSON_ACCESS_NAMESPACE=playsay-dev $0

Creates the environment-local shared lesson-access secret when it is absent.
Existing values are preserved so rerunning this script never rotates active links or
the Keycloak provider channel. Secret values are never printed.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require kubectl
require openssl

if kubectl -n "$NAMESPACE" get secret "$SECRET_NAME" >/dev/null 2>&1; then
  echo "$SECRET_NAME already exists in namespace $NAMESPACE; preserving it"
  exit 0
fi

hmac_secret_base64="$(openssl rand -base64 32 | tr -d '\n')"
provider_token="$(openssl rand -hex 32)"

kubectl -n "$NAMESPACE" create secret generic "$SECRET_NAME" \
  --from-literal=hmac-secret-base64="$hmac_secret_base64" \
  --from-literal=provider-token="$provider_token" >/dev/null

kubectl -n "$NAMESPACE" label secret "$SECRET_NAME" \
  app.kubernetes.io/name=playsay-lesson-access \
  app.kubernetes.io/managed-by=playsay-infra \
  --overwrite >/dev/null

unset hmac_secret_base64 provider_token
echo "Provisioned $SECRET_NAME in namespace $NAMESPACE"
