#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

JENKINS_URL="${JENKINS_URL:-http://127.0.0.1:${JENKINS_NODEPORT_HTTP:-32082}/jenkins}"
DEFAULT_JOB_NAMES=(
  playsay-legacy-vps-dispatch
  playsay-legacy-vps-platform
  playsay-legacy-vps-api-gateway
  playsay-legacy-vps-ai-tutor-service
  playsay-legacy-vps-vocabulary-service
  playsay-legacy-vps-web-app
  playsay-legacy-vps-collaboration-service
  playsay-legacy-vps-media-service
  playsay-legacy-vps-payment-service
  playsay-legacy-vps-registration-service
  playsay-legacy-vps-email-service
  playsay-legacy-vps-keyboard-backend
  playsay-legacy-vps-keyboard-frontend
)
DEFAULT_JOB_CONFIGS=(
  "$REPO_ROOT/jenkins/jobs/playsay-platform-dispatch-develop.xml"
  "$REPO_ROOT/jenkins/jobs/playsay-platform-develop.xml"
  "$REPO_ROOT/jenkins/jobs/playsay-api-gateway-develop.xml"
  "$REPO_ROOT/jenkins/jobs/playsay-ai-tutor-service-develop.xml"
  "$REPO_ROOT/jenkins/jobs/playsay-vocabulary-service-develop.xml"
  "$REPO_ROOT/jenkins/jobs/playsay-web-app-develop.xml"
  "$REPO_ROOT/jenkins/jobs/playsay-collaboration-service-develop.xml"
  "$REPO_ROOT/jenkins/jobs/playsay-media-service-develop.xml"
  "$REPO_ROOT/jenkins/jobs/playsay-payment-service-develop.xml"
  "$REPO_ROOT/jenkins/jobs/playsay-registration-service-develop.xml"
  "$REPO_ROOT/jenkins/jobs/playsay-email-service-develop.xml"
  "$REPO_ROOT/jenkins/jobs/playsay-keyboard-backend-develop.xml"
  "$REPO_ROOT/jenkins/jobs/playsay-keyboard-frontend-develop.xml"
)

CONFIGURE_ALL_JOBS=true
if [[ -n "${JOB_CONFIG:-}" || -n "${JENKINS_JOB_NAME:-}" ]]; then
  CONFIGURE_ALL_JOBS=false
  DEFAULT_JOB_NAMES=("${JENKINS_JOB_NAME:-playsay-legacy-vps-platform}")
  DEFAULT_JOB_CONFIGS=("${JOB_CONFIG:-$REPO_ROOT/jenkins/jobs/playsay-platform-develop.xml}")
fi

for config in "${DEFAULT_JOB_CONFIGS[@]}"; do
  if [[ ! -f "$config" ]]; then
    echo "Job config not found: $config" >&2
    exit 1
  fi
done

if [[ -z "${JENKINS_USER:-}" || -z "${JENKINS_PASSWORD:-}" ]]; then
  if ! command -v kubectl >/dev/null 2>&1; then
    echo "Set JENKINS_USER and JENKINS_PASSWORD, or run where kubectl can read the jenkins secret." >&2
    exit 1
  fi
  JENKINS_USER="${JENKINS_USER:-$(kubectl -n jenkins get secret jenkins -o jsonpath='{.data.jenkins-admin-user}' | base64 -d)}"
  JENKINS_PASSWORD="${JENKINS_PASSWORD:-$(kubectl -n jenkins get secret jenkins -o jsonpath='{.data.jenkins-admin-password}' | base64 -d)}"
fi

COOKIE_FILE="$(mktemp)"
trap 'rm -f "$COOKIE_FILE"' EXIT

echo "Waiting for Jenkins at $JENKINS_URL"
for _ in $(seq 1 60); do
  if curl -k -fsS -u "$JENKINS_USER:$JENKINS_PASSWORD" "$JENKINS_URL/login" >/dev/null 2>&1; then
    break
  fi
  sleep 5
done

CRUMB_JSON="$(curl -k -fsS -c "$COOKIE_FILE" -u "$JENKINS_USER:$JENKINS_PASSWORD" "$JENKINS_URL/crumbIssuer/api/json")"
CRUMB_FIELD="$(printf '%s' "$CRUMB_JSON" | sed -n 's/.*"crumbRequestField":"\([^"]*\)".*/\1/p')"
CRUMB_VALUE="$(printf '%s' "$CRUMB_JSON" | sed -n 's/.*"crumb":"\([^"]*\)".*/\1/p')"

if [[ -z "$CRUMB_FIELD" || -z "$CRUMB_VALUE" ]]; then
  echo "Could not get Jenkins crumb." >&2
  exit 1
fi

for index in "${!DEFAULT_JOB_NAMES[@]}"; do
  JENKINS_JOB_NAME="${DEFAULT_JOB_NAMES[$index]}"
  JOB_CONFIG="${DEFAULT_JOB_CONFIGS[$index]}"

  if curl -k -fsS -u "$JENKINS_USER:$JENKINS_PASSWORD" "$JENKINS_URL/job/$JENKINS_JOB_NAME/api/json" >/dev/null 2>&1; then
    echo "Updating Jenkins job $JENKINS_JOB_NAME"
    curl -k -fsS \
      -b "$COOKIE_FILE" \
      -u "$JENKINS_USER:$JENKINS_PASSWORD" \
      -H "$CRUMB_FIELD: $CRUMB_VALUE" \
      -H "Content-Type: application/xml" \
      --data-binary "@$JOB_CONFIG" \
      "$JENKINS_URL/job/$JENKINS_JOB_NAME/config.xml" >/dev/null
  else
    echo "Creating Jenkins job $JENKINS_JOB_NAME"
    curl -k -fsS \
      -b "$COOKIE_FILE" \
      -u "$JENKINS_USER:$JENKINS_PASSWORD" \
      -H "$CRUMB_FIELD: $CRUMB_VALUE" \
      -H "Content-Type: application/xml" \
      --data-binary "@$JOB_CONFIG" \
      "$JENKINS_URL/createItem?name=$JENKINS_JOB_NAME" >/dev/null
  fi

  echo "Jenkins job $JENKINS_JOB_NAME is configured."
done

if [[ "$CONFIGURE_ALL_JOBS" == "true" ]]; then
  REPLACED_JOB_NAMES=(
    playsay-platform-dispatch-develop
    playsay-platform-develop
    playsay-api-gateway-develop
    playsay-ai-tutor-service-develop
    playsay-vocabulary-service-develop
    playsay-web-app-develop
    playsay-collaboration-service-develop
    playsay-media-service-develop
    playsay-payment-service-develop
    playsay-registration-service-develop
    playsay-email-service-develop
    playsay-keyboard-backend-develop
    playsay-keyboard-frontend-develop
  )

  for replaced_job in "${REPLACED_JOB_NAMES[@]}"; do
    if curl -k -fsS -u "$JENKINS_USER:$JENKINS_PASSWORD" "$JENKINS_URL/job/$replaced_job/api/json" >/dev/null 2>&1; then
      curl -k -fsS \
        -b "$COOKIE_FILE" \
        -u "$JENKINS_USER:$JENKINS_PASSWORD" \
        -H "$CRUMB_FIELD: $CRUMB_VALUE" \
        -X POST \
        "$JENKINS_URL/job/$replaced_job/disable" >/dev/null
      echo "Disabled replaced Jenkins job $replaced_job."
    fi
  done
fi
