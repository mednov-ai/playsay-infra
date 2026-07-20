#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: export-dev-safety.sh --public-key PATH --output-dir PATH \
  [--platform-commit SHA] [--infra-commit SHA] [--label NAME]

Creates a full encrypted safety bundle from the current dev cluster. Run as root
on the source VPS. The RSA private key must stay off the source server.
EOF
}

public_key=""
output_dir=""
platform_commit="unknown"
infra_commit="unknown"
label="safety"

while (($#)); do
  case "$1" in
    --public-key) public_key="${2:?missing public-key value}"; shift 2 ;;
    --output-dir) output_dir="${2:?missing output-dir value}"; shift 2 ;;
    --platform-commit) platform_commit="${2:?missing platform commit}"; shift 2 ;;
    --infra-commit) infra_commit="${2:?missing infra commit}"; shift 2 ;;
    --label) label="${2:?missing label}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$public_key" && -f "$public_key" ]] || { echo "RSA public key is required" >&2; exit 2; }
[[ -n "$output_dir" ]] || { echo "Output directory is required" >&2; exit 2; }
[[ "$label" =~ ^[a-zA-Z0-9._-]+$ ]] || { echo "Unsafe label" >&2; exit 2; }

for command_name in kubectl jq openssl sha256sum tar gzip mktemp; do
  command -v "$command_name" >/dev/null || { echo "Missing command: $command_name" >&2; exit 1; }
done

export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
kubectl get --raw=/readyz >/dev/null

umask 077
mkdir -p "$output_dir"
work_dir="$(mktemp -d /var/tmp/playsay-ax41-export.XXXXXX)"
payload_dir="$work_dir/payload"
mkdir -p "$payload_dir"

cleanup() {
  if [[ -d "$work_dir" ]]; then
    find "$work_dir" -type f -exec chmod u+w {} + 2>/dev/null || true
    rm -rf -- "$work_dir"
  fi
}
trap cleanup EXIT

app_pod="$(kubectl -n playsay-data get pods -l cnpg.io/cluster=playsay-postgres -o json | jq -r '.items[] | select(.status.phase == "Running") | .metadata.name' | head -1)"
keycloak_db_pod="$(kubectl -n keycloak get pods -o json | jq -r '.items[] | select(any(.spec.containers[]; .name == "postgresql")) | select(.status.phase == "Running") | .metadata.name' | head -1)"
minio_pod="$(kubectl -n storage get pods -o json | jq -r '.items[] | select(any(.spec.containers[]; .name == "minio")) | select(.status.phase == "Running") | .metadata.name' | head -1)"

[[ -n "$app_pod" && -n "$keycloak_db_pod" && -n "$minio_pod" ]] || {
  echo "Could not resolve required source pods" >&2
  exit 1
}

echo "Exporting application PostgreSQL..."
kubectl -n playsay-data exec "$app_pod" -c postgres -- sh -lc \
  'pg_dump --format=custom --no-owner --no-privileges -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  >"$payload_dir/application-postgresql.dump"

echo "Exporting Keycloak PostgreSQL..."
kubectl -n keycloak exec "$keycloak_db_pod" -c postgresql -- sh -lc \
  'PGPASSWORD="$(cat "$POSTGRES_PASSWORD_FILE")" /opt/bitnami/postgresql/bin/pg_dump --format=custom --no-owner --no-privileges -U "$POSTGRES_USER" -d "$POSTGRES_DATABASE"' \
  >"$payload_dir/keycloak-postgresql.dump"

echo "Validating PostgreSQL dump catalogs with source PostgreSQL 17 tools..."
kubectl -n playsay-data exec -i "$app_pod" -c postgres -- pg_restore --list \
  <"$payload_dir/application-postgresql.dump" >/dev/null
kubectl -n keycloak exec -i "$keycloak_db_pod" -c postgresql -- \
  /opt/bitnami/postgresql/bin/pg_restore --list \
  <"$payload_dir/keycloak-postgresql.dump" >/dev/null
jq -n '{applicationPostgreSQL: "pg_restore-list-ok", keycloakPostgreSQL: "pg_restore-list-ok", toolMajorVersion: 17}' \
  >"$payload_dir/dump-validation.json"

