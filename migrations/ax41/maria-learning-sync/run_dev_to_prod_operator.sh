#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 077

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
infra_repo="$(cd "$script_dir/../../.." && pwd)"
platform_repo="$(cd "$infra_repo/../playsay-platform" && pwd)"
identity_tool="$script_dir/sync_student_identity_dev_to_prod.py"
learning_tool="$script_dir/sync_dev_to_prod.py"

apply_requested=false
case "${1:-}" in
  "") ;;
  --apply) apply_requested=true ;;
  -h|--help)
    cat <<'EOF'
Usage: ./run_dev_to_prod_operator.sh [--apply]

Without --apply the launcher creates isolated tunnels/profiles, discovers the
reviewed cohort from the encrypted VDSina-to-dev bundle and runs identity plans.
With --apply it additionally freezes dev/prod, transfers missing identities,
creates a fresh dev-to-prod bundle and applies/verifies it on production after
one interactive confirmation.

Optional path overrides:
  MIGRATION_SECURE_DIR
  MIGRATION_SOURCE_BUNDLE_DIR
  MIGRATION_SOURCE_BUNDLE
  MIGRATION_SOURCE_ENCRYPTED_KEY
  MIGRATION_PRIVATE_KEY
  MIGRATION_PUBLIC_KEY
  MIGRATION_SSH_KEY
EOF
    exit 0
    ;;
  *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
esac

secure_dir="${MIGRATION_SECURE_DIR:-$HOME/Backups/PlayAndSay/migrations/maria-dev-to-prod-20260817}"
source_bundle_dir="${MIGRATION_SOURCE_BUNDLE_DIR:-$HOME/Backups/PlayAndSay/migrations/maria-learning-vdsina-to-dev-20260817T135517Z}"
ssh_key="${MIGRATION_SSH_KEY:-$HOME/.ssh/play_and_say_vps_ed25519}"
jump_host="root@65.109.55.110"
dev_host="playsay@10.60.0.30"
prod_host="playsay@10.60.0.20"
kube="sudo env KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl"

dev_app_port=56432
prod_app_port=56433
dev_keycloak_port=56434
prod_keycloak_port=56435
dev_minio_port=59100
prod_minio_port=59101

die() { echo "ERROR: $*" >&2; exit 1; }

for tool in ssh nc base64 sed awk sort comm openssl tar shasum psql pg_dump pg_restore mc jq python3 git curl; do
  command -v "$tool" >/dev/null 2>&1 || die "missing command: $tool"
done
[[ -f "$ssh_key" ]] || die "SSH key is missing; set MIGRATION_SSH_KEY"
[[ -d "$source_bundle_dir" ]] || die "reviewed VDSina-to-dev bundle directory is missing; set MIGRATION_SOURCE_BUNDLE_DIR"

mkdir -p "$secure_dir" "$secure_dir/bundles/dev-to-prod" "$secure_dir/backups/prod-keycloak" \
  "$secure_dir/backups/prod-learning" "$secure_dir/reports" "$secure_dir/mc"
chmod 700 "$secure_dir" "$secure_dir/bundles" "$secure_dir/bundles/dev-to-prod" \
  "$secure_dir/backups" "$secure_dir/backups/prod-keycloak" "$secure_dir/backups/prod-learning" \
  "$secure_dir/reports" "$secure_dir/mc"

work="$(mktemp -d "${TMPDIR:-/tmp}/playsay-prod-operator.XXXXXX")"
chmod 700 "$work"
dev_tunnel_pid=""
prod_tunnel_pid=""
frozen=false
restored=false

ssh_common=(
  -i "$ssh_key"
  -o IdentitiesOnly=yes
  -o "ProxyCommand=ssh -i $ssh_key -o IdentitiesOnly=yes -W %h:%p $jump_host"
)

ssh_dev() { ssh "${ssh_common[@]}" "$dev_host" "$@"; }
ssh_prod() { ssh "${ssh_common[@]}" "$prod_host" "$@"; }

