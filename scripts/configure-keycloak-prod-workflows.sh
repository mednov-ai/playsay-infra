#!/usr/bin/env bash
set -Eeuo pipefail

: "${KEYCLOAK_OPERATOR_USERNAME:?Set KEYCLOAK_OPERATOR_USERNAME to the existing production operator}"

KUBECONFIG_PATH="${KUBECONFIG_PATH:-/etc/rancher/k3s/k3s.yaml}"
KEYCLOAK_NAMESPACE="${KEYCLOAK_NAMESPACE:-keycloak}"
KEYCLOAK_ADMIN_SECRET="${KEYCLOAK_ADMIN_SECRET:-keycloak-admin}"
KEYCLOAK_REALM="${KEYCLOAK_REALM:-workforce}"
KEYCLOAK_CONTAINER="${KEYCLOAK_CONTAINER:-keycloak}"
KEYCLOAK_SERVER="${KEYCLOAK_SERVER:-http://localhost:8080/keycloak}"
KCADM_PATH="${KCADM_PATH:-/opt/bitnami/keycloak/bin/kcadm.sh}"
KCADM_CONFIG="${KCADM_CONFIG:-/tmp/kcadm-argo-workflows.config}"
WORKFLOWS_CLIENT_ID="${WORKFLOWS_CLIENT_ID:-playsay-release-workflows}"
WORKFLOWS_GROUP="${WORKFLOWS_GROUP:-release-operators}"
WORKFLOWS_ORIGIN="${WORKFLOWS_ORIGIN:-https://workflows.ops.honey.school}"
WORKFLOWS_SECRET_NAMESPACE="${WORKFLOWS_SECRET_NAMESPACE:-argo-workflows-system}"
WORKFLOWS_SECRET_NAME="${WORKFLOWS_SECRET_NAME:-playsay-release-sso}"

kubectl_cmd=(sudo env "KUBECONFIG=${KUBECONFIG_PATH}" kubectl)
pod="$(
  "${kubectl_cmd[@]}" -n "${KEYCLOAK_NAMESPACE}" get pods \
    -l app.kubernetes.io/name=keycloak \
    -o jsonpath='{.items[0].metadata.name}'
)"
[[ -n "${pod}" ]] || {
  echo "Production Keycloak pod was not found." >&2
  exit 1
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

group_json="$(kcadm get groups -r "${KEYCLOAK_REALM}" -q "search=${WORKFLOWS_GROUP}")"
group_id="$(jq -r --arg name "${WORKFLOWS_GROUP}" '.[] | select(.name == $name) | .id' <<<"${group_json}" | head -n 1)"
if [[ -z "${group_id}" ]]; then
  printf '%s' "$(jq -cn --arg name "${WORKFLOWS_GROUP}" '{name:$name}')" |
    "${kubectl_cmd[@]}" -n "${KEYCLOAK_NAMESPACE}" exec -i -c "${KEYCLOAK_CONTAINER}" "${pod}" -- \
      "${KCADM_PATH}" create groups --config "${KCADM_CONFIG}" -r "${KEYCLOAK_REALM}" -f - >/dev/null
  group_json="$(kcadm get groups -r "${KEYCLOAK_REALM}" -q "search=${WORKFLOWS_GROUP}")"
  group_id="$(jq -r --arg name "${WORKFLOWS_GROUP}" '.[] | select(.name == $name) | .id' <<<"${group_json}" | head -n 1)"
fi
[[ -n "${group_id}" ]] || exit 1

user_json="$(kcadm get users -r "${KEYCLOAK_REALM}" -q "username=${KEYCLOAK_OPERATOR_USERNAME}" -q exact=true)"
user_id="$(jq -r 'if length == 1 then .[0].id else empty end' <<<"${user_json}")"
[[ -n "${user_id}" ]] || {
  echo "Expected exactly one existing Keycloak operator ${KEYCLOAK_OPERATOR_USERNAME}." >&2
  exit 2
}
kcadm update "users/${user_id}/groups/${group_id}" -r "${KEYCLOAK_REALM}" -n >/dev/null

client_json="$(kcadm get clients -r "${KEYCLOAK_REALM}" -q "clientId=${WORKFLOWS_CLIENT_ID}")"
client_id="$(jq -r 'if length == 1 then .[0].id else empty end' <<<"${client_json}")"
client_payload="$(
  jq -cn \
    --arg clientId "${WORKFLOWS_CLIENT_ID}" \
    --arg origin "${WORKFLOWS_ORIGIN}" \
    '{
      clientId:$clientId,
      enabled:true,
      protocol:"openid-connect",
      publicClient:false,
      standardFlowEnabled:true,
      implicitFlowEnabled:false,
      directAccessGrantsEnabled:false,
      serviceAccountsEnabled:false,
      consentRequired:false,
      frontchannelLogout:true,
      redirectUris:[($origin + "/oauth2/callback")],
      webOrigins:[$origin],
      defaultClientScopes:["web-origins","acr","profile","roles","email"],
      optionalClientScopes:[],
      attributes:{
        "pkce.code.challenge.method":"S256",
        "post.logout.redirect.uris":($origin + "/*")
      },
      protocolMappers:[
        {
          name:"release-operator-groups",
          protocol:"openid-connect",
          protocolMapper:"oidc-group-membership-mapper",
          consentRequired:false,
          config:{
            "full.path":"false",
            "id.token.claim":"true",
            "access.token.claim":"true",
            "userinfo.token.claim":"true",
            "claim.name":"groups"
          }
        },
        {
          name:"client-audience",
          protocol:"openid-connect",
          protocolMapper:"oidc-audience-mapper",
          consentRequired:false,
          config:{
            "included.client.audience":$clientId,
            "id.token.claim":"false",
            "access.token.claim":"true",
            "introspection.token.claim":"true"
          }
        }
      ]
    }'
)"
if [[ -n "${client_id}" ]]; then
  printf '%s' "${client_payload}" |
    "${kubectl_cmd[@]}" -n "${KEYCLOAK_NAMESPACE}" exec -i -c "${KEYCLOAK_CONTAINER}" "${pod}" -- \
      "${KCADM_PATH}" update "clients/${client_id}" --config "${KCADM_CONFIG}" \
        -r "${KEYCLOAK_REALM}" -f - >/dev/null
