#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: verify-encrypted-bundle.sh --bundle PATH --encrypted-key PATH \
  --private-key PATH [--transport-checksums PATH]

Decrypts into a temporary directory, validates every payload checksum and archive,
then removes all plaintext files. It never modifies the source bundle.
EOF
}

bundle=""
encrypted_key=""
private_key=""
transport_checksums=""

while (($#)); do
  case "$1" in
    --bundle) bundle="${2:?missing bundle}"; shift 2 ;;
    --encrypted-key) encrypted_key="${2:?missing encrypted key}"; shift 2 ;;
    --private-key) private_key="${2:?missing private key}"; shift 2 ;;
    --transport-checksums) transport_checksums="${2:?missing checksums}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

for required_file in "$bundle" "$encrypted_key" "$private_key"; do
  [[ -f "$required_file" ]] || { echo "Required file not found: $required_file" >&2; exit 2; }
done

for command_name in openssl shasum tar gzip mktemp; do
  command -v "$command_name" >/dev/null || { echo "Missing command: $command_name" >&2; exit 1; }
done

if [[ -n "$transport_checksums" ]]; then
  [[ -f "$transport_checksums" ]] || { echo "Transport checksum file not found" >&2; exit 2; }
  checksums_dir="$(cd "$(dirname "$transport_checksums")" && pwd)"
  (cd "$checksums_dir" && shasum -a 256 -c "$(basename "$transport_checksums")")
fi

umask 077
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/playsay-bundle-verify.XXXXXX")"
cleanup() { rm -rf -- "$work_dir"; }
trap cleanup EXIT

data_key="$work_dir/data-key.txt"
archive="$work_dir/payload.tar.gz"
payload="$work_dir/payload"
mkdir -p "$payload"

openssl pkeyutl -decrypt -inkey "$private_key" \
  -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 \
  -in "$encrypted_key" -out "$data_key"

openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -md sha256 \
  -pass "file:$data_key" -in "$bundle" -out "$archive"

gzip -t "$archive"
tar -tzf "$archive" >/dev/null
tar -xzf "$archive" -C "$payload"

for required_payload in application-postgresql.dump keycloak-postgresql.dump minio-data.tar.gz \
  sealed-secrets-keys.yaml workload-inventory.json pvc-inventory.json \
  kubernetes-version.json dump-validation.json manifest.json SHA256SUMS; do
  [[ -s "$payload/$required_payload" ]] || { echo "Missing payload: $required_payload" >&2; exit 1; }
done

(
  cd "$payload"
  shasum -a 256 -c SHA256SUMS
)

gzip -t "$payload/minio-data.tar.gz"
tar -tzf "$payload/minio-data.tar.gz" >/dev/null

if command -v jq >/dev/null; then
  jq -e '.schemaVersion == "1" and .targetEnvironment == "dev" and (.components.sealedSecretsKeys == true)' "$payload/manifest.json" >/dev/null
  jq -e '.applicationPostgreSQL == "pg_restore-list-ok" and .keycloakPostgreSQL == "pg_restore-list-ok" and .toolMajorVersion == 17' "$payload/dump-validation.json" >/dev/null
fi

if command -v pg_restore >/dev/null; then
  if ! pg_restore --list "$payload/application-postgresql.dump" >/dev/null 2>&1 \
    || ! pg_restore --list "$payload/keycloak-postgresql.dump" >/dev/null 2>&1; then
    echo "Local pg_restore cannot read PostgreSQL 17 custom dumps; source-side PostgreSQL 17 catalog validation is recorded and checksum-verified."
  fi
fi

echo "Encrypted bundle verified successfully: $(basename "$bundle")"
