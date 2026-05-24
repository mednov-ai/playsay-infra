#!/usr/bin/env bash
set -euo pipefail

KEYCLOAK_URL="${KEYCLOAK_URL:-https://ops.play-and-say.ru:18443/keycloak}"
KEYCLOAK_NAMESPACE="${KEYCLOAK_NAMESPACE:-keycloak}"
KEYCLOAK_ADMIN_SECRET="${KEYCLOAK_ADMIN_SECRET:-keycloak-admin}"
KEYCLOAK_DEV_USERS_SECRET="${KEYCLOAK_DEV_USERS_SECRET:-keycloak-dev-users}"
REALM="${KEYCLOAK_REALM:-playsay}"
WEB_CLIENT_ID="${KEYCLOAK_WEB_CLIENT_ID:-playsay-web}"
API_CLIENT_ID="${KEYCLOAK_API_CLIENT_ID:-playsay-api}"

CURL_TLS_ARGS=()
if [[ "${KEYCLOAK_INSECURE_TLS:-true}" == "true" ]]; then
  CURL_TLS_ARGS=(-k)
fi

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required tool: $1" >&2
    exit 1
  fi
}

kc_curl() {
  curl "${CURL_TLS_ARGS[@]}" -fsS "$@"
}

kc_status() {
  curl "${CURL_TLS_ARGS[@]}" -sS -o /dev/null -w "%{http_code}" "$@"
}

admin_token() {
  local password
  password=$(kubectl -n "$KEYCLOAK_NAMESPACE" get secret "$KEYCLOAK_ADMIN_SECRET" -o jsonpath="{.data.admin-password}" | base64 -d)

  kc_curl -X POST "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
    -d client_id=admin-cli \
    -d username=admin \
    --data-urlencode password="$password" \
    -d grant_type=password | jq -r .access_token
}

generate_password() {
  openssl rand -hex 12
}

ensure_dev_user_secret() {
  if kubectl -n "$KEYCLOAK_NAMESPACE" get secret "$KEYCLOAK_DEV_USERS_SECRET" >/dev/null 2>&1; then
    return
  fi

  kubectl -n "$KEYCLOAK_NAMESPACE" create secret generic "$KEYCLOAK_DEV_USERS_SECRET" \
    --from-literal=student-demo-password="$(generate_password)" \
    --from-literal=teacher-demo-password="$(generate_password)" \
    --from-literal=admin-demo-password="$(generate_password)" >/dev/null
}

secret_value() {
  local key="$1"
  kubectl -n "$KEYCLOAK_NAMESPACE" get secret "$KEYCLOAK_DEV_USERS_SECRET" -o json \
    | jq -r --arg key "$key" '.data[$key]' \
    | base64 -d
}

ensure_realm() {
  local token="$1"
  local status
  status=$(kc_status -H "Authorization: Bearer $token" "$KEYCLOAK_URL/admin/realms/$REALM")

  if [[ "$status" == "200" ]]; then
    return
  fi

  jq -n --arg realm "$REALM" '{realm:$realm, enabled:true, displayName:"Play&Say", loginTheme:"playsay"}' \
    | kc_curl -X POST -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
      -d @- "$KEYCLOAK_URL/admin/realms" >/dev/null
}

ensure_realm_theme() {
  local token="$1"
  kc_curl -H "Authorization: Bearer $token" "$KEYCLOAK_URL/admin/realms/$REALM" \
    | jq '. + {displayName:"Play&Say", loginTheme:"playsay"}' \
    | kc_curl -X PUT -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
      -d @- "$KEYCLOAK_URL/admin/realms/$REALM" >/dev/null
}

ensure_role() {
  local token="$1"
  local role="$2"
  local status
  status=$(kc_status -H "Authorization: Bearer $token" "$KEYCLOAK_URL/admin/realms/$REALM/roles/$role")

  if [[ "$status" == "200" ]]; then
    return
  fi

  jq -n --arg name "$role" '{name:$name}' \
    | kc_curl -X POST -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
      -d @- "$KEYCLOAK_URL/admin/realms/$REALM/roles" >/dev/null
}

client_id() {
  local token="$1"
  local client="$2"
  kc_curl -G -H "Authorization: Bearer $token" \
    --data-urlencode "clientId=$client" \
    "$KEYCLOAK_URL/admin/realms/$REALM/clients" | jq -r '.[0].id // empty'
}

upsert_client() {
  local token="$1"
  local client="$2"
  local payload="$3"
  local id
  id=$(client_id "$token" "$client")

  if [[ -n "$id" ]]; then
    kc_curl -X PUT -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
      -d "$payload" "$KEYCLOAK_URL/admin/realms/$REALM/clients/$id" >/dev/null
  else
    kc_curl -X POST -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
      -d "$payload" "$KEYCLOAK_URL/admin/realms/$REALM/clients" >/dev/null
  fi
}

