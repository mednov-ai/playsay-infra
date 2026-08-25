#!/usr/bin/env bash
set -euo pipefail

STORAGE_NAMESPACE="${STORAGE_NAMESPACE:-storage}"
APP_NAMESPACE="${APP_NAMESPACE:-playsay-dev}"
ROOT_SECRET="${ROOT_SECRET:-playsay-object-storage}"
SERVICE_SECRET="${SERVICE_SECRET:-playsay-worksheet-import}"
STAGING_SECRET="${STAGING_SECRET:-playsay-worksheet-import-storage}"
STAGING_BUCKET="${STAGING_BUCKET:-playsay-worksheet-staging}"
MINIO_ENDPOINT="${MINIO_ENDPOINT:-http://minio.storage.svc.cluster.local:9000}"
PROVISION_POD="worksheet-import-minio-provision"

for command_name in kubectl openssl python3 base64; do
  command -v "$command_name" >/dev/null 2>&1 || { echo "$command_name is required" >&2; exit 1; }
done

tmp_dir="$(mktemp -d)"
cleanup() {
  kubectl -n "$STORAGE_NAMESPACE" delete pod "$PROVISION_POD" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  rm -rf "$tmp_dir"
}
trap cleanup EXIT HUP INT TERM

kubectl create namespace "$APP_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n "$STORAGE_NAMESPACE" get secret "$ROOT_SECRET" >/dev/null

if ! kubectl -n "$APP_NAMESPACE" get secret "$SERVICE_SECRET" >/dev/null 2>&1; then
  openssl rand -base64 48 | tr -d '\r\n' > "$tmp_dir/service-token"
  kubectl -n "$APP_NAMESPACE" create secret generic "$SERVICE_SECRET" \
    --from-file=service-token="$tmp_dir/service-token" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
fi
kubectl -n "$APP_NAMESPACE" label secret "$SERVICE_SECRET" \
  app.kubernetes.io/name=worksheet-import-service \
  app.kubernetes.io/managed-by=playsay-infra \
  playsay.io/component=worksheet-import --overwrite >/dev/null

if ! kubectl -n "$STORAGE_NAMESPACE" get secret "$STAGING_SECRET" >/dev/null 2>&1; then
  openssl rand -hex 16 > "$tmp_dir/access-key"
  openssl rand -base64 48 | tr -d '\r\n' > "$tmp_dir/secret-key"
  kubectl -n "$STORAGE_NAMESPACE" create secret generic "$STAGING_SECRET" \
    --from-file=access-key="$tmp_dir/access-key" \
    --from-file=secret-key="$tmp_dir/secret-key" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
fi

kubectl -n "$STORAGE_NAMESPACE" delete pod "$PROVISION_POD" --ignore-not-found --wait=true >/dev/null 2>&1 || true
kubectl -n "$STORAGE_NAMESPACE" run "$PROVISION_POD" \
  --restart=Never \
  --image=minio/mc:RELEASE.2025-08-13T08-35-41Z \
  --env="MINIO_ENDPOINT=$MINIO_ENDPOINT" \
  --env="STAGING_BUCKET=$STAGING_BUCKET" \
  --overrides="$(
    kubectl -n "$STORAGE_NAMESPACE" run "$PROVISION_POD" --restart=Never --image=minio/mc:RELEASE.2025-08-13T08-35-41Z \
      --dry-run=client -o json --command -- /bin/sh -ec true |
      python3 -c '
import json, sys
p = json.load(sys.stdin)
c = p["spec"]["containers"][0]
c["env"] = [
  {"name":"MINIO_ENDPOINT","value":sys.argv[1]},
  {"name":"STAGING_BUCKET","value":sys.argv[2]},
  {"name":"MINIO_ROOT_USER","valueFrom":{"secretKeyRef":{"name":sys.argv[3],"key":"access-key"}}},
  {"name":"MINIO_ROOT_PASSWORD","valueFrom":{"secretKeyRef":{"name":sys.argv[3],"key":"secret-key"}}},
  {"name":"STAGING_ACCESS_KEY","valueFrom":{"secretKeyRef":{"name":sys.argv[4],"key":"access-key"}}},
  {"name":"STAGING_SECRET_KEY","valueFrom":{"secretKeyRef":{"name":sys.argv[4],"key":"secret-key"}}},
]
print(json.dumps(p))
' "$MINIO_ENDPOINT" "$STAGING_BUCKET" "$ROOT_SECRET" "$STAGING_SECRET"
  )" \
  --command -- /bin/sh -ec '
    mc alias set storage "$MINIO_ENDPOINT" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null
    mc mb --ignore-existing "storage/$STAGING_BUCKET" >/dev/null
    printf "%s" "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"s3:ListBucket\",\"s3:GetBucketLocation\"],\"Resource\":[\"arn:aws:s3:::$STAGING_BUCKET\"]},{\"Effect\":\"Allow\",\"Action\":[\"s3:GetObject\",\"s3:PutObject\",\"s3:DeleteObject\"],\"Resource\":[\"arn:aws:s3:::$STAGING_BUCKET/*\"]}]}" > /tmp/policy.json
    mc admin policy create storage worksheet-import-staging /tmp/policy.json >/dev/null 2>&1 || mc admin policy info storage worksheet-import-staging >/dev/null
    mc admin user add storage "$STAGING_ACCESS_KEY" "$STAGING_SECRET_KEY" >/dev/null 2>&1 || true
    mc admin policy attach storage worksheet-import-staging --user "$STAGING_ACCESS_KEY" >/dev/null
  ' >/dev/null

kubectl -n "$STORAGE_NAMESPACE" wait --for=condition=Ready "pod/$PROVISION_POD" --timeout=60s >/dev/null 2>&1 || true
if ! kubectl -n "$STORAGE_NAMESPACE" wait --for=jsonpath='{.status.phase}'=Succeeded "pod/$PROVISION_POD" --timeout=180s >/dev/null; then
  kubectl -n "$STORAGE_NAMESPACE" get pod "$PROVISION_POD" -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,REASON:.status.containerStatuses[0].state.terminated.reason >&2 || true
  exit 1
fi

kubectl -n "$STORAGE_NAMESPACE" get secret "$STAGING_SECRET" -o jsonpath='{.data.access-key}' | base64 -d > "$tmp_dir/access-key"
kubectl -n "$STORAGE_NAMESPACE" get secret "$STAGING_SECRET" -o jsonpath='{.data.secret-key}' | base64 -d > "$tmp_dir/secret-key"
kubectl -n "$APP_NAMESPACE" create secret generic "$STAGING_SECRET" \
  --from-file=access-key="$tmp_dir/access-key" \
  --from-file=secret-key="$tmp_dir/secret-key" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n "$APP_NAMESPACE" label secret "$STAGING_SECRET" \
  app.kubernetes.io/name=worksheet-import-service \
  app.kubernetes.io/managed-by=playsay-infra \
  playsay.io/component=worksheet-import --overwrite >/dev/null

echo "Worksheet import service token, restricted staging credentials and private bucket are provisioned."
