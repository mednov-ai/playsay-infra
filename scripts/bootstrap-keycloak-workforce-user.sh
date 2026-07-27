#!/usr/bin/env bash
set -Eeuo pipefail

: "${WORKFORCE_USERNAME:?Set WORKFORCE_USERNAME}"
: "${WORKFORCE_EMAIL:?Set WORKFORCE_EMAIL}"

KUBECONFIG_PATH="${KUBECONFIG_PATH:-${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}}"
KEYCLOAK_NAMESPACE="${KEYCLOAK_NAMESPACE:-keycloak}"
KEYCLOAK_ADMIN_SECRET="${KEYCLOAK_ADMIN_SECRET:-keycloak-admin}"
KEYCLOAK_CONTAINER="${KEYCLOAK_CONTAINER:-keycloak}"
KEYCLOAK_SERVER="${KEYCLOAK_SERVER:-http://localhost:8080/keycloak}"
KCADM_PATH="${KCADM_PATH:-/opt/bitnami/keycloak/bin/kcadm.sh}"
KCADM_CONFIG="${KCADM_CONFIG:-/tmp/kcadm-workforce-user.config}"
WORKFORCE_REALM="${WORKFORCE_REALM:-workforce}"
BOOTSTRAP_SECRET_NAME="${BOOTSTRAP_SECRET_NAME:-workforce-bootstrap-${WORKFORCE_USERNAME}}"
WORKFORCE_GROUPS="${WORKFORCE_GROUPS:-developers}"

[[ "${WORKFORCE_USERNAME}" =~ ^[a-z0-9][a-z0-9._-]{1,62}$ ]] || {
  echo "WORKFORCE_USERNAME has an invalid format." >&2
  exit 2
}
[[ "${WORKFORCE_EMAIL}" =~ ^[^[:space:]@]+@[^[:space:]@]+$ ]] || {
  echo "WORKFORCE_EMAIL has an invalid format." >&2
  exit 2
}
for command_name in kubectl jq base64 openssl; do
  command -v "${command_name}" >/dev/null || exit 2
done

kubectl_cmd=(kubectl --kubeconfig "${KUBECONFIG_PATH}")
pod="$(
  "${kubectl_cmd[@]}" -n "${KEYCLOAK_NAMESPACE}" get pods \
    -l app.kubernetes.io/name=keycloak \
    -o jsonpath='{.items[0].metadata.name}'
)"
admin_password="$(
  "${kubectl_cmd[@]}" -n "${KEYCLOAK_NAMESPACE}" get secret "${KEYCLOAK_ADMIN_SECRET}" \
    -o jsonpath='{.data.admin-password}' |
    base64 -d
)"
"${kubectl_cmd[@]}" -n "${KEYCLOAK_NAMESPACE}" exec -c "${KEYCLOAK_CONTAINER}" "${pod}" -- \
  "${KCADM_PATH}" config credentials --config "${KCADM_CONFIG}" \
    --server "${KEYCLOAK_SERVER}" --realm master --user admin \
    --password "${admin_password}" >/dev/null
unset admin_password
kcadm() {
  "${kubectl_cmd[@]}" -n "${KEYCLOAK_NAMESPACE}" exec -c "${KEYCLOAK_CONTAINER}" "${pod}" -- \
    "${KCADM_PATH}" "$@" --config "${KCADM_CONFIG}"
}

created_user=false
user_id="$(
  kcadm get users -r "${WORKFORCE_REALM}" \
    -q "username=${WORKFORCE_USERNAME}" -q exact=true |
    jq -r 'if length == 1 then .[0].id else empty end'
)"
if [[ -z "${user_id}" ]]; then
  payload="$(
    jq -cn \
      --arg username "${WORKFORCE_USERNAME}" \
      --arg email "${WORKFORCE_EMAIL}" \
      '{
        username:$username,
        email:$email,
        enabled:true,
        emailVerified:true,
        requiredActions:["UPDATE_PASSWORD","CONFIGURE_TOTP","webauthn-register-passwordless"]
      }'
  )"
  printf '%s' "${payload}" |
    "${kubectl_cmd[@]}" -n "${KEYCLOAK_NAMESPACE}" exec -i -c "${KEYCLOAK_CONTAINER}" "${pod}" -- \
      "${KCADM_PATH}" create users --config "${KCADM_CONFIG}" \
        -r "${WORKFORCE_REALM}" -f - >/dev/null
  user_id="$(
    kcadm get users -r "${WORKFORCE_REALM}" \
      -q "username=${WORKFORCE_USERNAME}" -q exact=true |
      jq -r 'if length == 1 then .[0].id else empty end'
  )"
  temporary_password="$(openssl rand -base64 30 | tr -d '/+=' | cut -c1-24)"
  printf '%s' "$(jq -cn --arg value "${temporary_password}" \
    '{type:"password",temporary:true,value:$value}')" |
    "${kubectl_cmd[@]}" -n "${KEYCLOAK_NAMESPACE}" exec -i -c "${KEYCLOAK_CONTAINER}" "${pod}" -- \
      "${KCADM_PATH}" update "users/${user_id}/reset-password" \
        --config "${KCADM_CONFIG}" -r "${WORKFORCE_REALM}" -f - >/dev/null
  "${kubectl_cmd[@]}" -n "${KEYCLOAK_NAMESPACE}" create secret generic "${BOOTSTRAP_SECRET_NAME}" \
    --from-literal=username="${WORKFORCE_USERNAME}" \
    --from-literal=temporary-password="${temporary_password}" \
    --dry-run=client -o yaml |
    "${kubectl_cmd[@]}" apply -f - >/dev/null
  unset temporary_password
  created_user=true
fi
[[ -n "${user_id}" ]] || exit 3

IFS=',' read -r -a requested_groups <<<"${WORKFORCE_GROUPS}"
for group_name in "${requested_groups[@]}"; do
  case "${group_name}" in
    developers|release-operators|platform-admins) ;;
    *)
      echo "Unsupported workforce group: ${group_name}" >&2
      exit 2
      ;;
  esac
  group_id="$(
    kcadm get groups -r "${WORKFORCE_REALM}" -q "search=${group_name}" |
      jq -r --arg name "${group_name}" '.[] | select(.name == $name) | .id' |
      head -n 1
  )"
  [[ -n "${group_id}" ]] || {
    echo "Missing workforce group ${group_name}; configure the realm first." >&2
    exit 3
  }
  kcadm update "users/${user_id}/groups/${group_id}" -r "${WORKFORCE_REALM}" -n >/dev/null
done

echo "Workforce user ${WORKFORCE_USERNAME} is ready for passkey/TOTP enrollment."
if [[ "${created_user}" == "true" ]]; then
  echo "Retrieve the temporary credential from Secret ${KEYCLOAK_NAMESPACE}/${BOOTSTRAP_SECRET_NAME}; delete it after enrollment."
else
  echo "Existing user membership was reconciled; no bootstrap credential was created."
fi
