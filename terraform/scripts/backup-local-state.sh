#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: backup-local-state.sh --environment platform|dev|prod|ci \
  --public-key PATH --output-dir PATH --infra-commit SHA \
  --plan-sha256 SHA256

Run on AX41 immediately before and after every temporary local-state apply.
Creates a hybrid RSA/AES encrypted state bundle. Copy every resulting file off
the AX41; the RSA private key must never be present on the server.
EOF
}

environment_name=""
public_key=""
output_dir=""
infra_commit=""
plan_sha256=""

while (($#)); do
  case "$1" in
    --environment) environment_name="${2:?missing environment}"; shift 2 ;;
    --public-key) public_key="${2:?missing public key}"; shift 2 ;;
    --output-dir) output_dir="${2:?missing output directory}"; shift 2 ;;
    --infra-commit) infra_commit="${2:?missing infra commit}"; shift 2 ;;
    --plan-sha256) plan_sha256="${2:?missing plan checksum}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$environment_name" =~ ^(platform|dev|prod|ci)$ ]] || { echo "Invalid environment" >&2; exit 2; }
[[ -f "$public_key" ]] || { echo "RSA public key not found" >&2; exit 2; }
[[ -n "$output_dir" ]] || { echo "Output directory is required" >&2; exit 2; }
[[ "$infra_commit" =~ ^[0-9a-f]{7,40}$ ]] || { echo "Invalid infra commit" >&2; exit 2; }
[[ "$plan_sha256" =~ ^[0-9a-f]{64}$ ]] || { echo "Invalid plan checksum" >&2; exit 2; }

for command_name in jq openssl sha256sum tar gzip mktemp; do
  command -v "$command_name" >/dev/null || { echo "Missing command: $command_name" >&2; exit 1; }
done

state_file="/var/lib/playsay-opentofu-state/${environment_name}/terraform.tfstate"
[[ -s "$state_file" ]] || { echo "State does not exist: $state_file" >&2; exit 1; }
jq -e '.version >= 4 and (.serial >= 0) and (.lineage | type == "string")' "$state_file" >/dev/null

umask 077
mkdir -p "$output_dir"
work_dir="$(mktemp -d /var/tmp/playsay-tofu-state.XXXXXX)"
trap 'rm -rf -- "$work_dir"' EXIT

bundle_id="playsay-tofu-${environment_name}-$(date -u +%Y%m%dT%H%M%SZ)"
payload_dir="$work_dir/payload"
mkdir -p "$payload_dir"
cp "$state_file" "$payload_dir/terraform.tfstate"

jq -n \
  --arg schemaVersion "1" \
  --arg bundleId "$bundle_id" \
  --arg environment "$environment_name" \
  --arg createdAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg infraCommit "$infra_commit" \
  --arg planSha256 "$plan_sha256" \
  --argjson stateSerial "$(jq '.serial' "$state_file")" \
  '{schemaVersion: $schemaVersion, bundleId: $bundleId, environment: $environment, createdAt: $createdAt, infraCommit: $infraCommit, planSha256: $planSha256, stateSerial: $stateSerial}' \
  >"$payload_dir/manifest.json"

(cd "$payload_dir" && sha256sum terraform.tfstate manifest.json >SHA256SUMS)
tar -C "$payload_dir" -czf "$work_dir/payload.tar.gz" .
openssl rand -hex 32 >"$work_dir/data-key.txt"

encrypted_bundle="$output_dir/${bundle_id}.tar.gz.enc"
encrypted_key="$output_dir/${bundle_id}.key.enc"
openssl enc -aes-256-cbc -salt -pbkdf2 -iter 200000 -md sha256 \
  -pass "file:$work_dir/data-key.txt" -in "$work_dir/payload.tar.gz" -out "$encrypted_bundle"
openssl pkeyutl -encrypt -pubin -inkey "$public_key" \
  -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 \
  -in "$work_dir/data-key.txt" -out "$encrypted_key"

cp "$payload_dir/manifest.json" "$output_dir/${bundle_id}.manifest.json"
(cd "$output_dir" && sha256sum "$(basename "$encrypted_bundle")" "$(basename "$encrypted_key")" >"${bundle_id}.transport.sha256")
chmod 600 "$output_dir/${bundle_id}."*

echo "Encrypted local-state bundle created: $bundle_id"
