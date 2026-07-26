#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=github-app-token.sh
source "${SCRIPT_DIR}/github-app-token.sh"

: "${RELEASE_BRANCH:?RELEASE_BRANCH is required}"
: "${CANDIDATE_STATUS:?CANDIDATE_STATUS is required}"
: "${WORKFLOW_NAME:?WORKFLOW_NAME is required}"
: "${REQUESTED_BY:?REQUESTED_BY is required}"
: "${BACKUP_APPROVED_BY:=}"
: "${DEPLOY_APPROVED_BY:=}"
: "${BACKUP_PREFIX:=}"
: "${SMOKE_RESULT:=pending}"
: "${ROLLBACK_RELEASE:=}"
: "${ROLLBACK_RESULT:=not-required}"
: "${CURRENT_RELEASE_PR:=}"
: "${GITHUB_INFRA_REPOSITORY:=mednov-ai/playsay-infra}"

[[ "${RELEASE_BRANCH}" =~ ^release/[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "Invalid release branch: ${RELEASE_BRANCH}" >&2
  exit 2
}
case "${CANDIDATE_STATUS}" in
  deploying|promoted|failed) ;;
  *)
    echo "Unsupported candidate status transition: ${CANDIDATE_STATUS}" >&2
    exit 2
    ;;
esac

GITHUB_TOKEN="$(github_app_token)"
export GITHUB_TOKEN
start_dir="$(pwd)"

for attempt in 1 2 3; do
  work_dir="$(mktemp -d /tmp/playsay-candidate-status.XXXXXX)"
  infra_dir="${work_dir}/infra"
  github_git clone --quiet --single-branch --branch "${RELEASE_BRANCH}" \
    "https://github.com/${GITHUB_INFRA_REPOSITORY}.git" "${infra_dir}"
  cd "${infra_dir}"
  git config user.email "release-automation@honey.school"
  git config user.name "HoneySchool Release Automation"

  manifest="argocd-apps/prod/release-candidate.yaml"
  [[ "$(yq -r '.schemaVersion // 0' "${manifest}")" == "2" ]] || {
    echo "Only schema v2 candidates can change workflow status." >&2
    exit 3
  }
  current_status="$(yq -r '.status // ""' "${manifest}")"
  case "${current_status}:${CANDIDATE_STATUS}" in
    ready:deploying|deploying:promoted|deploying:failed) ;;
    "${CANDIDATE_STATUS}:${CANDIDATE_STATUS}")
      echo "Candidate is already ${CANDIDATE_STATUS}."
      cd "${start_dir}"
      rm -rf "${work_dir}"
      exit 0
      ;;
    *)
      echo "Invalid candidate transition ${current_status} -> ${CANDIDATE_STATUS}." >&2
      exit 3
      ;;
  esac

  now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  export CANDIDATE_STATUS WORKFLOW_NAME REQUESTED_BY BACKUP_APPROVED_BY
  export DEPLOY_APPROVED_BY BACKUP_PREFIX SMOKE_RESULT ROLLBACK_RELEASE
  export ROLLBACK_RESULT CURRENT_RELEASE_PR NOW="${now}"
  yq -i '
    .status = strenv(CANDIDATE_STATUS)
    | .promotion.workflow = strenv(WORKFLOW_NAME)
    | .promotion.requestedBy = strenv(REQUESTED_BY)
    | .promotion.approvedBy.backup = strenv(BACKUP_APPROVED_BY)
    | .promotion.approvedBy.deploy = strenv(DEPLOY_APPROVED_BY)
    | .promotion.backupPrefix = strenv(BACKUP_PREFIX)
    | .promotion.smokeResult = strenv(SMOKE_RESULT)
    | .promotion.rollback.release = strenv(ROLLBACK_RELEASE)
    | .promotion.rollback.result = strenv(ROLLBACK_RESULT)
    | .promotion.currentReleasePr = strenv(CURRENT_RELEASE_PR)
    | .updatedAt = strenv(NOW)
    | (
        if strenv(CANDIDATE_STATUS) == "deploying" then
          .promotion.startedAt = strenv(NOW)
        elif strenv(CANDIDATE_STATUS) == "promoted" or strenv(CANDIDATE_STATUS) == "failed" then
          .promotion.finishedAt = strenv(NOW)
        else .
        end
      )
  ' "${manifest}"

  git add "${manifest}"
  git commit --quiet \
    -m "chore(prod): mark ${RELEASE_BRANCH} ${CANDIDATE_STATUS}" \
    -m "Workflow: ${WORKFLOW_NAME}"
  if github_git push --quiet origin "HEAD:${RELEASE_BRANCH}"; then
    cd "${start_dir}"
    rm -rf "${work_dir}"
    echo "Candidate ${RELEASE_BRANCH} is ${CANDIDATE_STATUS}."
    exit 0
  fi

  cd "${start_dir}"
  rm -rf "${work_dir}"
  echo "Candidate status push race; retrying ${attempt}/3." >&2
done

echo "Could not update ${RELEASE_BRANCH} candidate status." >&2
exit 1
