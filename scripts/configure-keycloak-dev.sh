#!/usr/bin/env bash
set -euo pipefail

KEYCLOAK_URL="${KEYCLOAK_URL:-https://ops.play-and-say.ru:18443/keycloak}"
KEYCLOAK_NAMESPACE="${KEYCLOAK_NAMESPACE:-keycloak}"
KEYCLOAK_ADMIN_SECRET="${KEYCLOAK_ADMIN_SECRET:-keycloak-admin}"
KEYCLOAK_DEV_USERS_SECRET="${KEYCLOAK_DEV_USERS_SECRET:-keycloak-dev-users}"
REALM="${KEYCLOAK_REALM:-playsay}"
WEB_CLIENT_ID="${KEYCLOAK_WEB_CLIENT_ID:-playsay-web}"
API_CLIENT_ID="${KEYCLOAK_API_CLIENT_ID:-playsay-api}"
REGISTRATION_CLIENT_ID="${KEYCLOAK_REGISTRATION_CLIENT_ID:-playsay-registration-service}"
REGISTRATION_SECRET_NAMESPACE="${REGISTRATION_SECRET_NAMESPACE:-playsay-dev}"
REGISTRATION_SECRET_NAME="${REGISTRATION_SECRET_NAME:-playsay-registration}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

ensure_secret_password() {
  local key="$1"
  local encoded
  local patch

  if kubectl -n "$KEYCLOAK_NAMESPACE" get secret "$KEYCLOAK_DEV_USERS_SECRET" -o json \
    | jq -e --arg key "$key" '.data[$key] // empty' >/dev/null; then
    return
  fi

  encoded=$(printf "%s" "$(generate_password)" | base64 | tr -d '\n')
  patch=$(jq -n --arg key "$key" --arg value "$encoded" '{data: {($key): $value}}')
  kubectl -n "$KEYCLOAK_NAMESPACE" patch secret "$KEYCLOAK_DEV_USERS_SECRET" --type merge -p "$patch" >/dev/null
}

ensure_dev_user_secret() {
  if ! kubectl -n "$KEYCLOAK_NAMESPACE" get secret "$KEYCLOAK_DEV_USERS_SECRET" >/dev/null 2>&1; then
    kubectl -n "$KEYCLOAK_NAMESPACE" create secret generic "$KEYCLOAK_DEV_USERS_SECRET" \
      --from-literal=created-by=configure-keycloak-dev >/dev/null
  fi

  ensure_secret_password student-demo-password
  ensure_secret_password student-demo-2-password
  ensure_secret_password student-demo-3-password
  ensure_secret_password student-demo-4-password
  ensure_secret_password teacher-demo-password
  ensure_secret_password admin-demo-password
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

  jq -n --arg realm "$REALM" '{
      realm: $realm,
      enabled: true,
      displayName: "Play&Say",
      loginTheme: "playsay",
      internationalizationEnabled: true,
      supportedLocales: ["ru", "en", "de", "fr"],
      defaultLocale: "ru"
    }' \
    | kc_curl -X POST -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
      -d @- "$KEYCLOAK_URL/admin/realms" >/dev/null
}

ensure_realm_theme() {
  local token="$1"
  kc_curl -H "Authorization: Bearer $token" "$KEYCLOAK_URL/admin/realms/$REALM" \
    | jq '. + {
        displayName: "Play&Say",
        loginTheme: "playsay",
        internationalizationEnabled: true,
        supportedLocales: ["ru", "en", "de", "fr"],
        defaultLocale: "ru"
      }' \
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

