#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
[[ "$(hostname -s)" == "playsay-prod" ]] || { echo "unexpected guest" >&2; exit 1; }
[[ $# == 1 && "$1" =~ ^/var/backups/playsay/stack-upgrade-prod-[0-9]{8}T[0-9]{6}Z$ ]] || {
  echo "expected the task-owned protected PROD backup directory" >&2; exit 1;
}
backup="$1"
test -d "$backup"
( cd "$backup"; sha256sum --check --status SHA256SUMS )
identity_jdbc="$(kubectl -n keycloak get statefulset keycloak -o json | jq -er '.spec.template.spec.containers[] | select(.name == "keycloak") | .env[] | select(.name == "KC_DB_URL") | .value')"
[[ "$identity_jdbc" == 'jdbc:postgresql://keycloak-postgresql:5432/bitnami_keycloak' ]] || {
  echo "restore comparison requires the reviewed Bitnami identity source" >&2; exit 1;
}

pod="stack-restore-$(date -u +%m%d%H%M%S)-$$"
image="ghcr.io/cloudnative-pg/postgresql@sha256:6ae4a22c14bdc66e5feaafd38d12c3956fabf9ce9582189e6aa4ee767d981d1b"
created=false
cleanup() {
  if [[ "$created" == true ]]; then
    owner="$(kubectl -n playsay-data get pod "$pod" -o jsonpath='{.metadata.labels.playsay-task}' 2>/dev/null || true)"
    if [[ "$owner" == "$pod" ]]; then
      kubectl -n playsay-data delete pod "$pod" --wait=true --timeout=60s >/dev/null
    else
      echo "temporary restore pod ownership not verified: $pod" >&2
    fi
  fi
}
trap cleanup EXIT

overrides="$(python3 - "$pod" "$image" <<'PY'
import json,sys
name,image=sys.argv[1:]
command="umask 077; initdb -D /tmp/pgdata --auth=trust --encoding=UTF8 --locale=C -U postgres >/tmp/initdb.log; exec postgres -D /tmp/pgdata -c listen_addresses= -c unix_socket_directories=/tmp -c shared_buffers=32MB -c max_connections=10"
print(json.dumps({"metadata":{"labels":{"playsay-task":name}},"spec":{
  "automountServiceAccountToken":False,
  "securityContext":{"runAsNonRoot":True,"runAsUser":26,"runAsGroup":26,"fsGroup":26},
  "volumes":[{"name":"scratch","emptyDir":{"sizeLimit":"1Gi"}}],
  "containers":[{"name":"restore","image":image,"imagePullPolicy":"IfNotPresent",
    "command":["sh","-ec",command],
    "volumeMounts":[{"name":"scratch","mountPath":"/tmp"}],
    "securityContext":{"allowPrivilegeEscalation":False,"capabilities":{"drop":["ALL"]}},
    "resources":{"requests":{"cpu":"50m","memory":"128Mi","ephemeral-storage":"128Mi"},"limits":{"cpu":"500m","memory":"512Mi","ephemeral-storage":"2Gi"}}}]
}}))
PY
)"
kubectl -n playsay-data run "$pod" --image="$image" --restart=Never --overrides="$overrides" >/dev/null
created=true
kubectl -n playsay-data wait --for=condition=Ready "pod/$pod" --timeout=120s >/dev/null
ready=false
for attempt in {1..40}; do
  if kubectl -n playsay-data exec "$pod" -- pg_isready -h /tmp -U postgres >/dev/null 2>&1; then ready=true; break; fi
  sleep 2
done
[[ "$ready" == true ]] || { echo "isolated restore PostgreSQL did not become ready" >&2; exit 1; }
primary="$(kubectl -n playsay-data get cluster playsay-postgres -o jsonpath='{.status.currentPrimary}')"
[[ -n "$primary" ]] || { echo "application database primary unavailable" >&2; exit 1; }
table_query="select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p')"
version="$(kubectl -n playsay-data exec "$pod" -- psql -X -h /tmp -U postgres -d postgres -Atq -c 'show server_version')"
encoding="$(kubectl -n playsay-data exec "$pod" -- psql -X -h /tmp -U postgres -d postgres -Atq -c 'show server_encoding')"
[[ "$encoding" == UTF8 ]] || { echo "isolated restore has unexpected encoding" >&2; exit 1; }
printf 'isolated_postgresql_version=%s\n' "$version"

for database in playsay keyboard worksheet_import keycloak; do
  file="$database.dump"
  timeout 180s kubectl -n playsay-data cp "$backup/$file" "$pod:/tmp/$file" -c restore
  expected="$(sha256sum "$backup/$file" | cut -d' ' -f1)"
  actual="$(kubectl -n playsay-data exec "$pod" -- sha256sum "/tmp/$file" | cut -d' ' -f1)"
  [[ "$actual" == "$expected" ]] || { echo "isolated restore copy checksum mismatch" >&2; exit 1; }
  kubectl -n playsay-data exec "$pod" -- createdb -h /tmp -U postgres "$database"
  if ! python3 - "$pod" "$database" "$file" <<'PY'
import subprocess, sys
pod, database, archive = sys.argv[1:]
command = ['kubectl', '-n', 'playsay-data', 'exec', pod, '--', 'pg_restore',
           '--exit-on-error', '--no-owner', '--no-privileges', '-h', '/tmp',
           '-U', 'postgres', '-d', database, '/tmp/' + archive]
try:
    result = subprocess.run(command, capture_output=True, text=True, errors='replace', timeout=300)
except subprocess.TimeoutExpired:
    print('isolated restore timed out', file=sys.stderr)
    raise SystemExit(1)
if result.returncode:
    # COPY error details can contain user rows. Never persist or print them.
    reason = 'varchar length mismatch' if 'value too long for type character varying' in result.stderr else 'restore error'
    print('isolated restore failed: ' + reason, file=sys.stderr)
    raise SystemExit(1)
PY
  then
    echo "isolated restore failed for $database; no row details retained" >&2
    exit 1
  fi
  count="$(kubectl -n playsay-data exec "$pod" -- psql -X -h /tmp -U postgres -d "$database" -Atq -c "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p')")"
  [[ "$count" =~ ^[0-9]+$ && "$count" -gt 0 ]] || { echo "restored schema is empty" >&2; exit 1; }
  if [[ "$database" == keycloak ]]; then
    source_count="$(kubectl -n keycloak exec keycloak-postgresql-0 -c postgresql -- sh -lc \
      'PGPASSWORD="$(cat "$POSTGRES_PASSWORD_FILE")" /opt/bitnami/postgresql/bin/psql -X -U "$POSTGRES_USER" -d "$POSTGRES_DATABASE" -Atq -c "$1"' -- "$table_query")"
  else
    source_count="$(kubectl -n playsay-data exec "$primary" -c postgres -- psql -X -U postgres -d "$database" -Atq -c "$table_query")"
  fi
  [[ "$source_count" == "$count" ]] || { echo "restored table count differs for $database" >&2; exit 1; }
  printf '%s restored_public_tables=%s source_tables_match=true\n' "$database" "$count"
done
echo "isolated_restore=ok"