echo "Exporting MinIO storage..."
minio_volume="$(kubectl -n storage get pod "$minio_pod" -o json | jq -r '.spec.containers[] | select(.name == "minio") | .volumeMounts[] | select(.mountPath == "/data") | .name')"
minio_claim="$(kubectl -n storage get pod "$minio_pod" -o json | jq -r --arg volume "$minio_volume" '.spec.volumes[] | select(.name == $volume) | .persistentVolumeClaim.claimName')"
minio_data_dir="$(find /var/lib/rancher/k3s/storage -maxdepth 1 -type d -name "*_${minio_claim}" -print -quit)"
[[ -n "$minio_data_dir" && -d "$minio_data_dir" ]] || {
  echo "Could not resolve MinIO local-path PVC directory" >&2
  exit 1
}
tar -C "$minio_data_dir" -cf - . | gzip -1 >"$payload_dir/minio-data.tar.gz"

echo "Exporting required recovery metadata..."
kubectl -n sealed-secrets get secrets \
  -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml \
  >"$payload_dir/sealed-secrets-keys.yaml"

kubectl get deployments,statefulsets -A -o json \
  | jq '{items: [.items[] | {kind, namespace: .metadata.namespace, name: .metadata.name, replicas: .spec.replicas, images: [.spec.template.spec.containers[].image]}]}' \
  >"$payload_dir/workload-inventory.json"

kubectl get pvc -A -o json \
  | jq '{items: [.items[] | {namespace: .metadata.namespace, name: .metadata.name, storageClass: .spec.storageClassName, requested: .spec.resources.requests.storage, capacity: .status.capacity.storage, phase: .status.phase}]}' \
  >"$payload_dir/pvc-inventory.json"

kubectl version -o json >"$payload_dir/kubernetes-version.json"

created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
bundle_id="playsay-${label}-$(date -u +%Y%m%dT%H%M%SZ)"

jq -n \
  --arg schemaVersion "1" \
  --arg bundleId "$bundle_id" \
  --arg createdAt "$created_at" \
  --arg sourceHost "$(hostname -f 2>/dev/null || hostname)" \
  --arg platformCommit "$platform_commit" \
  --arg infraCommit "$infra_commit" \
  --arg applicationPod "$app_pod" \
  --arg keycloakDatabasePod "$keycloak_db_pod" \
  --arg minioPod "$minio_pod" \
  '{schemaVersion: $schemaVersion, bundleId: $bundleId, createdAt: $createdAt, sourceHost: $sourceHost, targetEnvironment: "dev", platformCommit: $platformCommit, infraCommit: $infraCommit, components: {applicationPostgreSQL: $applicationPod, keycloakPostgreSQL: $keycloakDatabasePod, minio: $minioPod, sealedSecretsKeys: true}}' \
  >"$payload_dir/manifest.json"

(
  cd "$payload_dir"
  sha256sum application-postgresql.dump keycloak-postgresql.dump minio-data.tar.gz \
    sealed-secrets-keys.yaml workload-inventory.json pvc-inventory.json \
    kubernetes-version.json dump-validation.json manifest.json >SHA256SUMS
)

payload_archive="$work_dir/${bundle_id}.tar.gz"
tar -C "$payload_dir" -czf "$payload_archive" .

data_key="$work_dir/data-key.txt"
openssl rand -hex 32 >"$data_key"

encrypted_bundle="$output_dir/${bundle_id}.tar.gz.enc"
encrypted_key="$output_dir/${bundle_id}.key.enc"

openssl enc -aes-256-cbc -salt -pbkdf2 -iter 200000 -md sha256 \
  -pass "file:$data_key" -in "$payload_archive" -out "$encrypted_bundle"

openssl pkeyutl -encrypt -pubin -inkey "$public_key" \
  -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 \
  -in "$data_key" -out "$encrypted_key"

(
  cd "$output_dir"
  sha256sum "$(basename "$encrypted_bundle")" "$(basename "$encrypted_key")" \
    >"${bundle_id}.transport.sha256"
)
cp "$payload_dir/manifest.json" "$output_dir/${bundle_id}.manifest.json"
chmod 600 "$encrypted_bundle" "$encrypted_key" "$output_dir/${bundle_id}.transport.sha256" "$output_dir/${bundle_id}.manifest.json"

echo "Bundle created: $encrypted_bundle"
echo "Encrypted key: $encrypted_key"
echo "Transport checksums: $output_dir/${bundle_id}.transport.sha256"