service_account_user_id() {
  local token="$1"
  local client_uuid="$2"
  kc_curl -H "Authorization: Bearer $token" \
    "$KEYCLOAK_URL/admin/realms/$REALM/clients/$client_uuid/service-account-user" | jq -r '.id // empty'
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
        "https://key.play-and-say.ru/*",
        "http://localhost:5173/*",
        "http://localhost:5174/*",
        "http://localhost:5175/*",
        "http://localhost:4173/*",
        "http://localhost:4175/*",
        "http://127.0.0.1:5173/*",
        "http://127.0.0.1:5174/*",
        "http://127.0.0.1:5175/*",
        "http://127.0.0.1:4173/*",
        "http://127.0.0.1:4175/*"
      ],
      webOrigins: [
        "https://online.play-and-say.ru",
        "https://key.play-and-say.ru",
        "http://localhost:5173",
        "http://localhost:5174",
        "http://localhost:5175",
        "http://localhost:4173",
        "http://localhost:4175",
        "http://127.0.0.1:5173",
        "http://127.0.0.1:5174",
        "http://127.0.0.1:5175",
        "http://127.0.0.1:4173",
        "http://127.0.0.1:4175"
      ],
      attributes: {
        "pkce.code.challenge.method": "S256",
        "post.logout.redirect.uris": "https://online.play-and-say.ru/*##https://key.play-and-say.ru/*##http://localhost:5173/*##http://localhost:5174/*##http://localhost:5175/*##http://localhost:4173/*##http://localhost:4175/*##http://127.0.0.1:5173/*##http://127.0.0.1:5174/*##http://127.0.0.1:5175/*##http://127.0.0.1:4173/*##http://127.0.0.1:4175/*"
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

ensure_registration_service_client() {
  local token="$1"
  local registration_payload
  local registration_uuid
  local realm_management_uuid
  local service_user_id

  registration_payload=$(jq -n --arg clientId "$REGISTRATION_CLIENT_ID" '
    {
      clientId: $clientId,
      enabled: true,
      protocol: "openid-connect",
      publicClient: false,
      standardFlowEnabled: false,
      implicitFlowEnabled: false,
      directAccessGrantsEnabled: false,
      serviceAccountsEnabled: true
    }
  ')

  upsert_client "$token" "$REGISTRATION_CLIENT_ID" "$registration_payload"
  registration_uuid=$(client_id "$token" "$REGISTRATION_CLIENT_ID")
  realm_management_uuid=$(client_id "$token" "realm-management")
  service_user_id=$(service_account_user_id "$token" "$registration_uuid")

  for role in view-users manage-users view-realm; do
    if ! kc_curl -H "Authorization: Bearer $token" \
      "$KEYCLOAK_URL/admin/realms/$REALM/users/$service_user_id/role-mappings/clients/$realm_management_uuid" \
      | jq -e --arg role "$role" '.[] | select(.name == $role)' >/dev/null; then
      local role_payload
      role_payload=$(kc_curl -H "Authorization: Bearer $token" \
        "$KEYCLOAK_URL/admin/realms/$REALM/clients/$realm_management_uuid/roles/$role")
      jq -n --argjson role "$role_payload" '[$role]' \
        | kc_curl -X POST -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
          -d @- "$KEYCLOAK_URL/admin/realms/$REALM/users/$service_user_id/role-mappings/clients/$realm_management_uuid" >/dev/null
    fi
  done

  sync_registration_client_secret "$token" "$registration_uuid"
}

sync_registration_client_secret() {
  local token="$1"
  local client_uuid="$2"
  local client_secret
  local encoded_client_id
  local encoded_client_secret
  local patch

  client_secret=$(kc_curl -H "Authorization: Bearer $token" \
    "$KEYCLOAK_URL/admin/realms/$REALM/clients/$client_uuid/client-secret" | jq -r '.value')
  encoded_client_id=$(printf "%s" "$REGISTRATION_CLIENT_ID" | base64 | tr -d '\n')
  encoded_client_secret=$(printf "%s" "$client_secret" | base64 | tr -d '\n')

  kubectl create namespace "$REGISTRATION_SECRET_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  if ! kubectl -n "$REGISTRATION_SECRET_NAMESPACE" get secret "$REGISTRATION_SECRET_NAME" >/dev/null 2>&1; then
    kubectl -n "$REGISTRATION_SECRET_NAMESPACE" create secret generic "$REGISTRATION_SECRET_NAME" \
      --from-literal=created-by=configure-keycloak-dev >/dev/null
  fi
  patch=$(jq -n \
    --arg clientId "$encoded_client_id" \
    --arg clientSecret "$encoded_client_secret" \
    '{data: {"keycloak-client-id": $clientId, "keycloak-client-secret": $clientSecret}}')
  kubectl -n "$REGISTRATION_SECRET_NAMESPACE" patch secret "$REGISTRATION_SECRET_NAME" --type merge -p "$patch" >/dev/null
  kubectl -n "$REGISTRATION_SECRET_NAMESPACE" label secret "$REGISTRATION_SECRET_NAME" \
    app.kubernetes.io/name=playsay-registration \
    app.kubernetes.io/managed-by=playsay-infra \
    --overwrite >/dev/null
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
  ensure_registration_service_client "$token"
  ensure_user "$token" student-demo student-demo@play-and-say.ru Student Demo STUDENT student-demo-password
  ensure_user "$token" student-demo-2 student-demo-2@play-and-say.ru Student "Demo 2" STUDENT student-demo-2-password
  ensure_user "$token" student-demo-3 student-demo-3@play-and-say.ru Student "Demo 3" STUDENT student-demo-3-password
  ensure_user "$token" student-demo-4 student-demo-4@play-and-say.ru Student "Demo 4" STUDENT student-demo-4-password
  ensure_user "$token" teacher-demo teacher-demo@play-and-say.ru Teacher Demo TEACHER teacher-demo-password
  ensure_user "$token" admin-demo admin-demo@play-and-say.ru Admin Demo ADMIN admin-demo-password

  if [[ "${SYNC_JENKINS_SMOKE_SECRET:-true}" == "true" && -x "$ROOT_DIR/scripts/sync-keycloak-dev-users-secret.sh" ]]; then
    SOURCE_NAMESPACE="$KEYCLOAK_NAMESPACE" \
      SOURCE_SECRET="$KEYCLOAK_DEV_USERS_SECRET" \
      TARGET_NAMESPACES="${KEYCLOAK_DEV_USERS_TARGET_NAMESPACES:-jenkins}" \
      "$ROOT_DIR/scripts/sync-keycloak-dev-users-secret.sh"
  fi

  echo "Configured Keycloak realm '$REALM' with clients '$WEB_CLIENT_ID'/'$API_CLIENT_ID'/'$REGISTRATION_CLIENT_ID' and demo users."
  echo "Demo passwords are stored in Kubernetes secret '$KEYCLOAK_DEV_USERS_SECRET' in namespace '$KEYCLOAK_NAMESPACE'."
  echo "Registration client credentials are stored in secret '$REGISTRATION_SECRET_NAME' in namespace '$REGISTRATION_SECRET_NAMESPACE'."
}

main "$@"
