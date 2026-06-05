#!/usr/bin/env bash
set -euo pipefail

SOURCE_NAMESPACE="${SOURCE_NAMESPACE:-playsay-data}"
SOURCE_SECRET="${SOURCE_SECRET:-playsay-postgres-keyboard}"
TARGET_SECRET="${TARGET_SECRET:-playsay-keyboard-db}"
TARGET_NAMESPACES="${TARGET_NAMESPACES:-playsay-dev jenkins}"
DB_NAME="${DB_NAME:-keyboard}"
DB_USERNAME="${DB_USERNAME:-keyboard_app}"
DB_SERVICE_HOST="${DB_SERVICE_HOST:-playsay-postgres-rw.playsay-data.svc.cluster.local}"
DB_SERVICE_PORT="${DB_SERVICE_PORT:-5432}"

require() {
  command -v "$1" >/dev/null || { echo "$1 is required" >&2; exit 1; }
}

usage() {
  cat <<USAGE
Usage:
  SOURCE_NAMESPACE=playsay-data SOURCE_SECRET=playsay-postgres-keyboard TARGET_NAMESPACES="playsay-dev jenkins" $0

Ensures the CloudNativePG keyboard role password secret exists in the data namespace,
then syncs a runtime/migration connection secret into target namespaces. Secret values
are handled through temporary files and are not printed.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require kubectl
require openssl
require base64

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

kubectl create namespace "$SOURCE_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

if ! kubectl -n "$SOURCE_NAMESPACE" get secret "$SOURCE_SECRET" >/dev/null 2>&1; then
  openssl rand -base64 48 > "$tmp_dir/password"
  printf "%s" "$DB_USERNAME" > "$tmp_dir/username"
  kubectl -n "$SOURCE_NAMESPACE" create secret generic "$SOURCE_SECRET" \
    --type=kubernetes.io/basic-auth \
    --from-file=username="$tmp_dir/username" \
    --from-file=password="$tmp_dir/password" \
    --dry-run=client -o yaml \
    | kubectl apply -f - >/dev/null
else
  kubectl -n "$SOURCE_NAMESPACE" get secret "$SOURCE_SECRET" -o jsonpath='{.data.username}' | base64 -d > "$tmp_dir/username"
  kubectl -n "$SOURCE_NAMESPACE" get secret "$SOURCE_SECRET" -o jsonpath='{.data.password}' | base64 -d > "$tmp_dir/password"
fi

kubectl -n "$SOURCE_NAMESPACE" label secret "$SOURCE_SECRET" \
  app.kubernetes.io/name=playsay-keyboard-db \
  app.kubernetes.io/managed-by=playsay-infra \
  playsay.io/component=keyboard \
  cnpg.io/reload=true \
  --overwrite >/dev/null

printf "jdbc:postgresql://%s:%s/%s" "$DB_SERVICE_HOST" "$DB_SERVICE_PORT" "$DB_NAME" > "$tmp_dir/jdbc-uri"

for namespace in $TARGET_NAMESPACES; do
  kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl -n "$namespace" create secret generic "$TARGET_SECRET" \
    --from-file=jdbc-uri="$tmp_dir/jdbc-uri" \
    --from-file=username="$tmp_dir/username" \
    --from-file=password="$tmp_dir/password" \
    --dry-run=client -o yaml \
    | kubectl apply -f - >/dev/null
  kubectl -n "$namespace" label secret "$TARGET_SECRET" \
    app.kubernetes.io/name=playsay-keyboard-db \
    app.kubernetes.io/managed-by=playsay-infra \
    playsay.io/component=keyboard \
    --overwrite >/dev/null
  echo "Synced $TARGET_SECRET in namespace $namespace"
done
