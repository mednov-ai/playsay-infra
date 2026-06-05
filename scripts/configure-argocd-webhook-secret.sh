#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
SECRET_NAME="${ARGOCD_SECRET_NAME:-argocd-secret}"
SECRET_KEY="${ARGOCD_WEBHOOK_SECRET_KEY:-webhook.github.secret}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required." >&2
  exit 1
fi

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

secret_value="${ARGOCD_GITHUB_WEBHOOK_SECRET:-}"
if [[ -z "$secret_value" ]]; then
  secret_value="$(kubectl -n "$NAMESPACE" get secret "$SECRET_NAME" -o "jsonpath={.data.${SECRET_KEY//./\\.}}" 2>/dev/null | base64 -d 2>/dev/null || true)"
fi

if [[ -z "$secret_value" ]]; then
  if ! command -v openssl >/dev/null 2>&1; then
    echo "openssl is required to generate a webhook secret; or set ARGOCD_GITHUB_WEBHOOK_SECRET." >&2
    exit 1
  fi
  secret_value="$(openssl rand -hex 32)"
  created="true"
else
  created="false"
fi

encoded_secret="$(printf '%s' "$secret_value" | base64 | tr -d '\n')"

if kubectl -n "$NAMESPACE" get secret "$SECRET_NAME" >/dev/null 2>&1; then
  kubectl -n "$NAMESPACE" patch secret "$SECRET_NAME" \
    --type merge \
    -p "{\"data\":{\"${SECRET_KEY}\":\"${encoded_secret}\"}}" >/dev/null
else
  kubectl -n "$NAMESPACE" create secret generic "$SECRET_NAME" \
    --from-literal="${SECRET_KEY}=${secret_value}" >/dev/null
fi

if [[ "$created" == "true" ]]; then
  echo "Generated and stored ArgoCD GitHub webhook secret in ${NAMESPACE}/${SECRET_NAME}:${SECRET_KEY}."
else
  echo "ArgoCD GitHub webhook secret is configured in ${NAMESPACE}/${SECRET_NAME}:${SECRET_KEY}."
fi
echo "Use the stored value as the GitHub webhook secret for mednov-ai/playsay-infra -> /argocd/api/webhook. Do not print it in logs."
