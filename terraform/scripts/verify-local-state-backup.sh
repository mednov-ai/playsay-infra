#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: verify-local-state-backup.sh --bundle PATH --encrypted-key PATH \
  --private-key PATH [--transport-checksums PATH]

Decrypts a temporary OpenTofu state bundle, validates its checksums and JSON
shape, then removes all plaintext automatically.
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

if [[ -n "$transport_checksums" ]]; then
  checksums_dir="$(cd "$(dirname "$transport_checksums")" && pwd)"
  (cd "$checksums_dir" && shasum -a 256 -c "$(basename "$transport_checksums")")
fi

umask 077
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/playsay-tofu-state-verify.XXXXXX")"
trap 'rm -rf -- "$work_dir"' EXIT
mkdir -p "$work_dir/payload"

openssl pkeyutl -decrypt -inkey "$private_key" \
  -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 \
  -in "$encrypted_key" -out "$work_dir/data-key.txt"
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -md sha256 \
  -pass "file:$work_dir/data-key.txt" -in "$bundle" -out "$work_dir/payload.tar.gz"
gzip -t "$work_dir/payload.tar.gz"
tar -xzf "$work_dir/payload.tar.gz" -C "$work_dir/payload"

(cd "$work_dir/payload" && shasum -a 256 -c SHA256SUMS)
jq -e '.version >= 4 and (.serial >= 0) and (.lineage | type == "string")' "$work_dir/payload/terraform.tfstate" >/dev/null
jq -e '.schemaVersion == "1" and (.environment == "platform" or .environment == "dev" or .environment == "prod" or .environment == "ci") and (.planSha256 | test("^[0-9a-f]{64}$"))' "$work_dir/payload/manifest.json" >/dev/null

echo "Encrypted OpenTofu state backup verified successfully: $(basename "$bundle")"
