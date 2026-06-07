#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${MULTICA_NAMESPACE:-multica}"
SECRET_NAME="${MULTICA_SECRET_NAME:-multica-secrets}"
PUBLIC_URL="${MULTICA_PUBLIC_URL:-https://tasks.play-and-say.ru}"
APP_URL="${MULTICA_APP_URL:-$PUBLIC_URL}"
DEFAULT_ALLOWED_EMAILS="${MULTICA_DEFAULT_ALLOWED_EMAILS:-admin@play-and-say.ru}"
PLAYSAY_EMAIL_NAMESPACE="${MULTICA_PLAYSAY_EMAIL_NAMESPACE:-playsay-dev}"
PLAYSAY_EMAIL_SECRET_NAME="${MULTICA_PLAYSAY_EMAIL_SECRET_NAME:-playsay-email}"

require() {
  command -v "$1" >/dev/null || { echo "$1 is required" >&2; exit 1; }
}

usage() {
  cat <<USAGE
Usage:
  MULTICA_ALLOWED_EMAILS="admin@example.com,dev@example.com" \
  MULTICA_SMTP_HOST="smtp.example.com" \
  MULTICA_SMTP_USERNAME="..." \
  MULTICA_SMTP_PASSWORD="..." \
  MULTICA_GITHUB_APP_SLUG="..." \
  MULTICA_GITHUB_WEBHOOK_SECRET="..." \
  $0

Creates or updates the Multica runtime secret in Kubernetes without printing
secret values. Existing generated JWT/PostgreSQL/GitHub webhook values are reused
unless matching environment variables are provided.

If MULTICA_SMTP_* values are not provided and multica-secrets does not already
contain SMTP values, the script copies SMTP fallback values and from-address from
the existing Play&Say email secret:
  ${PLAYSAY_EMAIL_NAMESPACE}/${PLAYSAY_EMAIL_SECRET_NAME}
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require kubectl
require openssl
require base64

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

existing_value() {
  local key="$1"
  kubectl -n "$NAMESPACE" get secret "$SECRET_NAME" \
    -o "jsonpath={.data.${key}}" 2>/dev/null \
    | base64 -d 2>/dev/null \
    | tr -d '\r' || true
}

secret_value() {
  local namespace="$1"
  local secret_name="$2"
  local key="$3"
  local encoded

  encoded="$(
    kubectl -n "$namespace" get secret "$secret_name" \
      -o "jsonpath={.data.${key}}" 2>/dev/null || true
  )"
  if [[ -z "$encoded" ]]; then
    return
  fi

  printf "%s" "$encoded" | base64 -d 2>/dev/null | tr -d '\r' || true
}

playsay_email_value() {
  local key="$1"
  secret_value "$PLAYSAY_EMAIL_NAMESPACE" "$PLAYSAY_EMAIL_SECRET_NAME" "$key"
}

default_if_empty() {
  local value="$1"
  local fallback="$2"

  if [[ -n "$value" ]]; then
    printf "%s" "$value"
  else
    printf "%s" "$fallback"
  fi
}

smtp_tls_from_playsay_email() {
  local starttls
  local normalized
  starttls="$(playsay_email_value smtp-starttls)"
  normalized="$(printf "%s" "$starttls" | tr '[:upper:]' '[:lower:]')"

  case "$normalized" in
    true|1|yes|on)
      printf "starttls"
      ;;
    false|0|no|off)
      printf "none"
      ;;
    *)
      printf "starttls"
      ;;
  esac
}

write_value() {
  local key="$1"
  local value="$2"
  printf "%s" "$value" > "$tmp_dir/$key"
}

value_from_env_or_existing() {
  local env_name="$1"
  local key="$2"
  local fallback="${3:-}"
  local env_value="${!env_name:-}"

  if [[ -n "$env_value" ]]; then
    printf "%s" "$env_value"
    return
  fi

  local existing
  existing="$(existing_value "$key")"
  if [[ -n "$existing" ]]; then
    printf "%s" "$existing"
    return
  fi

  printf "%s" "$fallback"
}

write_value JWT_SECRET "$(value_from_env_or_existing MULTICA_JWT_SECRET JWT_SECRET "$(openssl rand -hex 32)")"
write_value POSTGRES_PASSWORD "$(value_from_env_or_existing MULTICA_POSTGRES_PASSWORD POSTGRES_PASSWORD "$(openssl rand -hex 24)")"

write_value RESEND_API_KEY "$(value_from_env_or_existing MULTICA_RESEND_API_KEY RESEND_API_KEY)"
write_value RESEND_FROM_EMAIL "$(value_from_env_or_existing MULTICA_RESEND_FROM_EMAIL RESEND_FROM_EMAIL "$(default_if_empty "$(playsay_email_value from-address)" "noreply@play-and-say.ru")")"

