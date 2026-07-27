#!/usr/bin/env bash
set -Eeuo pipefail

KUBECONFIG_PATH="${KUBECONFIG_PATH:-${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}}"
KEYCLOAK_NAMESPACE="${KEYCLOAK_NAMESPACE:-keycloak}"
KEYCLOAK_ADMIN_SECRET="${KEYCLOAK_ADMIN_SECRET:-keycloak-admin}"
KEYCLOAK_CONTAINER="${KEYCLOAK_CONTAINER:-keycloak}"
KEYCLOAK_SERVER="${KEYCLOAK_SERVER:-http://localhost:8080/keycloak}"
KCADM_PATH="${KCADM_PATH:-/opt/bitnami/keycloak/bin/kcadm.sh}"
KCADM_CONFIG="${KCADM_CONFIG:-/tmp/kcadm-dev-workforce-broker.config}"
DEV_REALM="${DEV_REALM:-playsay}"
BROKER_ALIAS="${BROKER_ALIAS:-workforce}"
BROKER_SECRET="${BROKER_SECRET:-workforce-broker-oidc}"
WORKFORCE_ISSUER="${WORKFORCE_ISSUER:-https://ops.honey.school/keycloak/realms/workforce}"

for command_name in kubectl jq base64; do
  command -v "${command_name}" >/dev/null || {
    echo "Missing required command: ${command_name}" >&2
    exit 2
  }
done
[[ "${DEV_REALM}" == "playsay" && "${BROKER_ALIAS}" == "workforce" ]] || {
  echo "The dev realm and workforce broker alias are fixed." >&2
  exit 2
}

kubectl_cmd=(kubectl --kubeconfig "${KUBECONFIG_PATH}")
pod="$(
  "${kubectl_cmd[@]}" -n "${KEYCLOAK_NAMESPACE}" get pods \
    -l app.kubernetes.io/name=keycloak \
    -o jsonpath='{.items[0].metadata.name}'
)"
[[ -n "${pod}" ]] || {
  echo "Keycloak pod was not found in ${KEYCLOAK_NAMESPACE}." >&2
  exit 3
}

admin_password="$(
  "${kubectl_cmd[@]}" -n "${KEYCLOAK_NAMESPACE}" get secret "${KEYCLOAK_ADMIN_SECRET}" \
    -o jsonpath='{.data.admin-password}' |
    base64 -d
)"
"${kubectl_cmd[@]}" -n "${KEYCLOAK_NAMESPACE}" exec -c "${KEYCLOAK_CONTAINER}" "${pod}" -- \
  "${KCADM_PATH}" config credentials \
    --config "${KCADM_CONFIG}" \
    --server "${KEYCLOAK_SERVER}" \
    --realm master \
    --user admin \
    --password "${admin_password}" >/dev/null
unset admin_password

kcadm() {
  "${kubectl_cmd[@]}" -n "${KEYCLOAK_NAMESPACE}" exec -c "${KEYCLOAK_CONTAINER}" "${pod}" -- \
    "${KCADM_PATH}" "$@" --config "${KCADM_CONFIG}"
}

for required_role in TEACHER ADMIN; do
  kcadm get "roles/${required_role}" -r "${DEV_REALM}" >/dev/null 2>&1 || {
    echo "Required dev realm role is missing: ${required_role}." >&2
    exit 3
  }
done

client_id="$(
  "${kubectl_cmd[@]}" -n "${KEYCLOAK_NAMESPACE}" get secret "${BROKER_SECRET}" \
    -o jsonpath='{.data.client-id}' |
    base64 -d
)"
client_secret="$(
  "${kubectl_cmd[@]}" -n "${KEYCLOAK_NAMESPACE}" get secret "${BROKER_SECRET}" \
    -o jsonpath='{.data.client-secret}' |
    base64 -d
)"
[[ "${client_id}" == "playsay-dev-workforce-broker" && -n "${client_secret}" ]] || {
  echo "${KEYCLOAK_NAMESPACE}/${BROKER_SECRET} is missing the expected OIDC client." >&2
  exit 3
}

