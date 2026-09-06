#!/usr/bin/env bash
set -euo pipefail

KUBECONFIG_PATH="${KUBECONFIG_PATH:-/etc/rancher/k3s/k3s.yaml}"
KEYCLOAK_NAMESPACE="${KEYCLOAK_NAMESPACE:-keycloak}"
KEYCLOAK_ADMIN_SECRET="${KEYCLOAK_ADMIN_SECRET:-keycloak-admin}"
KEYCLOAK_REALM="${KEYCLOAK_REALM:-playsay}"
KEYCLOAK_WEB_CLIENT_ID="${KEYCLOAK_WEB_CLIENT_ID:-playsay-web}"
KEYCLOAK_CONTAINER="${KEYCLOAK_CONTAINER:-keycloak}"
KEYCLOAK_SERVER="${KEYCLOAK_SERVER:-http://localhost:8080/keycloak}"
KCADM_PATH="${KCADM_PATH:-/opt/keycloak/bin/kcadm.sh}"
KCADM_CONFIG="${KCADM_CONFIG:-/tmp/kcadm-dev-rf-aliases.config}"

ONLINE_REDIRECT="https://dev.online.honeyschool.ru/*"
KEYBOARD_REDIRECT="https://dev.key.honeyschool.ru/*"
ONLINE_ORIGIN="https://dev.online.honeyschool.ru"
KEYBOARD_ORIGIN="https://dev.key.honeyschool.ru"

[[ "$(hostname -s)" == "playsay-dev" ]] || {
  echo "This script may run only on playsay-dev." >&2
  exit 1
}
[[ "$KUBECONFIG_PATH" == /etc/rancher/k3s/k3s.yaml && "$KEYCLOAK_REALM" == playsay \
   && "$KEYCLOAK_WEB_CLIENT_ID" == playsay-web && "$KEYCLOAK_SERVER" == http://localhost:8080/keycloak ]] || {
  echo "Refusing an alternate development identity boundary." >&2
  exit 1
}

kubectl_cmd=(sudo env "KUBECONFIG=${KUBECONFIG_PATH}" kubectl)

pod="$(
  "${kubectl_cmd[@]}" \
    -n "${KEYCLOAK_NAMESPACE}" \
    get pods \
    -l app.kubernetes.io/name=keycloak \
    -o jsonpath='{.items[0].metadata.name}'
)"

if [[ -z "${pod}" ]]; then
  echo "Keycloak pod was not found in namespace ${KEYCLOAK_NAMESPACE}." >&2
  exit 1
fi

cleanup() {
  "${kubectl_cmd[@]}" -n "$KEYCLOAK_NAMESPACE" exec -c "$KEYCLOAK_CONTAINER" "$pod" -- rm -f "$KCADM_CONFIG" >/dev/null 2>&1 || true
}
trap cleanup EXIT

admin_password="$(
  "${kubectl_cmd[@]}" \
    -n "${KEYCLOAK_NAMESPACE}" \
    get secret "${KEYCLOAK_ADMIN_SECRET}" \
    -o jsonpath='{.data.admin-password}' |
    base64 -d
)"

printf '%s\n' "$admin_password" | "${kubectl_cmd[@]}" -n "$KEYCLOAK_NAMESPACE" \
  exec -i -c "$KEYCLOAK_CONTAINER" "$pod" -- sh -c '
    IFS= read -r password
    umask 077
    "$1" config credentials --config "$2" --server "$3" --realm master --user admin --password "$password" >/dev/null
  ' sh "$KCADM_PATH" "$KCADM_CONFIG" "$KEYCLOAK_SERVER"
unset admin_password

client_json="$(
  "${kubectl_cmd[@]}" \
    -n "${KEYCLOAK_NAMESPACE}" \
    exec -c "${KEYCLOAK_CONTAINER}" "${pod}" -- \
    "${KCADM_PATH}" get clients \
      --config "${KCADM_CONFIG}" \
      -r "${KEYCLOAK_REALM}" \
      -q "clientId=${KEYCLOAK_WEB_CLIENT_ID}"
)"

client_count="$(jq 'length' <<<"${client_json}")"
if [[ "${client_count}" != "1" ]]; then
  echo "Expected one ${KEYCLOAK_WEB_CLIENT_ID} client, found ${client_count}." >&2
  exit 1
fi

client_uuid="$(jq -r '.[0].id' <<<"${client_json}")"
updated_client="$(
  jq -c \
    --arg online_redirect "${ONLINE_REDIRECT}" \
    --arg keyboard_redirect "${KEYBOARD_REDIRECT}" \
    --arg online_origin "${ONLINE_ORIGIN}" \
    --arg keyboard_origin "${KEYBOARD_ORIGIN}" \
    '
      .[0]
      | .redirectUris = (((.redirectUris // []) + [$online_redirect, $keyboard_redirect]) | unique)
      | .webOrigins = (((.webOrigins // []) + [$online_origin, $keyboard_origin]) | unique)
      | .attributes = (.attributes // {})
      | .attributes["post.logout.redirect.uris"] = (
          (
            (.attributes["post.logout.redirect.uris"] // "" | split("##"))
            + [$online_redirect, $keyboard_redirect]
          )
          | map(select(length > 0))
          | unique
          | join("##")
        )
    ' <<<"${client_json}"
)"

printf '%s' "${updated_client}" |
  "${kubectl_cmd[@]}" \
    -n "${KEYCLOAK_NAMESPACE}" \
    exec -i -c "${KEYCLOAK_CONTAINER}" "${pod}" -- \
    "${KCADM_PATH}" update "clients/${client_uuid}" \
      --config "${KCADM_CONFIG}" \
      -r "${KEYCLOAK_REALM}" \
      -f - \
    >/dev/null

verified_client="$(
  "${kubectl_cmd[@]}" \
    -n "${KEYCLOAK_NAMESPACE}" \
    exec -c "${KEYCLOAK_CONTAINER}" "${pod}" -- \
    "${KCADM_PATH}" get "clients/${client_uuid}" \
      --config "${KCADM_CONFIG}" \
      -r "${KEYCLOAK_REALM}"
)"

jq -e \
  --arg online_redirect "${ONLINE_REDIRECT}" \
  --arg keyboard_redirect "${KEYBOARD_REDIRECT}" \
  --arg online_origin "${ONLINE_ORIGIN}" \
  --arg keyboard_origin "${KEYBOARD_ORIGIN}" \
  '
    (.redirectUris | index($online_redirect)) != null
    and (.redirectUris | index($keyboard_redirect)) != null
    and (.webOrigins | index($online_origin)) != null
    and (.webOrigins | index($keyboard_origin)) != null
    and (.attributes["post.logout.redirect.uris"] | split("##") | index($online_redirect)) != null
    and (.attributes["post.logout.redirect.uris"] | split("##") | index($keyboard_redirect)) != null
  ' <<<"${verified_client}" \
  >/dev/null

echo "Development Keycloak accepts the two Russian application aliases."
