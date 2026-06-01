#!/usr/bin/env bash
set -euo pipefail

SOURCE_NAMESPACE="${SOURCE_NAMESPACE:-keycloak}"
SOURCE_SECRET="${SOURCE_SECRET:-keycloak-dev-users}"
TARGET_SECRET="${TARGET_SECRET:-keycloak-dev-users}"
TARGET_NAMESPACES="${TARGET_NAMESPACES:-jenkins}"
PASSWORD_KEYS=(
  teacher-demo-password
  student-demo-password
  student-demo-2-password
)

require() {
  command -v "$1" >/dev/null || { echo "$1 is required" >&2; exit 1; }
}

usage() {
  cat <<USAGE
Usage:
  TARGET_NAMESPACES="jenkins" $0

Copies only the demo user password keys required by Jenkins Sprint 5 UI smoke from the
Keycloak namespace into target namespaces. Secret values are handled through temporary
files and are not printed.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require kubectl
require base64

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

for key in "${PASSWORD_KEYS[@]}"; do
  kubectl -n "$SOURCE_NAMESPACE" get secret "$SOURCE_SECRET" -o "jsonpath={.data.$key}" \
    | base64 -d > "$tmp_dir/$key"
done

for namespace in $TARGET_NAMESPACES; do
  kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  from_file_args=()
  for key in "${PASSWORD_KEYS[@]}"; do
    from_file_args+=(--from-file="$key=$tmp_dir/$key")
  done
  kubectl -n "$namespace" create secret generic "$TARGET_SECRET" \
    "${from_file_args[@]}" \
    --dry-run=client -o yaml \
    | kubectl apply -f - >/dev/null
  kubectl -n "$namespace" label secret "$TARGET_SECRET" \
    app.kubernetes.io/name=keycloak-dev-users \
    app.kubernetes.io/managed-by=playsay-infra \
    --overwrite >/dev/null
  echo "Synced $TARGET_SECRET in namespace $namespace"
done
