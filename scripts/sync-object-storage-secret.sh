#!/usr/bin/env bash
set -euo pipefail

SOURCE_NAMESPACE="${SOURCE_NAMESPACE:-storage}"
SOURCE_SECRET="${SOURCE_SECRET:-playsay-object-storage}"
TARGET_NAMESPACES="${TARGET_NAMESPACES:-playsay-dev}"

require() {
  command -v "$1" >/dev/null || { echo "$1 is required" >&2; exit 1; }
}

require kubectl
require openssl

kubectl create namespace "$SOURCE_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

if ! kubectl -n "$SOURCE_NAMESPACE" get secret "$SOURCE_SECRET" >/dev/null 2>&1; then
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT
  openssl rand -hex 20 > "$tmpdir/access-key"
  openssl rand -base64 48 > "$tmpdir/secret-key"
  kubectl -n "$SOURCE_NAMESPACE" create secret generic "$SOURCE_SECRET" \
    --from-file=access-key="$tmpdir/access-key" \
    --from-file=secret-key="$tmpdir/secret-key" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
kubectl -n "$SOURCE_NAMESPACE" get secret "$SOURCE_SECRET" -o jsonpath='{.data.access-key}' | base64 -d > "$tmpdir/access-key"
kubectl -n "$SOURCE_NAMESPACE" get secret "$SOURCE_SECRET" -o jsonpath='{.data.secret-key}' | base64 -d > "$tmpdir/secret-key"

for namespace in $TARGET_NAMESPACES; do
  kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl -n "$namespace" create secret generic "$SOURCE_SECRET" \
    --from-file=access-key="$tmpdir/access-key" \
    --from-file=secret-key="$tmpdir/secret-key" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
done

echo "Object storage secret is present in $SOURCE_NAMESPACE and copied to: $TARGET_NAMESPACES"
