#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=github-app-token.sh
source "${SCRIPT_DIR}/github-app-token.sh"

: "${RELEASE_BRANCH:?RELEASE_BRANCH is required}"
: "${EXPECTED_INFRA_HEAD:?EXPECTED_INFRA_HEAD is required}"
: "${OUTPUT_DIR:=/tmp/outputs}"
: "${GITHUB_INFRA_REPOSITORY:=mednov-ai/playsay-infra}"
: "${GITHUB_PLATFORM_REPOSITORY:=mednov-ai/playsay-platform}"

[[ "${RELEASE_BRANCH}" =~ ^release/[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "Release branch must use numeric release/<number>.<number>.<number> format." >&2
  exit 2
}
[[ "${EXPECTED_INFRA_HEAD}" =~ ^[0-9a-f]{40}$ ]] || {
  echo "EXPECTED_INFRA_HEAD must be a full Git SHA." >&2
  exit 2
}

version="${RELEASE_BRANCH#release/}"
IFS=. read -r version_major version_minor version_patch <<<"${version}"
if (( version_major < 1 )) ||
  (( version_major == 1 && version_minor < 1 )) ||
  (( version_major == 1 && version_minor == 1 && version_patch < 8 )); then
  echo "Argo Workflows may promote only release/1.001.08 or newer; ${RELEASE_BRANCH} is legacy." >&2
  exit 2
fi

GITHUB_TOKEN="$(github_app_token)"
export GITHUB_TOKEN

work_dir="$(mktemp -d /tmp/playsay-candidate-validation.XXXXXX)"
trap 'rm -rf "${work_dir}"' EXIT
infra_dir="${work_dir}/infra"
github_git clone --quiet --single-branch --branch "${RELEASE_BRANCH}" \
  "https://github.com/${GITHUB_INFRA_REPOSITORY}.git" "${infra_dir}"
cd "${infra_dir}"

actual_infra_head="$(git rev-parse HEAD)"
[[ "${actual_infra_head}" == "${EXPECTED_INFRA_HEAD}" ]] || {
  echo "Reviewed infra SHA moved: expected ${EXPECTED_INFRA_HEAD}, found ${actual_infra_head}." >&2
  exit 3
}

manifest="argocd-apps/prod/release-candidate.yaml"
[[ -f "${manifest}" ]] || {
  echo "Candidate manifest is missing on ${RELEASE_BRANCH}." >&2
  exit 3
}

[[ "$(yq -r '.schemaVersion // 0' "${manifest}")" == "2" ]] || {
  echo "Legacy candidates cannot be promoted by Argo Workflows." >&2
  exit 3
}
[[ "$(yq -r '.status // ""' "${manifest}")" == "ready" ]] || {
  echo "Candidate status must be ready." >&2
  exit 3
}
[[ "$(yq -r '.releaseBranch // ""' "${manifest}")" == "${RELEASE_BRANCH}" ]] || {
  echo "Candidate releaseBranch does not match the requested branch." >&2
  exit 3
}

platform_sha="$(yq -r '.platformSha // ""' "${manifest}")"
infra_sha="$(yq -r '.infraSha // ""' "${manifest}")"
base_release="$(yq -r '.baseRelease // ""' "${manifest}")"
for sha in "${platform_sha}" "${infra_sha}"; do
  [[ "${sha}" =~ ^[0-9a-f]{40}$ ]] || {
    echo "Candidate contains an invalid platform/infra SHA." >&2
    exit 3
  }
done
[[ "${base_release}" =~ ^release/[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "Candidate baseRelease is invalid." >&2
  exit 3
}

git cat-file -e "${infra_sha}^{commit}" 2>/dev/null || {
  echo "Candidate infraSha is not available in the reviewed branch." >&2
  exit 3
}
unexpected_manifest_diff="$(
  git diff --name-only "${infra_sha}..${actual_infra_head}" |
    grep -vx 'argocd-apps/prod/release-candidate.yaml' || true
)"
[[ -z "${unexpected_manifest_diff}" ]] || {
  echo "Candidate changed after infra validation outside release-candidate.yaml:" >&2
  printf '%s\n' "${unexpected_manifest_diff}" >&2
  exit 3
}

github_git fetch --quiet origin develop
current_release="$(
  git show origin/develop:argocd-apps/prod/current-release.txt |
    tr -d '[:space:]'
)"
[[ "${current_release}" == "${base_release}" ]] || {
  echo "Production baseline moved from ${base_release} to ${current_release}." >&2
  exit 3
}

platform_head="$(
  github_git ls-remote --exit-code \
    "https://github.com/${GITHUB_PLATFORM_REPOSITORY}.git" \
    "refs/heads/${RELEASE_BRANCH}" |
    awk 'NR == 1 {print $1}'
)"
[[ "${platform_head}" == "${platform_sha}" ]] || {
  echo "Platform branch moved from ${platform_sha} to ${platform_head:-missing}." >&2
  exit 3
}

pulls="$(
  github_curl \
    "https://api.github.com/repos/${GITHUB_INFRA_REPOSITORY}/pulls?state=open&base=develop&head=mednov-ai%3A${RELEASE_BRANCH}"
)"
pr_number="$(
  jq -r \
    --arg head "${actual_infra_head}" \
    '.[] | select(.head.sha == $head) | .number' \
    <<<"${pulls}" |
    head -n 1
)"
[[ -n "${pr_number}" ]] || {
  echo "No open infra review PR targets develop at ${actual_infra_head}." >&2
  exit 4
}
reviews="$(
  github_curl \
    "https://api.github.com/repos/${GITHUB_INFRA_REPOSITORY}/pulls/${pr_number}/reviews"
)"
approved_count="$(jq '[.[] | select(.state == "APPROVED")] | length' <<<"${reviews}")"
(( approved_count > 0 )) || {
  echo "Infra PR #${pr_number} has no approval." >&2
  exit 4
}

mapfile -t migrations < <(yq -r '.migrationTargets[]?' "${manifest}")
allowed_migrations=" api-gateway ai-tutor-service vocabulary-service payment-service registration-service email-service keyboard-service "
for target in "${migrations[@]}"; do
  [[ "${allowed_migrations}" == *" ${target} "* ]] || {
    echo "Unsupported migration target in candidate: ${target}" >&2
    exit 3
  }
  TARGET="${target}" yq -e '.affectedTargets | index(strenv(TARGET)) != null' "${manifest}" >/dev/null || {
    echo "Migration target ${target} is not an affected target." >&2
    exit 3
  }
done

mkdir -p "${OUTPUT_DIR}"
printf '%s' "${base_release}" > "${OUTPUT_DIR}/base-release"
printf '%s' "${platform_sha}" > "${OUTPUT_DIR}/platform-sha"
printf '%s' "${actual_infra_head}" > "${OUTPUT_DIR}/candidate-head"
printf '%s' "${pr_number}" > "${OUTPUT_DIR}/infra-pr"
printf '%s' "$(IFS=,; echo "${migrations[*]}")" > "${OUTPUT_DIR}/migration-targets"

echo "Candidate ${RELEASE_BRANCH} at ${actual_infra_head} is ready and reviewed (PR #${pr_number})."
