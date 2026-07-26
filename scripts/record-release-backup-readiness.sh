#!/usr/bin/env bash
set -Eeuo pipefail

: "${PLAYSAY_BACKUP_ENDPOINT:?PLAYSAY_BACKUP_ENDPOINT is required}"
: "${PLAYSAY_BACKUP_REGION:?PLAYSAY_BACKUP_REGION is required}"
: "${PLAYSAY_BACKUP_BUCKET:?PLAYSAY_BACKUP_BUCKET is required}"
: "${PLAYSAY_BACKUP_ACCESS_KEY:?PLAYSAY_BACKUP_ACCESS_KEY is required}"
: "${PLAYSAY_BACKUP_SECRET_KEY:?PLAYSAY_BACKUP_SECRET_KEY is required}"
: "${PLAYSAY_BACKUP_RESTORE_OBJECT:?PLAYSAY_BACKUP_RESTORE_OBJECT is required}"
: "${PLAYSAY_BACKUP_EXPECTED_SHA256:?PLAYSAY_BACKUP_EXPECTED_SHA256 is required}"
: "${AGE_IDENTITY_FILE:?AGE_IDENTITY_FILE is required and must stay outside the cluster}"
: "${RESTORE_DRILL_ID:?RESTORE_DRILL_ID is required}"

[[ -r "${AGE_IDENTITY_FILE}" ]] || {
  echo "The age restore identity is not readable." >&2
  exit 2
}
[[ "${PLAYSAY_BACKUP_EXPECTED_SHA256}" =~ ^[0-9a-f]{64}$ ]] || exit 2

export AWS_ACCESS_KEY_ID="${PLAYSAY_BACKUP_ACCESS_KEY}"
export AWS_SECRET_ACCESS_KEY="${PLAYSAY_BACKUP_SECRET_KEY}"
export AWS_DEFAULT_REGION="${PLAYSAY_BACKUP_REGION}"
export AWS_EC2_METADATA_DISABLED=true

aws_s3() {
  aws --endpoint-url "${PLAYSAY_BACKUP_ENDPOINT}" "$@"
}

[[ "$(aws_s3 s3api get-bucket-versioning --bucket "${PLAYSAY_BACKUP_BUCKET}" --query Status --output text)" == "Enabled" ]] || {
  echo "Backup bucket versioning is not enabled." >&2
  exit 3
}
[[ "$(aws_s3 s3api get-object-lock-configuration --bucket "${PLAYSAY_BACKUP_BUCKET}" --query ObjectLockConfiguration.ObjectLockEnabled --output text)" == "Enabled" ]] || {
  echo "Backup bucket Object Lock is not enabled." >&2
  exit 3
}

work_dir="$(mktemp -d /tmp/playsay-backup-restore-drill.XXXXXX)"
trap 'rm -rf "${work_dir}"' EXIT
aws_s3 s3 cp --only-show-errors \
  "s3://${PLAYSAY_BACKUP_BUCKET}/${PLAYSAY_BACKUP_RESTORE_OBJECT}" \
  "${work_dir}/restore.age"
age --decrypt -i "${AGE_IDENTITY_FILE}" \
  -o "${work_dir}/restore.payload" "${work_dir}/restore.age"
actual_sha="$(sha256sum "${work_dir}/restore.payload" | awk '{print $1}')"
[[ "${actual_sha}" == "${PLAYSAY_BACKUP_EXPECTED_SHA256}" ]] || {
  echo "Restore drill checksum mismatch." >&2
  exit 4
}

kubectl create namespace playsay-release-system --dry-run=client -o yaml |
  kubectl apply -f - >/dev/null
kubectl -n playsay-release-system create configmap playsay-release-backup-readiness \
  --from-literal=bucket-versioning=Enabled \
  --from-literal=object-lock=Enabled \
  --from-literal=restore-drill-id="${RESTORE_DRILL_ID}" \
  --from-literal=verified-at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  --dry-run=client -o yaml |
  kubectl apply -f - >/dev/null

echo "Backup restore drill ${RESTORE_DRILL_ID} passed and readiness was recorded."