restore_replicas() {
  [[ "$frozen" == true && "$restored" == false ]] || return 0
  echo "Restoring recorded dev/prod replicas..."
  ssh_dev "$kube -n keycloak scale statefulset/keycloak --replicas=$(cat "$work/dev-keycloak-replicas") >/dev/null"
  ssh_prod "$kube -n keycloak scale statefulset/keycloak --replicas=$(cat "$work/prod-keycloak-replicas") >/dev/null"
  awk -F '\t' -v k="$kube" '{printf "%s -n playsay-dev scale deployment/%s --replicas=%s >/dev/null\n", k, $1, $2}' \
    "$work/dev-deployments.tsv" | ssh_dev 'bash -se'
  awk -F '\t' -v k="$kube" '{printf "%s -n playsay-prod scale deployment/%s --replicas=%s >/dev/null\n", k, $1, $2}' \
    "$work/prod-deployments.tsv" | ssh_prod 'bash -se'
  ssh_dev "$kube -n argocd scale statefulset/argocd-application-controller --replicas=$(cat "$work/dev-argocd-replicas") >/dev/null"
  ssh_prod "$kube -n argocd scale statefulset/argocd-application-controller --replicas=$(cat "$work/prod-argocd-replicas") >/dev/null"
  restored=true
}

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  restore_replicas || true
  [[ -z "$dev_tunnel_pid" ]] || kill "$dev_tunnel_pid" >/dev/null 2>&1 || true
  [[ -z "$prod_tunnel_pid" ]] || kill "$prod_tunnel_pid" >/dev/null 2>&1 || true
  rm -rf -- "$work"
  exit "$status"
}
trap cleanup EXIT INT TERM

service_ip() {
  local environment="$1" namespace="$2" service="$3"
  if [[ "$environment" == dev ]]; then
    ssh_dev "$kube -n $namespace get service $service -o jsonpath='{.spec.clusterIP}'"
  else
    ssh_prod "$kube -n $namespace get service $service -o jsonpath='{.spec.clusterIP}'"
  fi
}

