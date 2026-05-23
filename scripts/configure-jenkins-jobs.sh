#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

JENKINS_URL="${JENKINS_URL:-http://127.0.0.1:${JENKINS_NODEPORT_HTTP:-32082}/jenkins}"
JENKINS_JOB_NAME="${JENKINS_JOB_NAME:-playsay-platform-develop}"
JOB_CONFIG="${JOB_CONFIG:-$REPO_ROOT/jenkins/jobs/playsay-platform-develop.xml}"

if [[ ! -f "$JOB_CONFIG" ]]; then
  echo "Job config not found: $JOB_CONFIG" >&2
  exit 1
fi

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