idp_payload="$(
  jq -cn \
    --arg alias "${BROKER_ALIAS}" \
    --arg issuer "${WORKFORCE_ISSUER}" \
    --arg clientId "${client_id}" \
    --arg clientSecret "${client_secret}" \
    '{
      alias:$alias,
      displayName:"Play&Say Workforce",
      providerId:"oidc",
      enabled:true,
      updateProfileFirstLoginMode:"on",
      trustEmail:false,
      storeToken:false,
      addReadTokenRoleOnCreate:false,
      authenticateByDefault:false,
      linkOnly:false,
      firstBrokerLoginFlowAlias:"first broker login",
      config:{
        authorizationUrl:($issuer + "/protocol/openid-connect/auth"),
        tokenUrl:($issuer + "/protocol/openid-connect/token"),
        logoutUrl:($issuer + "/protocol/openid-connect/logout"),
        userInfoUrl:($issuer + "/protocol/openid-connect/userinfo"),
        jwksUrl:($issuer + "/protocol/openid-connect/certs"),
        issuer:$issuer,
        clientId:$clientId,
        clientSecret:$clientSecret,
        clientAuthMethod:"client_secret_post",
        defaultScope:"openid profile email groups",
        syncMode:"FORCE",
        pkceEnabled:"true",
        pkceMethod:"S256",
        validateSignature:"true",
        useJwksUrl:"true",
        hideOnLoginPage:"false",
        disableUserInfo:"false",
        backchannelSupported:"false"
      }
    }'
)"

if kcadm get "identity-provider/instances/${BROKER_ALIAS}" -r "${DEV_REALM}" >/dev/null 2>&1; then
  printf '%s' "${idp_payload}" |
    "${kubectl_cmd[@]}" -n "${KEYCLOAK_NAMESPACE}" exec -i -c "${KEYCLOAK_CONTAINER}" "${pod}" -- \
      "${KCADM_PATH}" update "identity-provider/instances/${BROKER_ALIAS}" \
        --config "${KCADM_CONFIG}" -r "${DEV_REALM}" -f - >/dev/null
else
  printf '%s' "${idp_payload}" |
    "${kubectl_cmd[@]}" -n "${KEYCLOAK_NAMESPACE}" exec -i -c "${KEYCLOAK_CONTAINER}" "${pod}" -- \
      "${KCADM_PATH}" create identity-provider/instances \
        --config "${KCADM_CONFIG}" -r "${DEV_REALM}" -f - >/dev/null
fi
unset client_secret idp_payload

upsert_role_mapper() {
  local mapper_name="$1"
  local workforce_group="$2"
  local local_role="$3"
  local mapper_id
  local claims
  local payload

  claims="$(jq -cn --arg value "${workforce_group}" '[{key:"groups",value:$value}]')"
  payload="$(
    jq -cn \
      --arg name "${mapper_name}" \
      --arg alias "${BROKER_ALIAS}" \
      --arg claims "${claims}" \
      --arg role "${local_role}" \
      '{
        name:$name,
        identityProviderAlias:$alias,
        identityProviderMapper:"oidc-advanced-role-idp-mapper",
        config:{
          syncMode:"FORCE",
          claims:$claims,
          "are.claim.values.regex":"false",
          role:$role
        }
      }'
  )"
  mapper_id="$(
    kcadm get "identity-provider/instances/${BROKER_ALIAS}/mappers" -r "${DEV_REALM}" |
      jq -r --arg name "${mapper_name}" '.[] | select(.name == $name) | .id' |
      head -n 1
  )"
  if [[ -n "${mapper_id}" ]]; then
    printf '%s' "${payload}" |
      "${kubectl_cmd[@]}" -n "${KEYCLOAK_NAMESPACE}" exec -i -c "${KEYCLOAK_CONTAINER}" "${pod}" -- \
        "${KCADM_PATH}" update "identity-provider/instances/${BROKER_ALIAS}/mappers/${mapper_id}" \
          --config "${KCADM_CONFIG}" -r "${DEV_REALM}" -f - >/dev/null
  else
    printf '%s' "${payload}" |
      "${kubectl_cmd[@]}" -n "${KEYCLOAK_NAMESPACE}" exec -i -c "${KEYCLOAK_CONTAINER}" "${pod}" -- \
        "${KCADM_PATH}" create "identity-provider/instances/${BROKER_ALIAS}/mappers" \
          --config "${KCADM_CONFIG}" -r "${DEV_REALM}" -f - >/dev/null
  fi
}

upsert_role_mapper workforce-developers-teacher developers TEACHER
upsert_role_mapper workforce-platform-admins-teacher platform-admins TEACHER
upsert_role_mapper workforce-platform-admins-admin platform-admins ADMIN

echo "Dev realm now brokers the central workforce realm; production product identity remains isolated."
