#!/usr/bin/env bash
set -Eeuo pipefail

required=(
  BACKUP_KIND
  BACKUP_PREFIX
  PLAYSAY_BACKUP_ENDPOINT
  PLAYSAY_BACKUP_REGION
  PLAYSAY_BACKUP_BUCKET
  PLAYSAY_BACKUP_ACCESS_KEY
  PLAYSAY_BACKUP_SECRET_KEY
  PLAYSAY_BACKUP_AGE_RECIPIENT
)
for name in "${required[@]}"; do
  [[ -n "${!name:-}" ]] || {
    echo "Missing backup input: ${name}" >&2
    exit 2
  }
done

export AWS_ACCESS_KEY_ID="${PLAYSAY_BACKUP_ACCESS_KEY}"
export AWS_SECRET_ACCESS_KEY="${PLAYSAY_BACKUP_SECRET_KEY}"
export AWS_DEFAULT_REGION="${PLAYSAY_BACKUP_REGION}"
export AWS_EC2_METADATA_DISABLED=true

aws_s3() {
  aws --endpoint-url "${PLAYSAY_BACKUP_ENDPOINT}" "$@"
}

versioning_status="$(
  aws_s3 s3api get-bucket-versioning \
    --bucket "${PLAYSAY_BACKUP_BUCKET}" \
    --query Status \
    --output text
)"
[[ "${versioning_status}" == "Enabled" ]] || {
  echo "Backup bucket versioning is not enabled." >&2
  exit 3
}

object_lock_status="$(
  aws_s3 s3api get-object-lock-configuration \
    --bucket "${PLAYSAY_BACKUP_BUCKET}" \
    --query ObjectLockConfiguration.ObjectLockEnabled \
    --output text
)"
[[ "${object_lock_status}" == "Enabled" ]] || {
  echo "Backup bucket Object Lock is not enabled." >&2
  exit 3
}

work_dir="$(mktemp -d /tmp/playsay-release-backup.XXXXXX)"
chmod 0700 "${work_dir}"
trap 'rm -rf "${work_dir}"' EXIT

encrypted_file="${work_dir}/${BACKUP_KIND}.tar.age"
case "${BACKUP_KIND}" in
  application-db|keyboard-db|keycloak-db)
    for name in PGHOST PGPORT PGUSER PGPASSWORD PGDATABASE; do
      [[ -n "${!name:-}" ]] || {
        echo "Missing PostgreSQL input for ${BACKUP_KIND}: ${name}" >&2
        exit 2
      }
    done
    export PGHOST PGPORT PGUSER PGPASSWORD PGDATABASE
    pg_dump --format=custom --no-owner --no-privileges |
      age --encrypt --recipient "${PLAYSAY_BACKUP_AGE_RECIPIENT}" \
        --output "${encrypted_file}"
    ;;
  minio)
    for name in MINIO_ENDPOINT MINIO_BUCKET MINIO_ACCESS_KEY MINIO_SECRET_KEY; do
      [[ -n "${!name:-}" ]] || {
        echo "Missing MinIO input: ${name}" >&2
        exit 2
      }
    done
    mkdir -p "${work_dir}/minio"
    mc alias set source "${MINIO_ENDPOINT}" "${MINIO_ACCESS_KEY}" "${MINIO_SECRET_KEY}" --api S3v4 >/dev/null
    mc mirror --overwrite --remove "source/${MINIO_BUCKET}" "${work_dir}/minio/${MINIO_BUCKET}" >/dev/null
    tar -C "${work_dir}/minio" -cf - "${MINIO_BUCKET}" |
      age --encrypt --recipient "${PLAYSAY_BACKUP_AGE_RECIPIENT}" \
        --output "${encrypted_file}"
    ;;
  *)
    echo "Unsupported BACKUP_KIND: ${BACKUP_KIND}" >&2
    exit 2
    ;;
esac

checksum="$(sha256sum "${encrypted_file}" | awk '{print $1}')"
object_key="${BACKUP_PREFIX}/${BACKUP_KIND}.tar.age"
checksum_key="${object_key}.sha256"

aws_s3 s3 cp --only-show-errors "${encrypted_file}" \
  "s3://${PLAYSAY_BACKUP_BUCKET}/${object_key}"
printf '%s  %s\n' "${checksum}" "$(basename "${encrypted_file}")" > "${encrypted_file}.sha256"
aws_s3 s3 cp --only-show-errors "${encrypted_file}.sha256" \
  "s3://${PLAYSAY_BACKUP_BUCKET}/${checksum_key}"

remote_size="$(
  aws_s3 s3api head-object \
    --bucket "${PLAYSAY_BACKUP_BUCKET}" \
    --key "${object_key}" \
    --query ContentLength \
    --output text
)"
local_size="$(wc -c < "${encrypted_file}" | tr -d '[:space:]')"
[[ "${remote_size}" == "${local_size}" ]] || {
  echo "Uploaded backup size does not match local encrypted artifact." >&2
  exit 4
}

echo "Encrypted ${BACKUP_KIND} backup verified at ${object_key} (${local_size} bytes)."
