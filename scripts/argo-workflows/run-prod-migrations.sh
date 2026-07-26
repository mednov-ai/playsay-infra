#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=github-app-token.sh
source "${SCRIPT_DIR}/github-app-token.sh"

: "${RELEASE_BRANCH:?RELEASE_BRANCH is required}"
: "${PLATFORM_SHA:?PLATFORM_SHA is required}"
: "${MIGRATION_TARGETS:=}"
: "${GITHUB_PLATFORM_REPOSITORY:=mednov-ai/playsay-platform}"

[[ "${RELEASE_BRANCH}" =~ ^release/[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "Invalid release branch: ${RELEASE_BRANCH}" >&2
  exit 2
}
[[ "${PLATFORM_SHA}" =~ ^[0-9a-f]{40}$ ]] || {
  echo "PLATFORM_SHA must be a full Git SHA." >&2
  exit 2
}
[[ -n "${MIGRATION_TARGETS}" ]] || {
  echo "Candidate declares no database migrations."
  exit 0
}

GITHUB_TOKEN="$(github_app_token)"
export GITHUB_TOKEN
work_dir="$(mktemp -d /tmp/playsay-prod-migrations.XXXXXX)"
trap 'rm -rf "${work_dir}"' EXIT
platform_dir="${work_dir}/platform"
github_git clone --quiet --single-branch --branch "${RELEASE_BRANCH}" \
  "https://github.com/${GITHUB_PLATFORM_REPOSITORY}.git" "${platform_dir}"
cd "${platform_dir}"
[[ "$(git rev-parse HEAD)" == "${PLATFORM_SHA}" ]] || {
  echo "Platform release moved before migrations." >&2
  exit 3
}

IFS=, read -ra targets <<<"${MIGRATION_TARGETS}"
for target in "${targets[@]}"; do
  case "${target}" in
    api-gateway|ai-tutor-service|vocabulary-service|payment-service|registration-service|email-service)
      db_secret="playsay-app-db"
      ;;
    keyboard-service)
      db_secret="playsay-keyboard-db"
      ;;
    "")
      continue
      ;;
    *)
      echo "Unsupported production migration target: ${target}" >&2
      exit 2
      ;;
  esac
  changelog_dir="backend/${target}/src/main/resources/db/changelog"
  [[ -f "${changelog_dir}/db.changelog-master.xml" ]] || {
    echo "Missing ${target} changelog master at ${PLATFORM_SHA}." >&2
    exit 3
  }
  MODULE_NAME="${target}" \
  CHANGELOG_DIR="${changelog_dir}" \
  DB_SECRET="${db_secret}" \
  SOURCE_SHA="${PLATFORM_SHA}" \
    "${SCRIPT_DIR}/launch-liquibase-job.sh"
done

echo "All declared production migrations completed."