ensure_clients() {
  local token="$1"
  local web_payload
  local api_payload

  web_payload=$(jq -n --arg clientId "$WEB_CLIENT_ID" '
    {
      clientId: $clientId,
      enabled: true,
      protocol: "openid-connect",
      publicClient: true,
      standardFlowEnabled: true,
      implicitFlowEnabled: false,
      directAccessGrantsEnabled: false,
      serviceAccountsEnabled: false,
      redirectUris: [
        "https://online.play-and-say.ru/*",
        "http://localhost:5173/*",
        "http://localhost:4173/*"
      ],
      webOrigins: [
        "https://online.play-and-say.ru",
        "http://localhost:5173",
        "http://localhost:4173"
      ],
      attributes: {
        "pkce.code.challenge.method": "S256",
        "post.logout.redirect.uris": "https://online.play-and-say.ru/*##http://localhost:5173/*##http://localhost:4173/*"
      }
    }
  ')

  api_payload=$(jq -n --arg clientId "$API_CLIENT_ID" '
    {
      clientId: $clientId,
      enabled: true,
      protocol: "openid-connect",
      publicClient: false,
      standardFlowEnabled: false,
      implicitFlowEnabled: false,
      directAccessGrantsEnabled: false,
      serviceAccountsEnabled: false
    }
  ')

  upsert_client "$token" "$WEB_CLIENT_ID" "$web_payload"
  upsert_client "$token" "$API_CLIENT_ID" "$api_payload"
}

user_id() {
  local token="$1"
  local username="$2"
  kc_curl -G -H "Authorization: Bearer $token" \
    --data-urlencode "username=$username" \
    --data-urlencode "exact=true" \
    "$KEYCLOAK_URL/admin/realms/$REALM/users" | jq -r '.[0].id // empty'
}

ensure_user() {
  local token="$1"
  local username="$2"
  local email="$3"
  local first_name="$4"
  local last_name="$5"
  local role="$6"
  local password_key="$7"
  local id
  local payload
  local password

  payload=$(jq -n \
    --arg username "$username" \
    --arg email "$email" \
    --arg firstName "$first_name" \
    --arg lastName "$last_name" \
    '{
      username: $username,
      email: $email,
      firstName: $firstName,
      lastName: $lastName,
      enabled: true,
      emailVerified: true
    }')

  id=$(user_id "$token" "$username")
  if [[ -n "$id" ]]; then
    kc_curl -X PUT -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
      -d "$payload" "$KEYCLOAK_URL/admin/realms/$REALM/users/$id" >/dev/null
  else
    kc_curl -X POST -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
      -d "$payload" "$KEYCLOAK_URL/admin/realms/$REALM/users" >/dev/null
    id=$(user_id "$token" "$username")
  fi

  password=$(secret_value "$password_key")
  jq -n --arg value "$password" '{type:"password", value:$value, temporary:false}' \
    | kc_curl -X PUT -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
      -d @- "$KEYCLOAK_URL/admin/realms/$REALM/users/$id/reset-password" >/dev/null

  if ! kc_curl -H "Authorization: Bearer $token" "$KEYCLOAK_URL/admin/realms/$REALM/users/$id/role-mappings/realm" \
    | jq -e --arg role "$role" '.[] | select(.name == $role)' >/dev/null; then
    local role_payload
    role_payload=$(kc_curl -H "Authorization: Bearer $token" "$KEYCLOAK_URL/admin/realms/$REALM/roles/$role")
    jq -n --argjson role "$role_payload" '[$role]' \
      | kc_curl -X POST -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
        -d @- "$KEYCLOAK_URL/admin/realms/$REALM/users/$id/role-mappings/realm" >/dev/null
  fi
}

main() {
  require_tool base64
  require_tool curl
  require_tool jq
  require_tool kubectl
  require_tool openssl

  ensure_dev_user_secret

  local token
  token=$(admin_token)

  ensure_realm "$token"
  ensure_realm_theme "$token"
  ensure_role "$token" STUDENT
  ensure_role "$token" TEACHER
  ensure_role "$token" ADMIN
  ensure_clients "$token"
  ensure_user "$token" student-demo student-demo@play-and-say.ru Student Demo STUDENT student-demo-password
  ensure_user "$token" teacher-demo teacher-demo@play-and-say.ru Teacher Demo TEACHER teacher-demo-password
  ensure_user "$token" admin-demo admin-demo@play-and-say.ru Admin Demo ADMIN admin-demo-password

  echo "Configured Keycloak realm '$REALM' with clients '$WEB_CLIENT_ID'/'$API_CLIENT_ID' and demo users."
  echo "Demo passwords are stored in Kubernetes secret '$KEYCLOAK_DEV_USERS_SECRET' in namespace '$KEYCLOAK_NAMESPACE'."
}

main "$@"