else
  printf '%s' "${client_payload}" |
    "${kubectl_cmd[@]}" -n "${KEYCLOAK_NAMESPACE}" exec -i -c "${KEYCLOAK_CONTAINER}" "${pod}" -- \
      "${KCADM_PATH}" create clients --config "${KCADM_CONFIG}" \
        -r "${KEYCLOAK_REALM}" -f - >/dev/null
  client_json="$(kcadm get clients -r "${KEYCLOAK_REALM}" -q "clientId=${WORKFLOWS_CLIENT_ID}")"
  client_id="$(jq -r 'if length == 1 then .[0].id else empty end' <<<"${client_json}")"
fi
[[ -n "${client_id}" ]] || exit 1

client_secret="$(kcadm get "clients/${client_id}/client-secret" -r "${KEYCLOAK_REALM}" | jq -r '.value // empty')"
[[ -n "${client_secret}" ]] || {
  echo "Keycloak did not return the Workflows client secret." >&2
  exit 1
}
"${kubectl_cmd[@]}" create namespace "${WORKFLOWS_SECRET_NAMESPACE}" --dry-run=client -o yaml |
  "${kubectl_cmd[@]}" apply -f - >/dev/null
"${kubectl_cmd[@]}" -n "${WORKFLOWS_SECRET_NAMESPACE}" create secret generic "${WORKFLOWS_SECRET_NAME}" \
  --from-literal=client-id="${WORKFLOWS_CLIENT_ID}" \
  --from-literal=client-secret="${client_secret}" \
  --dry-run=client -o yaml |
  "${kubectl_cmd[@]}" apply -f - >/dev/null
unset client_secret

members="$(kcadm get "groups/${group_id}/members" -r "${KEYCLOAK_REALM}")"
jq -e --arg username "${KEYCLOAK_OPERATOR_USERNAME}" \
  '.[] | select(.username == $username)' <<<"${members}" >/dev/null
echo "Keycloak client ${WORKFLOWS_CLIENT_ID} and release-operators membership are configured."
