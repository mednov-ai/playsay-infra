#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=github-app-token.sh
source "${SCRIPT_DIR}/github-app-token.sh"

: "${RELEASE_BRANCH:?RELEASE_BRANCH is required}"
: "${PREVIOUS_RELEASE:?PREVIOUS_RELEASE is required}"
: "${WORKFLOW_NAME:?WORKFLOW_NAME is required}"
: "${REQUESTED_BY:?REQUESTED_BY is required}"
: "${BACKUP_PREFIX:=}"
: "${GITHUB_INFRA_REPOSITORY:=mednov-ai/playsay-infra}"

GITHUB_TOKEN="$(github_app_token)"
export GITHUB_TOKEN
work_dir="$(mktemp -d /tmp/playsay-rollback-check.XXXXXX)"
trap 'rm -rf "${work_dir}"' EXIT
github_git clone --quiet --single-branch --branch "${RELEASE_BRANCH}" \
  "https://github.com/${GITHUB_INFRA_REPOSITORY}.git" "${work_dir}/infra"
status="$(yq -r '.status // ""' "${work_dir}/infra/argocd-apps/prod/release-candidate.yaml")"
if [[ "${status}" != "deploying" ]]; then
  echo "Candidate is ${status}; no production sync rollback is required."
  exit 0
fi

TARGET_RELEASE="${PREVIOUS_RELEASE}" "${SCRIPT_DIR}/sync-argocd.sh"
EXPECTED_RELEASE="${PREVIOUS_RELEASE}" "${SCRIPT_DIR}/smoke-prod.sh"
CANDIDATE_STATUS=failed \
ROLLBACK_RELEASE="${PREVIOUS_RELEASE}" \
ROLLBACK_RESULT=passed \
SMOKE_RESULT=failed \
RELEASE_BRANCH="${RELEASE_BRANCH}" \
WORKFLOW_NAME="${WORKFLOW_NAME}" \
REQUESTED_BY="${REQUESTED_BY}" \
BACKUP_PREFIX="${BACKUP_PREFIX}" \
  "${SCRIPT_DIR}/update-candidate-status.sh"

echo "Applications rolled back to ${PREVIOUS_RELEASE}; database restore was not attempted."
