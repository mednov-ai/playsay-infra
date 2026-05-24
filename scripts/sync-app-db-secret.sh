#!/usr/bin/env bash
set -euo pipefail

SOURCE_NAMESPACE="${SOURCE_NAMESPACE:-playsay-data}"
SOURCE_SECRET="${SOURCE_SECRET:-playsay-postgres-app}"
TARGET_SECRET="${TARGET_SECRET:-playsay-app-db}"
TARGET_NAMESPACES="${TARGET_NAMESPACES:-playsay-dev jenkins}"

require() {
  command -v "$1" >/dev/null || { echo "$1 is required" >&2; exit 1; }
}

usage() {
  cat <<USAGE
Usage:
  SOURCE_NAMESPACE=playsay-data SOURCE_SECRET=playsay-postgres-app TARGET_NAMESPACES="playsay-dev jenkins" $0

Copies the CloudNativePG application database connection secret into namespaces that need
runtime or migration access. Secret values are handled through temporary files and are not
printed.
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

secret_value_to_file() {
  local key="$1"
  local output="$2"
  kubectl -n "$SOURCE_NAMESPACE" get secret "$SOURCE_SECRET" -o "jsonpath={.data.$key}" | base64 -d > "$output"
}

secret_value_to_file "fqdn-jdbc-uri" "$tmp_dir/jdbc-uri"
secret_value_to_file "username" "$tmp_dir/username"
secret_value_to_file "password" "$tmp_dir/password"

for namespace in $TARGET_NAMESPACES; do
  kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl -n "$namespace" create secret generic "$TARGET_SECRET" \
    --from-file=jdbc-uri="$tmp_dir/jdbc-uri" \
    --from-file=username="$tmp_dir/username" \
    --from-file=password="$tmp_dir/password" \
    --dry-run=client -o yaml \
    | kubectl apply -f - >/dev/null
  kubectl -n "$namespace" label secret "$TARGET_SECRET" \
    app.kubernetes.io/name=playsay-app-db \
    app.kubernetes.io/managed-by=playsay-infra \
    --overwrite >/dev/null
  echo "Synced $TARGET_SECRET in namespace $namespace"
done