require_cluster_ip() {
  local environment="$1" service="$2" address="$3"
  [[ "$address" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || die "cannot discover $environment ClusterIP for $service"
}

start_tunnel() {
  local result_variable="$1" host="$2" app_ip="$3" keycloak_ip="$4" minio_ip="$5"
  local local_app="$6" local_keycloak="$7" local_minio="$8" log="$9"
  ssh "${ssh_common[@]}" \
    -N \
    -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    -L "$local_app:$app_ip:5432" \
    -L "$local_keycloak:$keycloak_ip:5432" \
    -L "$local_minio:$minio_ip:9000" \
    "$host" >"$log" 2>&1 &
  local tunnel_pid=$!
  printf -v "$result_variable" '%s' "$tunnel_pid"
}

echo "Discovering dev/prod Kubernetes service addresses..."
dev_app_ip="$(service_ip dev playsay-data playsay-postgres-rw)"
dev_keycloak_ip="$(service_ip dev keycloak keycloak-postgresql)"
dev_minio_ip="$(service_ip dev storage minio)"
prod_app_ip="$(service_ip prod playsay-data playsay-postgres-rw)"
prod_keycloak_ip="$(service_ip prod keycloak keycloak-postgresql)"
prod_minio_ip="$(service_ip prod storage minio)"

require_cluster_ip dev playsay-postgres-rw "$dev_app_ip"
require_cluster_ip dev keycloak-postgresql "$dev_keycloak_ip"
require_cluster_ip dev minio "$dev_minio_ip"
require_cluster_ip prod playsay-postgres-rw "$prod_app_ip"
require_cluster_ip prod keycloak-postgresql "$prod_keycloak_ip"
require_cluster_ip prod minio "$prod_minio_ip"

echo "Starting isolated dev/prod SSH tunnels..."
start_tunnel dev_tunnel_pid "$dev_host" "$dev_app_ip" "$dev_keycloak_ip" "$dev_minio_ip" \
  "$dev_app_port" "$dev_keycloak_port" "$dev_minio_port" "$work/dev-tunnel.log"
start_tunnel prod_tunnel_pid "$prod_host" "$prod_app_ip" "$prod_keycloak_ip" "$prod_minio_ip" \
  "$prod_app_port" "$prod_keycloak_port" "$prod_minio_port" "$work/prod-tunnel.log"

for _ in {1..30}; do
  all_ready=true
  for port in "$dev_app_port" "$prod_app_port" "$dev_keycloak_port" "$prod_keycloak_port" "$dev_minio_port" "$prod_minio_port"; do
    nc -z -w 1 127.0.0.1 "$port" >/dev/null 2>&1 || all_ready=false
  done
  [[ "$all_ready" == true ]] && break
  sleep 1
done
[[ "${all_ready:-false}" == true ]] || die "one or more isolated tunnels failed"
kill -0 "$dev_tunnel_pid" >/dev/null 2>&1 || die "dev tunnel process exited"
kill -0 "$prod_tunnel_pid" >/dev/null 2>&1 || die "prod tunnel process exited"

secret_value() {
  local environment="$1" namespace="$2" secret="$3" key="$4"
  if [[ "$environment" == dev ]]; then
    ssh_dev "$kube -n $namespace get secret $secret -o jsonpath='{.data.$key}'" | base64 -d
  else
    ssh_prod "$kube -n $namespace get secret $secret -o jsonpath='{.data.$key}'" | base64 -d
  fi
}

echo "Creating isolated protected database and MinIO profiles..."
dev_app_user="$(secret_value dev playsay-data playsay-postgres-app username)"
dev_app_password="$(secret_value dev playsay-data playsay-postgres-app password)"
prod_app_user="$(secret_value prod playsay-data playsay-postgres-app username)"
prod_app_password="$(secret_value prod playsay-data playsay-postgres-app password)"
dev_keycloak_password="$(secret_value dev keycloak keycloak-postgresql password)"
prod_keycloak_password="$(secret_value prod keycloak keycloak-postgresql password)"
dev_s3_access="$(secret_value dev storage playsay-object-storage access-key)"
dev_s3_secret="$(secret_value dev storage playsay-object-storage secret-key)"
prod_s3_access="$(secret_value prod storage playsay-object-storage access-key)"
prod_s3_secret="$(secret_value prod storage playsay-object-storage secret-key)"

for value in "$dev_app_user" "$dev_app_password" "$prod_app_user" "$prod_app_password" \
  "$dev_keycloak_password" "$prod_keycloak_password" "$dev_s3_access" "$dev_s3_secret" \
  "$prod_s3_access" "$prod_s3_secret"; do
  [[ -n "$value" ]] || die "a required protected credential is empty"
done

export PGSERVICEFILE="$secure_dir/pg_service.conf"
export PGPASSFILE="$secure_dir/pgpass"
export MC_CONFIG_DIR="$secure_dir/mc"
cat >"$PGSERVICEFILE" <<EOF
[ax41-dev-playsay]
host=127.0.0.1
port=$dev_app_port
dbname=playsay
user=$dev_app_user
sslmode=disable
connect_timeout=10

[ax41-prod-playsay]
host=127.0.0.1
port=$prod_app_port
dbname=playsay
user=$prod_app_user
sslmode=disable
connect_timeout=10

[ax41-dev-keycloak]
host=127.0.0.1
port=$dev_keycloak_port
dbname=bitnami_keycloak
user=bn_keycloak
sslmode=disable
connect_timeout=10

[ax41-prod-keycloak]
host=127.0.0.1
port=$prod_keycloak_port
dbname=bitnami_keycloak
user=bn_keycloak
sslmode=disable
connect_timeout=10
EOF

pgpass_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/:/\\:/g'; }
{
  printf '127.0.0.1:%s:playsay:%s:%s\n' "$dev_app_port" "$(pgpass_escape "$dev_app_user")" "$(pgpass_escape "$dev_app_password")"
  printf '127.0.0.1:%s:playsay:%s:%s\n' "$prod_app_port" "$(pgpass_escape "$prod_app_user")" "$(pgpass_escape "$prod_app_password")"
  printf '127.0.0.1:%s:bitnami_keycloak:bn_keycloak:%s\n' "$dev_keycloak_port" "$(pgpass_escape "$dev_keycloak_password")"
  printf '127.0.0.1:%s:bitnami_keycloak:bn_keycloak:%s\n' "$prod_keycloak_port" "$(pgpass_escape "$prod_keycloak_password")"
} >"$PGPASSFILE"
chmod 600 "$PGSERVICEFILE" "$PGPASSFILE"

databases_ready=false
for _ in {1..30}; do
  if PGSERVICE=ax41-dev-playsay psql -X -Atqc 'select 1' 2>/dev/null | grep -qx 1 \
    && PGSERVICE=ax41-prod-playsay psql -X -Atqc 'select 1' 2>/dev/null | grep -qx 1 \
    && PGSERVICE=ax41-dev-keycloak psql -X -Atqc 'select 1' 2>/dev/null | grep -qx 1 \
    && PGSERVICE=ax41-prod-keycloak psql -X -Atqc 'select 1' 2>/dev/null | grep -qx 1; then
    databases_ready=true
    break
  fi
  kill -0 "$dev_tunnel_pid" >/dev/null 2>&1 || break
  kill -0 "$prod_tunnel_pid" >/dev/null 2>&1 || break
  sleep 1
done
[[ "$databases_ready" == true ]] || die "database tunnels did not become ready"

minio_ready=false
for _ in {1..30}; do
  if mc alias set ax41-dev "http://127.0.0.1:$dev_minio_port" "$dev_s3_access" "$dev_s3_secret" >/dev/null 2>&1 \
    && mc alias set ax41-prod "http://127.0.0.1:$prod_minio_port" "$prod_s3_access" "$prod_s3_secret" >/dev/null 2>&1 \
    && mc stat ax41-dev/playsay-material-assets >/dev/null 2>&1 \
    && mc stat ax41-prod/playsay-material-assets >/dev/null 2>&1; then
    minio_ready=true
    break
  fi
  kill -0 "$dev_tunnel_pid" >/dev/null 2>&1 || break
  kill -0 "$prod_tunnel_pid" >/dev/null 2>&1 || break
  sleep 1
done
[[ "$minio_ready" == true ]] || die "MinIO tunnels did not become ready"
unset dev_app_password prod_app_password dev_keycloak_password prod_keycloak_password
unset dev_s3_access dev_s3_secret prod_s3_access prod_s3_secret

for service in ax41-dev-playsay ax41-prod-playsay ax41-dev-keycloak ax41-prod-keycloak; do
  PGSERVICE="$service" psql -X -Atqc 'select 1' | grep -qx 1 || die "$service connection failed"
done
mc stat ax41-dev/playsay-material-assets >/dev/null || die "dev MinIO connection failed"
mc stat ax41-prod/playsay-material-assets >/dev/null || die "prod MinIO connection failed"

find_single() {
  local description="$1"; shift
  local -a matches=("$@")
  [[ ${#matches[@]} -eq 1 && -f "${matches[0]}" ]] || die "cannot uniquely discover $description; set its MIGRATION_* override"
  printf '%s' "${matches[0]}"
}

source_bundle="${MIGRATION_SOURCE_BUNDLE:-}"
if [[ -z "$source_bundle" ]]; then
  mapfile -t candidates < <(find "$source_bundle_dir" -maxdepth 1 -type f -name 'maria-learning-vdsina-to-dev-*.tar.gz.enc' | sort)
  source_bundle="$(find_single source-bundle "${candidates[@]}")"
fi
source_encrypted_key="${MIGRATION_SOURCE_ENCRYPTED_KEY:-${source_bundle%.tar.gz.enc}.key.enc}"
[[ -f "$source_encrypted_key" ]] || die "source encrypted data key is missing"

private_key="${MIGRATION_PRIVATE_KEY:-}"
public_key="${MIGRATION_PUBLIC_KEY:-}"
if [[ -z "$private_key" ]]; then
  private_candidates=()
  while IFS= read -r candidate; do
    openssl pkey -in "$candidate" -noout >/dev/null 2>&1 && private_candidates+=("$candidate")
  done < <(find "$source_bundle_dir" -maxdepth 1 -type f -name '*.pem' | sort)
  private_key="$(find_single private-key "${private_candidates[@]}")"
fi
[[ -f "$private_key" ]] || die "private key is missing; set MIGRATION_PRIVATE_KEY"
if [[ -z "$public_key" ]]; then
  public_key="$secure_dir/migration-public-derived.pem"
  openssl pkey -in "$private_key" -pubout -out "$public_key" >/dev/null 2>&1 \
    || die "cannot derive public key from the migration private key"
  chmod 600 "$public_key"
fi
[[ -f "$public_key" ]] || die "public key is missing; set MIGRATION_PUBLIC_KEY"

echo "Recovering reviewed immutable cohort selectors without printing them..."
openssl pkeyutl -decrypt -inkey "$private_key" \
  -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 \
  -in "$source_encrypted_key" -out "$work/source-data-key.txt"
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -md sha256 \
  -pass "file:$work/source-data-key.txt" -in "$source_bundle" -out "$work/source.tar.gz"
mkdir -p "$work/source"
tar -xzf "$work/source.tar.gz" -C "$work/source"
(cd "$work/source" && shasum -a 256 -c PAYLOAD_SHA256SUMS >/dev/null)
[[ -s "$work/source/maria-subject.txt" && -s "$work/source/cohort-subjects.txt" ]] || die "reviewed bundle has no cohort selectors"
cp "$work/source/maria-subject.txt" "$secure_dir/maria.subject"
chmod 600 "$secure_dir/maria.subject"

python3 "$identity_tool" export-inventory \
  --target-pg-service ax41-prod-keycloak \
  --output "$work/prod-subjects-before.txt" >/dev/null
sort -u "$work/source/cohort-subjects.txt" >"$work/cohort-sorted.txt"
sort -u "$work/prod-subjects-before.txt" >"$work/prod-sorted.txt"
comm -23 "$work/cohort-sorted.txt" "$work/prod-sorted.txt" >"$work/missing-subjects.txt"
missing_count="$(awk 'NF {count++} END {print count+0}' "$work/missing-subjects.txt")"
echo "Missing reviewed production identities: $missing_count"

identity_index=0
while IFS= read -r subject; do
  [[ -n "$subject" ]] || continue
  identity_index=$((identity_index + 1))
  subject_file="$work/student-$identity_index.subject"
  printf '%s\n' "$subject" >"$subject_file"
  chmod 600 "$subject_file"
  python3 "$identity_tool" plan \
    --source-pg-service ax41-dev-keycloak \
    --target-pg-service ax41-prod-keycloak \
    --student-subject-file "$subject_file"
done <"$work/missing-subjects.txt"

if [[ "$apply_requested" == false ]]; then
  echo "Preflight complete. Re-run the same command with --apply to execute production migration."
  exit 0
fi

printf 'Type APPLY PROD to start the maintenance window: '
IFS= read -r confirmation
[[ "$confirmation" == "APPLY PROD" ]] || die "operator confirmation did not match"

echo "Recording replicas and freezing dev/prod writers..."
ssh_dev "$kube -n playsay-dev get deployments -o json" | jq -r '.items[] | [.metadata.name, (.spec.replicas // 0)] | @tsv' >"$work/dev-deployments.tsv"
ssh_prod "$kube -n playsay-prod get deployments -o json" | jq -r '.items[] | [.metadata.name, (.spec.replicas // 0)] | @tsv' >"$work/prod-deployments.tsv"
ssh_dev "$kube -n keycloak get statefulset keycloak -o jsonpath='{.spec.replicas}'" >"$work/dev-keycloak-replicas"
ssh_prod "$kube -n keycloak get statefulset keycloak -o jsonpath='{.spec.replicas}'" >"$work/prod-keycloak-replicas"
ssh_dev "$kube -n argocd get statefulset argocd-application-controller -o jsonpath='{.spec.replicas}'" >"$work/dev-argocd-replicas"
ssh_prod "$kube -n argocd get statefulset argocd-application-controller -o jsonpath='{.spec.replicas}'" >"$work/prod-argocd-replicas"

frozen=true
ssh_dev "$kube -n argocd scale statefulset/argocd-application-controller --replicas=0 >/dev/null; $kube -n playsay-dev scale deployment --all --replicas=0 >/dev/null; $kube -n keycloak scale statefulset/keycloak --replicas=0 >/dev/null"
ssh_prod "$kube -n argocd scale statefulset/argocd-application-controller --replicas=0 >/dev/null; $kube -n playsay-prod scale deployment --all --replicas=0 >/dev/null; $kube -n keycloak scale statefulset/keycloak --replicas=0 >/dev/null"

cat >"$work/assert-dev-keycloak-stopped" <<EOF
#!/usr/bin/env bash
set -euo pipefail
ssh -n ${ssh_common[*]@Q} ${dev_host@Q} '$kube -n keycloak get statefulset keycloak -o json' |
  jq -e '(.spec.replicas // 0) == 0 and (.status.readyReplicas // 0) == 0' >/dev/null
EOF
cat >"$work/assert-prod-keycloak-stopped" <<EOF
#!/usr/bin/env bash
set -euo pipefail
ssh -n ${ssh_common[*]@Q} ${prod_host@Q} '$kube -n keycloak get statefulset keycloak -o json' |
  jq -e '(.spec.replicas // 0) == 0 and (.status.readyReplicas // 0) == 0' >/dev/null
EOF
cat >"$work/assert-prod-maintenance" <<EOF
#!/usr/bin/env bash
set -euo pipefail
deployments="\$(ssh -n ${ssh_common[*]@Q} ${prod_host@Q} '$kube -n playsay-prod get deployments -o json')"
controller="\$(ssh -n ${ssh_common[*]@Q} ${prod_host@Q} '$kube -n argocd get statefulset argocd-application-controller -o json')"
jq -e '[.items[] | ((.spec.replicas // 0) + (.status.readyReplicas // 0))] | add // 0 | . == 0' <<<"\$deployments" >/dev/null
jq -e '((.spec.replicas // 0) + (.status.readyReplicas // 0)) == 0' <<<"\$controller" >/dev/null
EOF
chmod 700 "$work/assert-dev-keycloak-stopped" "$work/assert-prod-keycloak-stopped" "$work/assert-prod-maintenance"

for _ in {1..90}; do
  "$work/assert-dev-keycloak-stopped" && "$work/assert-prod-keycloak-stopped" && "$work/assert-prod-maintenance" && break
  sleep 2
done
"$work/assert-dev-keycloak-stopped" || die "dev Keycloak did not stop"
"$work/assert-prod-keycloak-stopped" || die "prod Keycloak did not stop"
"$work/assert-prod-maintenance" || die "prod writers did not stop"

identity_index=0
while IFS= read -r subject; do
  [[ -n "$subject" ]] || continue
  identity_index=$((identity_index + 1))
  subject_file="$work/student-$identity_index.subject"
  python3 "$identity_tool" apply \
    --source-pg-service ax41-dev-keycloak \
    --target-pg-service ax41-prod-keycloak \
    --student-subject-file "$subject_file" \
    --backup-dir "$secure_dir/backups/prod-keycloak" \
    --backup-public-key "$public_key" \
    --backup-private-key "$private_key" \
    --source-maintenance-guard-command "$work/assert-dev-keycloak-stopped" \
    --target-maintenance-guard-command "$work/assert-prod-keycloak-stopped" \
    --operator-production-approval
  python3 "$identity_tool" verify \
    --source-pg-service ax41-dev-keycloak \
    --target-pg-service ax41-prod-keycloak \
    --student-subject-file "$subject_file"
done <"$work/missing-subjects.txt"

python3 "$identity_tool" export-inventory \
  --target-pg-service ax41-prod-keycloak \
  --output "$secure_dir/prod-keycloak-subjects" >/dev/null

platform_commit="$(ssh_dev "$kube -n playsay-dev get deployment api-gateway -o jsonpath='{.metadata.labels.playsay\\.io/source-commit}'" || true)"
[[ -n "$platform_commit" ]] || platform_commit="accepted-dev-runtime-unknown"
infra_commit="$(git -C "$infra_repo" rev-parse HEAD)"

echo "Creating fresh accepted dev-to-prod learning bundle..."
export_json="$(python3 "$learning_tool" export \
  --pg-service ax41-dev-playsay \
  --maria-subject-file "$secure_dir/maria.subject" \
  --s3-alias ax41-dev \
  --s3-bucket playsay-material-assets \
  --public-key "$public_key" \
  --output-dir "$secure_dir/bundles/dev-to-prod" \
  --platform-commit "$platform_commit" \
  --infra-commit "$infra_commit")"
bundle_id="$(jq -r '.bundleId' <<<"$export_json")"
manifest_sha="$(jq -r '.manifestSha256' <<<"$export_json")"
bundle="$secure_dir/bundles/dev-to-prod/$bundle_id.tar.gz.enc"
bundle_key="$secure_dir/bundles/dev-to-prod/$bundle_id.key.enc"
transport="$secure_dir/bundles/dev-to-prod/$bundle_id.transport.sha256"

python3 "$learning_tool" verify-bundle \
  --bundle "$bundle" --encrypted-key "$bundle_key" --private-key "$private_key" \
  --transport-checksums "$transport" >/dev/null
python3 "$learning_tool" plan \
  --pg-service ax41-prod-playsay \
  --bundle "$bundle" --encrypted-key "$bundle_key" --private-key "$private_key" \
  --transport-checksums "$transport" \
  --target-subjects-file "$secure_dir/prod-keycloak-subjects" \
  --output "$secure_dir/reports/$bundle_id.plan.json"

python3 "$learning_tool" apply \
  --pg-service ax41-prod-playsay \
  --s3-alias ax41-prod --s3-bucket playsay-material-assets \
  --bundle "$bundle" --encrypted-key "$bundle_key" --private-key "$private_key" \
  --transport-checksums "$transport" \
  --target-subjects-file "$secure_dir/prod-keycloak-subjects" \
  --backup-dir "$secure_dir/backups/prod-learning" \
  --backup-public-key "$public_key" \
  --maintenance-guard-command "$work/assert-prod-maintenance" \
  --confirm-manifest-sha256 "$manifest_sha" \
  --operator-production-approval

python3 "$learning_tool" verify-target \
  --pg-service ax41-prod-playsay \
  --s3-alias ax41-prod --s3-bucket playsay-material-assets \
  --bundle "$bundle" --encrypted-key "$bundle_key" --private-key "$private_key" \
  --transport-checksums "$transport" \
  --target-subjects-file "$secure_dir/prod-keycloak-subjects"

restore_replicas
echo "Waiting for public production endpoints..."
endpoints_ok=false
for _ in {1..60}; do
  if curl -fsS https://online.honey.school/ >/dev/null \
    && curl -fsS https://key.honey.school/ >/dev/null \
    && curl -fsS https://ops.honey.school/keycloak/realms/playsay/.well-known/openid-configuration >/dev/null; then
    echo "Production endpoints OK"
    endpoints_ok=true
    break
  fi
  sleep 5
done
[[ "$endpoints_ok" == true ]] || die "production endpoints did not recover in time"

echo "Production migration complete. Bundle ID: $bundle_id"
