#!/usr/bin/env bash
set -euo pipefail

KUBECONFIG_PATH="${KUBECONFIG_PATH:-/etc/rancher/k3s/k3s.yaml}"
KEYCLOAK_NAMESPACE="${KEYCLOAK_NAMESPACE:-keycloak}"
KEYCLOAK_ADMIN_SECRET="${KEYCLOAK_ADMIN_SECRET:-keycloak-admin}"
KEYCLOAK_REALM="${KEYCLOAK_REALM:-playsay}"
REGISTRATION_CLIENT_ID="${KEYCLOAK_REGISTRATION_CLIENT_ID:-playsay-registration-service}"

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required tool: $1" >&2
    exit 1
  fi
}

require_tool base64
require_tool curl
require_tool jq

kubectl_cmd=(sudo env "KUBECONFIG=${KUBECONFIG_PATH}" kubectl)

admin_password="$(
  "${kubectl_cmd[@]}" -n "${KEYCLOAK_NAMESPACE}" get secret "${KEYCLOAK_ADMIN_SECRET}" \
    -o jsonpath='{.data.admin-password}' | base64 -d
)"
keycloak_ip="$(
  "${kubectl_cmd[@]}" -n "${KEYCLOAK_NAMESPACE}" get service keycloak \
    -o jsonpath='{.spec.clusterIP}'
)"
keycloak_url="http://${keycloak_ip}/keycloak"
admin_token="$(
  curl --connect-timeout 5 --max-time 20 -fsS -X POST \
    "${keycloak_url}/realms/master/protocol/openid-connect/token" \
    --data-urlencode client_id=admin-cli \
    --data-urlencode username=admin \
    --data-urlencode "password=${admin_password}" \
    --data-urlencode grant_type=password | jq -er '.access_token'
)"
unset admin_password

client_uuid() {
  local client_id="$1"
  curl --connect-timeout 5 --max-time 20 -fsS -G \
    -H "Authorization: Bearer ${admin_token}" \
    --data-urlencode "clientId=${client_id}" \
    "${keycloak_url}/admin/realms/${KEYCLOAK_REALM}/clients" \
    | jq -er --arg client_id "${client_id}" \
      'if length == 1 then .[0].id else error("Expected exactly one client " + $client_id) end'
}

registration_uuid="$(client_uuid "${REGISTRATION_CLIENT_ID}")"
realm_management_uuid="$(client_uuid realm-management)"
service_user_id="$(
  curl --connect-timeout 5 --max-time 20 -fsS \
    -H "Authorization: Bearer ${admin_token}" \
    "${keycloak_url}/admin/realms/${KEYCLOAK_REALM}/clients/${registration_uuid}/service-account-user" \
    | jq -er '.id'
)"

role_mappings_url="${keycloak_url}/admin/realms/${KEYCLOAK_REALM}/users/${service_user_id}/role-mappings/clients/${realm_management_uuid}"

for role in view-users manage-users view-realm; do
  mappings="$(
    curl --connect-timeout 5 --max-time 20 -fsS \
      -H "Authorization: Bearer ${admin_token}" "${role_mappings_url}"
  )"
  if ! jq -e --arg role "${role}" '.[] | select(.name == $role)' <<<"${mappings}" >/dev/null; then
    role_payload="$(
      curl --connect-timeout 5 --max-time 20 -fsS \
        -H "Authorization: Bearer ${admin_token}" \
        "${keycloak_url}/admin/realms/${KEYCLOAK_REALM}/clients/${realm_management_uuid}/roles/${role}"
    )"
    jq -n --argjson role "${role_payload}" '[$role]' \
      | curl --connect-timeout 5 --max-time 20 -fsS -X POST \
        -H "Authorization: Bearer ${admin_token}" \
        -H 'Content-Type: application/json' \
        -d @- "${role_mappings_url}" >/dev/null
  fi
done

verified_mappings="$(
  curl --connect-timeout 5 --max-time 20 -fsS \
    -H "Authorization: Bearer ${admin_token}" "${role_mappings_url}"
)"
for role in view-users manage-users view-realm; do
  jq -e --arg role "${role}" '.[] | select(.name == $role)' \
    <<<"${verified_mappings}" >/dev/null
done

unset admin_token mappings role_payload verified_mappings
echo "Production registration service account has the required Keycloak realm-management roles."
