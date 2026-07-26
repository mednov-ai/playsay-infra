#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=github-app-token.sh
source "${SCRIPT_DIR}/github-app-token.sh"

: "${TARGET_RELEASE:?TARGET_RELEASE is required}"
: "${OUTPUT_DIR:=/tmp/outputs}"
: "${GITHUB_INFRA_REPOSITORY:=mednov-ai/playsay-infra}"
: "${GITHUB_PLATFORM_REPOSITORY:=mednov-ai/playsay-platform}"

[[ "${TARGET_RELEASE}" =~ ^release/[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 2
GITHUB_TOKEN="$(github_app_token)"
export GITHUB_TOKEN

work_dir="$(mktemp -d /tmp/playsay-rollback-validation.XXXXXX)"
trap 'rm -rf "${work_dir}"' EXIT
github_git clone --quiet --single-branch --branch develop \
  "https://github.com/${GITHUB_INFRA_REPOSITORY}.git" "${work_dir}/infra"
cd "${work_dir}/infra"

slug="${TARGET_RELEASE#release/}"
slug="${slug//./-}"
history="argocd-apps/prod/promotion-history/${slug}.yaml"
if [[ -f "${history}" ]]; then
  [[ "$(yq -r '.releaseBranch // ""' "${history}")" == "${TARGET_RELEASE}" ]] || exit 3
  [[ "$(yq -r '.smokeResult // ""' "${history}")" == "passed" ]] || {
    echo "${TARGET_RELEASE} was not recorded with a passing production smoke." >&2
    exit 3
  }
  platform_sha="$(yq -r '.platformSha // ""' "${history}")"
else
  github_git fetch --quiet origin "refs/heads/${TARGET_RELEASE}:refs/remotes/origin/rollback-target"
  candidate="$(
    git show "refs/remotes/origin/rollback-target:argocd-apps/prod/release-candidate.yaml" \
      2>/dev/null || true
  )"
  [[ "$(yq -r '.schemaVersion // 0' <<<"${candidate}")" == "2" ]] || {
    echo "${TARGET_RELEASE} has neither legacy history nor a schema-v2 candidate." >&2
    exit 3
  }
  [[ "$(yq -r '.releaseBranch // ""' <<<"${candidate}")" == "${TARGET_RELEASE}" ]] || exit 3
  [[ "$(yq -r '.status // ""' <<<"${candidate}")" == "promoted" ]] || {
    echo "${TARGET_RELEASE} was not recorded as promoted." >&2
    exit 3
  }
  [[ "$(yq -r '.promotion.smokeResult // ""' <<<"${candidate}")" == "passed" ]] || {
    echo "${TARGET_RELEASE} was not recorded with a passing production smoke." >&2
    exit 3
  }
  platform_sha="$(yq -r '.platformSha // ""' <<<"${candidate}")"
fi
current_release="$(tr -d '[:space:]' < argocd-apps/prod/current-release.txt)"
[[ "${current_release}" =~ ^release/[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 3
[[ "${current_release}" != "${TARGET_RELEASE}" ]] || {
  echo "${TARGET_RELEASE} is already current production." >&2
  exit 3
}
[[ "${platform_sha}" =~ ^[0-9a-f]{40}$ ]] || exit 3
platform_ref="$(
  github_git ls-remote --exit-code \
    "https://github.com/${GITHUB_PLATFORM_REPOSITORY}.git" \
    "refs/heads/${TARGET_RELEASE}" |
    awk 'NR == 1 {print $1}'
)"
github_git ls-remote --exit-code \
  "https://github.com/${GITHUB_INFRA_REPOSITORY}.git" \
  "refs/heads/${TARGET_RELEASE}" >/dev/null
[[ "${platform_ref}" == "${platform_sha}" ]] || {
  echo "Accepted platform branch ${TARGET_RELEASE} moved from ${platform_sha}." >&2
  exit 3
}

mkdir -p "${OUTPUT_DIR}"
printf '%s' "${platform_sha}" > "${OUTPUT_DIR}/platform-sha"
printf '%s' "${current_release}" > "${OUTPUT_DIR}/current-release"
echo "Rollback target ${TARGET_RELEASE} is an accepted immutable release."
