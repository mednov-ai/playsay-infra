#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_REPOSITORY="${IMAGE_REPOSITORY:-ghcr.io/mednov-ai/playsay-release-ops}"
SOURCE_SHA="${SOURCE_SHA:-$(git -C "${ROOT_DIR}" rev-parse HEAD)}"
PLATFORM="${PLATFORM:-linux/amd64}"

for command_name in docker git jq; do
  command -v "${command_name}" >/dev/null || {
    echo "Missing required command: ${command_name}" >&2
    exit 2
  }
done
[[ "${SOURCE_SHA}" =~ ^[0-9a-f]{40}$ ]] || {
  echo "SOURCE_SHA must be a full Git commit." >&2
  exit 2
}
[[ -z "$(git -C "${ROOT_DIR}" status --porcelain --untracked-files=no)" ]] || {
  echo "Tracked files must be committed before publishing the release-ops image." >&2
  exit 3
}

tag="${IMAGE_REPOSITORY}:${SOURCE_SHA}"
docker buildx build \
  --platform "${PLATFORM}" \
  --provenance=true \
  --sbom=true \
  --label "org.opencontainers.image.revision=${SOURCE_SHA}" \
  --tag "${tag}" \
  --push \
  "${ROOT_DIR}/argo-workflows/release-ops"

digest="$(
  docker buildx imagetools inspect "${tag}" --format '{{json .Manifest}}' |
    jq -r '.digest'
)"
[[ "${digest}" =~ ^sha256:[0-9a-f]{64}$ ]] || {
  echo "Unable to resolve immutable image digest for ${tag}." >&2
  exit 4
}
printf '%s@%s\n' "${IMAGE_REPOSITORY}" "${digest}"
