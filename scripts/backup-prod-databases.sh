#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# PROD only. Run on the established playsay-prod guest as root; no credentials
# or database contents are copied into the workspace or printed.
[[ "$(hostname -s)" == "playsay-prod" ]] || { echo "unexpected guest" >&2; exit 1; }
for tool in kubectl jq sha256sum timeout; do command -v "$tool" >/dev/null; done
kubectl get --raw=/readyz >/dev/null
primary="$(kubectl -n playsay-data get cluster playsay-postgres -o json | jq -er '.status.currentPrimary')"
identity_state="$(kubectl -n keycloak get statefulset keycloak -o json)"
jq -e '(.status.observedGeneration // 0) >= .metadata.generation and (.status.readyReplicas // 0) == (.spec.replicas // 1)' <<< "$identity_state" >/dev/null || {
  echo "identity workload has not converged; refusing to select a backup source" >&2; exit 1;
}
identity_replicas="$(jq -er '.spec.replicas // 1' <<< "$identity_state")"
identity_jdbc="$(jq -er '.spec.template.spec.containers[] | select(.name == "keycloak") | .env[] | select(.name == "KC_DB_URL") | .value' <<< "$identity_state")"
kubectl -n keycloak get pods -o json | jq -e --arg url "$identity_jdbc" --argjson expected "$identity_replicas" '
  [.items[] | select(any(.metadata.ownerReferences[]?; .kind == "StatefulSet" and .name == "keycloak"))] as $pods |
  ($pods | length) == $expected and all($pods[];
    .status.phase == "Running" and
    any(.status.containerStatuses[]?; .name == "keycloak" and .ready == true) and
    any(.spec.containers[] | select(.name == "keycloak") | .env[]?; .name == "KC_DB_URL" and .value == $url))' >/dev/null || {
  echo "identity pods do not match the reviewed active JDBC endpoint" >&2; exit 1;
}
case "$identity_jdbc" in
  jdbc:postgresql://keycloak-postgresql:5432/bitnami_keycloak)
    identity_kind=bitnami
    keycloak_db="$(kubectl -n keycloak get pods -o json | jq -er '[.items[] | select(.status.phase == "Running") | select(any(.spec.containers[]; .name == "postgresql")) | .metadata.name] | if length == 1 then .[0] else error("identity database pod is not unique") end')"
    ;;
  jdbc:postgresql://keycloak-postgres-upgrade-rw:5432/bitnami_keycloak)
    [[ "$identity_replicas" == 1 ]] || { echo "new identity database backup requires a running verified Keycloak" >&2; exit 1; }
    identity_kind=cnpg
    keycloak_db="$(kubectl -n keycloak get cluster keycloak-postgres-upgrade -o json | jq -er '.status.currentPrimary')"
    ;;
  *) echo "active identity database does not match a reviewed PROD endpoint" >&2; exit 1 ;;
esac
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup="/var/backups/playsay/stack-upgrade-prod-${stamp}"
mkdir -m 700 "$backup"
printf 'Backup did not complete validation. Do not use.\n' > "$backup/INCOMPLETE.txt"

for database in playsay keyboard worksheet_import; do
  timeout 180s kubectl -n playsay-data exec "$primary" -c postgres -- \
    pg_dump --format=custom --no-owner --no-privileges -U postgres -d "$database" \
    > "$backup/$database.dump"
  test -s "$backup/$database.dump"
done
if [[ "$identity_kind" == bitnami ]]; then
  timeout 180s kubectl -n keycloak exec "$keycloak_db" -c postgresql -- sh -lc \
    'PGPASSWORD="$(cat "$POSTGRES_PASSWORD_FILE")" /opt/bitnami/postgresql/bin/pg_dump --format=custom --no-owner --no-privileges -U "$POSTGRES_USER" -d "$POSTGRES_DATABASE"' \
    > "$backup/keycloak.dump"
else
  timeout 180s kubectl -n keycloak exec "$keycloak_db" -c postgres -- \
    pg_dump --format=custom --no-owner --no-privileges -U postgres -d bitnami_keycloak \
    > "$backup/keycloak.dump"
fi
test -s "$backup/keycloak.dump"

# Validate a private temporary file in the matching PostgreSQL 17 container.
# `kubectl exec -i` can fail to close stdin on this cluster; use `cp` instead.
validation_namespace=""
validation_pod=""
validation_container=""
validation_path=""
cleanup_validation() {
  if [[ -n "$validation_path" ]]; then
    kubectl -n "$validation_namespace" exec "$validation_pod" -c "$validation_container" -- \
      unlink "$validation_path" >/dev/null 2>&1 || true
  fi
}
trap cleanup_validation EXIT
for database in playsay keyboard worksheet_import; do
  validation_namespace=playsay-data
  validation_pod="$primary"
  validation_container=postgres
  validation_path="/controller/run/stack-upgrade-${stamp}-${database}.dump"
  timeout 180s kubectl cp "$backup/$database.dump" "$validation_namespace/$validation_pod:$validation_path" -c "$validation_container"
  timeout 120s kubectl -n "$validation_namespace" exec "$validation_pod" -c "$validation_container" -- pg_restore --list "$validation_path" > "$backup/$database.catalog"
  test "$(grep -c ' TABLE DATA ' "$backup/$database.catalog")" -gt 0
  cleanup_validation
  validation_path=""
done
validation_namespace=keycloak
validation_pod="$keycloak_db"
if [[ "$identity_kind" == bitnami ]]; then
  validation_container=postgresql
  validation_path="/tmp/stack-upgrade-${stamp}-keycloak.dump"
else
  validation_container=postgres
  validation_path="/controller/run/stack-upgrade-${stamp}-keycloak.dump"
fi
timeout 180s kubectl cp "$backup/keycloak.dump" "$validation_namespace/$validation_pod:$validation_path" -c "$validation_container"
if [[ "$identity_kind" == bitnami ]]; then
  timeout 120s kubectl -n "$validation_namespace" exec "$validation_pod" -c "$validation_container" -- /opt/bitnami/postgresql/bin/pg_restore --list "$validation_path" > "$backup/keycloak.catalog"
else
  timeout 120s kubectl -n "$validation_namespace" exec "$validation_pod" -c "$validation_container" -- pg_restore --list "$validation_path" > "$backup/keycloak.catalog"
fi
test "$(grep -c ' TABLE DATA ' "$backup/keycloak.catalog")" -gt 0
cleanup_validation
validation_path=""
(
  cd "$backup"
  sha256sum playsay.dump keyboard.dump worksheet_import.dump keycloak.dump > SHA256SUMS
  sha256sum --check --status SHA256SUMS
)
rm "$backup/INCOMPLETE.txt"
printf 'backup=%s\nidentity_source=%s\ndumps=4\narchive_catalogs=4\nchecksums=ok\n' "$backup" "$identity_kind"
