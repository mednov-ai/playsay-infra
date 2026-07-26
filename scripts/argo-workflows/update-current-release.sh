#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=github-app-token.sh
source "${SCRIPT_DIR}/github-app-token.sh"

: "${RELEASE_BRANCH:?RELEASE_BRANCH is required}"
: "${PLATFORM_SHA:?PLATFORM_SHA is required}"
: "${WORKFLOW_NAME:?WORKFLOW_NAME is required}"
: "${REQUESTED_BY:?REQUESTED_BY is required}"
: "${BACKUP_PREFIX:?BACKUP_PREFIX is required}"
: "${OPERATION_MODE:=promotion}"
: "${ROLLBACK_REASON:=}"
: "${OUTPUT_DIR:=/tmp/outputs}"
: "${GITHUB_INFRA_REPOSITORY:=mednov-ai/playsay-infra}"

[[ "${RELEASE_BRANCH}" =~ ^release/[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 2
[[ "${PLATFORM_SHA}" =~ ^[0-9a-f]{40}$ ]] || exit 2
case "${OPERATION_MODE}" in
  promotion|rollback) ;;
  *) echo "Unsupported current-release operation: ${OPERATION_MODE}" >&2; exit 2 ;;
esac

GITHUB_TOKEN="$(github_app_token)"
export GITHUB_TOKEN
work_dir="$(mktemp -d /tmp/playsay-current-release.XXXXXX)"
trap 'rm -rf "${work_dir}"' EXIT
infra_dir="${work_dir}/infra"
github_git clone --quiet --single-branch --branch develop \
  "https://github.com/${GITHUB_INFRA_REPOSITORY}.git" "${infra_dir}"
cd "${infra_dir}"

previous_release="$(tr -d '[:space:]' < argocd-apps/prod/current-release.txt)"
[[ "${previous_release}" =~ ^release/[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "Current production baseline is invalid." >&2
  exit 3
}
[[ "${previous_release}" != "${RELEASE_BRANCH}" ]] || {
  echo "${RELEASE_BRANCH} is already current production."
  mkdir -p "${OUTPUT_DIR}"
  printf '%s' "already-current" > "${OUTPUT_DIR}/current-release-pr"
  exit 0
}

slug="${RELEASE_BRANCH#release/}"
slug="${slug//./-}"
workflow_slug="$(printf '%s' "${WORKFLOW_NAME}" | tr -c 'a-zA-Z0-9-' '-' | cut -c1-30)"
automation_branch="automation/${OPERATION_MODE}-${slug}-${workflow_slug}"
git switch --quiet -c "${automation_branch}"
printf '%s\n' "${RELEASE_BRANCH}" > argocd-apps/prod/current-release.txt

git config user.email "release-automation@honey.school"
git config user.name "HoneySchool Release Automation"
git add argocd-apps/prod/current-release.txt
changed_files="$(git diff --cached --name-only)"
expected_files="argocd-apps/prod/current-release.txt"
[[ "${changed_files}" == "${expected_files}" ]] || {
  echo "Refusing current-release update with an unexpected diff." >&2
  printf '%s\n' "${changed_files}" >&2
  exit 3
}
git commit --quiet -m "chore(prod): ${OPERATION_MODE} ${RELEASE_BRANCH}"
github_git push --quiet origin "HEAD:${automation_branch}"

pull_payload="$(
  jq -cn \
    --arg title "chore(prod): ${OPERATION_MODE} ${RELEASE_BRANCH}" \
    --arg head "${automation_branch}" \
    --arg body "Automated ${OPERATION_MODE} current-release update after Argo Workflows sync and smoke. Workflow: ${WORKFLOW_NAME}." \
    '{title:$title,head:$head,base:"develop",body:$body}'
)"
pull="$(
  github_curl \
    -X POST \
    -H "Content-Type: application/json" \
    -d "${pull_payload}" \
    "https://api.github.com/repos/${GITHUB_INFRA_REPOSITORY}/pulls"
)"
pr_number="$(jq -r '.number // empty' <<<"${pull}")"
pr_node_id="$(jq -r '.node_id // empty' <<<"${pull}")"
[[ -n "${pr_number}" && -n "${pr_node_id}" ]] || {
  echo "GitHub did not create the current-release PR." >&2
  exit 4
}

graphql_payload="$(
  jq -cn \
    --arg query 'mutation($pullRequestId:ID!){enablePullRequestAutoMerge(input:{pullRequestId:$pullRequestId,mergeMethod:SQUASH}){pullRequest{number}}}' \
    --arg id "${pr_node_id}" \
    '{query:$query,variables:{pullRequestId:$id}}'
)"
auto_merge="$(
  github_curl \
    -X POST \
    -H "Content-Type: application/json" \
    -d "${graphql_payload}" \
    https://api.github.com/graphql
)"
jq -e '.data.enablePullRequestAutoMerge.pullRequest.number != null and (.errors // [] | length == 0)' \
  <<<"${auto_merge}" >/dev/null || {
  echo "Could not enable auto-merge for current-release PR #${pr_number}." >&2
  exit 4
}

deadline="$((SECONDS + 900))"
while (( SECONDS < deadline )); do
  state="$(
    github_curl \
      "https://api.github.com/repos/${GITHUB_INFRA_REPOSITORY}/pulls/${pr_number}" |
      jq -r 'if .merged then "merged" else .state end'
  )"
  case "${state}" in
    merged)
      mkdir -p "${OUTPUT_DIR}"
      printf '%s' "${pr_number}" > "${OUTPUT_DIR}/current-release-pr"
      echo "Current-release PR #${pr_number} merged."
      exit 0
      ;;
    closed)
      echo "Current-release PR #${pr_number} closed without merge." >&2
      exit 4
      ;;
  esac
  sleep 10
done

echo "Timed out waiting for current-release PR #${pr_number}." >&2
exit 4