write_value SMTP_HOST "$(value_from_env_or_existing MULTICA_SMTP_HOST SMTP_HOST "$(playsay_email_value smtp-host)")"
write_value SMTP_PORT "$(value_from_env_or_existing MULTICA_SMTP_PORT SMTP_PORT "$(default_if_empty "$(playsay_email_value smtp-port)" "587")")"
write_value SMTP_USERNAME "$(value_from_env_or_existing MULTICA_SMTP_USERNAME SMTP_USERNAME "$(playsay_email_value smtp-username)")"
write_value SMTP_PASSWORD "$(value_from_env_or_existing MULTICA_SMTP_PASSWORD SMTP_PASSWORD "$(playsay_email_value smtp-password)")"
write_value SMTP_TLS "$(value_from_env_or_existing MULTICA_SMTP_TLS SMTP_TLS "$(smtp_tls_from_playsay_email)")"
write_value SMTP_TLS_INSECURE "$(value_from_env_or_existing MULTICA_SMTP_TLS_INSECURE SMTP_TLS_INSECURE "false")"
write_value SMTP_EHLO_NAME "$(value_from_env_or_existing MULTICA_SMTP_EHLO_NAME SMTP_EHLO_NAME "tasks.play-and-say.ru")"

write_value GOOGLE_CLIENT_SECRET "$(value_from_env_or_existing MULTICA_GOOGLE_CLIENT_SECRET GOOGLE_CLIENT_SECRET)"
write_value CLOUDFRONT_PRIVATE_KEY "$(value_from_env_or_existing MULTICA_CLOUDFRONT_PRIVATE_KEY CLOUDFRONT_PRIVATE_KEY)"
write_value MULTICA_DEV_VERIFICATION_CODE "${MULTICA_DEV_VERIFICATION_CODE:-}"

write_value ALLOW_SIGNUP "$(value_from_env_or_existing MULTICA_ALLOW_SIGNUP ALLOW_SIGNUP "true")"
write_value ALLOWED_EMAILS "$(value_from_env_or_existing MULTICA_ALLOWED_EMAILS ALLOWED_EMAILS "$DEFAULT_ALLOWED_EMAILS")"
write_value ALLOWED_EMAIL_DOMAINS "$(value_from_env_or_existing MULTICA_ALLOWED_EMAIL_DOMAINS ALLOWED_EMAIL_DOMAINS)"
write_value DISABLE_WORKSPACE_CREATION "$(value_from_env_or_existing MULTICA_DISABLE_WORKSPACE_CREATION DISABLE_WORKSPACE_CREATION "false")"

write_value FRONTEND_ORIGIN "$PUBLIC_URL"
write_value CORS_ALLOWED_ORIGINS "$PUBLIC_URL"
write_value MULTICA_APP_URL "$APP_URL"
write_value MULTICA_PUBLIC_URL "$PUBLIC_URL"
write_value ALLOWED_ORIGINS "$PUBLIC_URL"
write_value ANALYTICS_DISABLED "$(value_from_env_or_existing MULTICA_ANALYTICS_DISABLED ANALYTICS_DISABLED "true")"
write_value DATABASE_MAX_CONNS "$(value_from_env_or_existing MULTICA_DATABASE_MAX_CONNS DATABASE_MAX_CONNS "10")"
write_value DATABASE_MIN_CONNS "$(value_from_env_or_existing MULTICA_DATABASE_MIN_CONNS DATABASE_MIN_CONNS "2")"
write_value RATE_LIMIT_TRUSTED_PROXIES "$(value_from_env_or_existing MULTICA_RATE_LIMIT_TRUSTED_PROXIES RATE_LIMIT_TRUSTED_PROXIES "127.0.0.1/32,::1/128,10.42.0.0/16,10.43.0.0/16")"
write_value MULTICA_TRUSTED_PROXIES "$(value_from_env_or_existing MULTICA_TRUSTED_PROXIES MULTICA_TRUSTED_PROXIES "127.0.0.1/32,::1/128,10.42.0.0/16,10.43.0.0/16")"

write_value GITHUB_APP_SLUG "$(value_from_env_or_existing MULTICA_GITHUB_APP_SLUG GITHUB_APP_SLUG)"
write_value GITHUB_WEBHOOK_SECRET "$(value_from_env_or_existing MULTICA_GITHUB_WEBHOOK_SECRET GITHUB_WEBHOOK_SECRET "$(openssl rand -hex 32)")"
write_value GITHUB_APP_ID "$(value_from_env_or_existing MULTICA_GITHUB_APP_ID GITHUB_APP_ID)"
write_value GITHUB_APP_PRIVATE_KEY "$(value_from_env_or_existing MULTICA_GITHUB_APP_PRIVATE_KEY GITHUB_APP_PRIVATE_KEY)"

kubectl -n "$NAMESPACE" create secret generic "$SECRET_NAME" \
  --from-file=JWT_SECRET="$tmp_dir/JWT_SECRET" \
  --from-file=POSTGRES_PASSWORD="$tmp_dir/POSTGRES_PASSWORD" \
  --from-file=RESEND_API_KEY="$tmp_dir/RESEND_API_KEY" \
  --from-file=RESEND_FROM_EMAIL="$tmp_dir/RESEND_FROM_EMAIL" \
  --from-file=SMTP_HOST="$tmp_dir/SMTP_HOST" \
  --from-file=SMTP_PORT="$tmp_dir/SMTP_PORT" \
  --from-file=SMTP_USERNAME="$tmp_dir/SMTP_USERNAME" \
  --from-file=SMTP_PASSWORD="$tmp_dir/SMTP_PASSWORD" \
  --from-file=SMTP_TLS="$tmp_dir/SMTP_TLS" \
  --from-file=SMTP_TLS_INSECURE="$tmp_dir/SMTP_TLS_INSECURE" \
  --from-file=SMTP_EHLO_NAME="$tmp_dir/SMTP_EHLO_NAME" \
  --from-file=GOOGLE_CLIENT_SECRET="$tmp_dir/GOOGLE_CLIENT_SECRET" \
  --from-file=CLOUDFRONT_PRIVATE_KEY="$tmp_dir/CLOUDFRONT_PRIVATE_KEY" \
  --from-file=MULTICA_DEV_VERIFICATION_CODE="$tmp_dir/MULTICA_DEV_VERIFICATION_CODE" \
  --from-file=ALLOW_SIGNUP="$tmp_dir/ALLOW_SIGNUP" \
  --from-file=ALLOWED_EMAILS="$tmp_dir/ALLOWED_EMAILS" \
  --from-file=ALLOWED_EMAIL_DOMAINS="$tmp_dir/ALLOWED_EMAIL_DOMAINS" \
  --from-file=DISABLE_WORKSPACE_CREATION="$tmp_dir/DISABLE_WORKSPACE_CREATION" \
  --from-file=FRONTEND_ORIGIN="$tmp_dir/FRONTEND_ORIGIN" \
  --from-file=CORS_ALLOWED_ORIGINS="$tmp_dir/CORS_ALLOWED_ORIGINS" \
  --from-file=MULTICA_APP_URL="$tmp_dir/MULTICA_APP_URL" \
  --from-file=MULTICA_PUBLIC_URL="$tmp_dir/MULTICA_PUBLIC_URL" \
  --from-file=ALLOWED_ORIGINS="$tmp_dir/ALLOWED_ORIGINS" \
  --from-file=ANALYTICS_DISABLED="$tmp_dir/ANALYTICS_DISABLED" \
  --from-file=DATABASE_MAX_CONNS="$tmp_dir/DATABASE_MAX_CONNS" \
  --from-file=DATABASE_MIN_CONNS="$tmp_dir/DATABASE_MIN_CONNS" \
  --from-file=RATE_LIMIT_TRUSTED_PROXIES="$tmp_dir/RATE_LIMIT_TRUSTED_PROXIES" \
  --from-file=MULTICA_TRUSTED_PROXIES="$tmp_dir/MULTICA_TRUSTED_PROXIES" \
  --from-file=GITHUB_APP_SLUG="$tmp_dir/GITHUB_APP_SLUG" \
  --from-file=GITHUB_WEBHOOK_SECRET="$tmp_dir/GITHUB_WEBHOOK_SECRET" \
  --from-file=GITHUB_APP_ID="$tmp_dir/GITHUB_APP_ID" \
  --from-file=GITHUB_APP_PRIVATE_KEY="$tmp_dir/GITHUB_APP_PRIVATE_KEY" \
  --dry-run=client -o yaml \
  | kubectl apply -f - >/dev/null

kubectl -n "$NAMESPACE" label secret "$SECRET_NAME" \
  app.kubernetes.io/name=multica \
  app.kubernetes.io/managed-by=playsay-infra \
  playsay.io/component=agent-task-tracker \
  --overwrite >/dev/null

echo "Synced $SECRET_NAME in namespace $NAMESPACE."

if [[ -z "$(cat "$tmp_dir/SMTP_HOST")" && -z "$(cat "$tmp_dir/RESEND_API_KEY")" ]]; then
  echo "Warning: Multica email delivery is not configured. Verification codes will be written to backend logs until SMTP or Resend is set." >&2
elif [[ -n "$(playsay_email_value smtp-host)" && -z "${MULTICA_SMTP_HOST:-}" ]]; then
  echo "Multica email delivery is configured from ${PLAYSAY_EMAIL_NAMESPACE}/${PLAYSAY_EMAIL_SECRET_NAME} SMTP fallback values." >&2
fi

if [[ "$(cat "$tmp_dir/ALLOWED_EMAILS")" == "$DEFAULT_ALLOWED_EMAILS" ]]; then
  echo "Warning: Multica signup is restricted to the default $DEFAULT_ALLOWED_EMAILS allowlist. Set MULTICA_ALLOWED_EMAILS before production use." >&2
fi
