#!/usr/bin/env bash
set -euo pipefail

KEYCLOAK_URL="${KEYCLOAK_URL:-https://dev.ops.honey.school/keycloak}"
KEYCLOAK_NAMESPACE="${KEYCLOAK_NAMESPACE:-keycloak}"
KEYCLOAK_ADMIN_SECRET="${KEYCLOAK_ADMIN_SECRET:-keycloak-admin}"
KEYCLOAK_REALM="${KEYCLOAK_REALM:-playsay}"
KEYCLOAK_BROWSER_FLOW="${KEYCLOAK_BROWSER_FLOW:-browser-with-lesson-access}"
KEYCLOAK_LESSON_REDEEM_URL="${KEYCLOAK_LESSON_REDEEM_URL:-http://registration-service.playsay-dev.svc.cluster.local/api/provider/lesson-auth/assertions/redeem}"
KEYCLOAK_LESSON_ISSUER="${KEYCLOAK_LESSON_ISSUER:-https://dev.ops.honey.school/keycloak/realms/playsay}"
KEYCLOAK_LESSON_PROVIDER_SECRET="${KEYCLOAK_LESSON_PROVIDER_SECRET:-playsay-lesson-access}"
KEYCLOAK_LESSON_PROVIDER_NAMESPACE="${KEYCLOAK_LESSON_PROVIDER_NAMESPACE:-playsay-dev}"
KEYCLOAK_LESSON_PROVIDER_TOKEN_KEY="${KEYCLOAK_LESSON_PROVIDER_TOKEN_KEY:-provider-token}"
KEYCLOAK_INSECURE_TLS="${KEYCLOAK_INSECURE_TLS:-false}"

CURL_TLS_ARGS=()
if [[ "$KEYCLOAK_INSECURE_TLS" == "true" ]]; then
  CURL_TLS_ARGS=(-k)
fi

require_tool() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required tool: $1" >&2; exit 1; }
}

kc_curl() {
  curl "${CURL_TLS_ARGS[@]}" -fsS "$@"
}

secret_value() {
  kubectl -n "$1" get secret "$2" -o "jsonpath={.data.$3}" | base64 -d
}

admin_token() {
  local password
  password=$(secret_value "$KEYCLOAK_NAMESPACE" "$KEYCLOAK_ADMIN_SECRET" admin-password)
  kc_curl -X POST "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
    -d client_id=admin-cli -d username=admin --data-urlencode password="$password" -d grant_type=password \
    | jq -er .access_token
}

configure_remembered_sessions() {
  local token="$1"
  kc_curl -H "Authorization: Bearer $token" "$KEYCLOAK_URL/admin/realms/$KEYCLOAK_REALM" \
    | jq '. + {rememberMe: true, ssoSessionIdleRememberMe: 2592000, ssoSessionMaxLifespanRememberMe: 2592000}' \
    | kc_curl -X PUT -H "Authorization: Bearer $token" -H 'Content-Type: application/json' -d @- \
      "$KEYCLOAK_URL/admin/realms/$KEYCLOAK_REALM" >/dev/null
}

ensure_browser_flow() {
  local token="$1"
  local flow_id
  flow_id=$(kc_curl -H "Authorization: Bearer $token" \
    "$KEYCLOAK_URL/admin/realms/$KEYCLOAK_REALM/authentication/flows" \
    | jq -r --arg alias "$KEYCLOAK_BROWSER_FLOW" '.[] | select(.alias == $alias) | .id' | head -1)
  if [[ -z "$flow_id" ]]; then
    kc_curl -X POST -H "Authorization: Bearer $token" -H 'Content-Type: application/json' \
      -d "$(jq -nc --arg name "$KEYCLOAK_BROWSER_FLOW" '{newName: $name}')" \
      "$KEYCLOAK_URL/admin/realms/$KEYCLOAK_REALM/authentication/flows/browser/copy" >/dev/null
  fi
}

configure_lesson_execution() {
  local token="$1"
  local executions execution_id config_id provider_token payload
  executions=$(kc_curl -H "Authorization: Bearer $token" \
    "$KEYCLOAK_URL/admin/realms/$KEYCLOAK_REALM/authentication/flows/$KEYCLOAK_BROWSER_FLOW/executions")
  execution_id=$(printf '%s' "$executions" | jq -r '.[] | select(.providerId == "playsay-lesson-assertion") | .id' | head -1)
  if [[ -z "$execution_id" ]]; then
    kc_curl -X POST -H "Authorization: Bearer $token" -H 'Content-Type: application/json' \
      -d '{"provider":"playsay-lesson-assertion"}' \
      "$KEYCLOAK_URL/admin/realms/$KEYCLOAK_REALM/authentication/flows/$KEYCLOAK_BROWSER_FLOW/executions/execution" >/dev/null
    executions=$(kc_curl -H "Authorization: Bearer $token" \
      "$KEYCLOAK_URL/admin/realms/$KEYCLOAK_REALM/authentication/flows/$KEYCLOAK_BROWSER_FLOW/executions")
    execution_id=$(printf '%s' "$executions" | jq -er '.[] | select(.providerId == "playsay-lesson-assertion") | .id' | head -1)
  fi

  printf '%s' "$executions" | jq -c --arg id "$execution_id" \
    '.[] | select(.id == $id) | . + {requirement: "ALTERNATIVE"}' \
    | kc_curl -X PUT -H "Authorization: Bearer $token" -H 'Content-Type: application/json' -d @- \
      "$KEYCLOAK_URL/admin/realms/$KEYCLOAK_REALM/authentication/executions/$execution_id" >/dev/null

  provider_token=$(secret_value "$KEYCLOAK_LESSON_PROVIDER_NAMESPACE" "$KEYCLOAK_LESSON_PROVIDER_SECRET" "$KEYCLOAK_LESSON_PROVIDER_TOKEN_KEY")
  payload=$(jq -nc \
    --arg alias honey-school-lesson-access \
    --arg redeemUrl "$KEYCLOAK_LESSON_REDEEM_URL" \
    --arg issuer "$KEYCLOAK_LESSON_ISSUER" \
    --arg providerToken "$provider_token" \
    '{alias: $alias, config: {redeemUrl: $redeemUrl, issuer: $issuer, providerToken: $providerToken}}')
  config_id=$(printf '%s' "$executions" | jq -r --arg id "$execution_id" \
    '.[] | select(.id == $id) | .authenticationConfig' | head -1)
  if [[ -n "$config_id" && "$config_id" != "null" ]]; then
    printf '%s' "$payload" | kc_curl -X PUT -H "Authorization: Bearer $token" -H 'Content-Type: application/json' -d @- \
      "$KEYCLOAK_URL/admin/realms/$KEYCLOAK_REALM/authentication/config/$config_id" >/dev/null
  else
    printf '%s' "$payload" | kc_curl -X POST -H "Authorization: Bearer $token" -H 'Content-Type: application/json' -d @- \
      "$KEYCLOAK_URL/admin/realms/$KEYCLOAK_REALM/authentication/executions/$execution_id/config" >/dev/null
  fi
}

activate_and_verify() {
  local token="$1"
  kc_curl -H "Authorization: Bearer $token" "$KEYCLOAK_URL/admin/realms/$KEYCLOAK_REALM" \
    | jq --arg flow "$KEYCLOAK_BROWSER_FLOW" '. + {browserFlow: $flow}' \
    | kc_curl -X PUT -H "Authorization: Bearer $token" -H 'Content-Type: application/json' -d @- \
      "$KEYCLOAK_URL/admin/realms/$KEYCLOAK_REALM" >/dev/null

  kc_curl -H "Authorization: Bearer $token" "$KEYCLOAK_URL/admin/realms/$KEYCLOAK_REALM" \
    | jq -e --arg flow "$KEYCLOAK_BROWSER_FLOW" \
      '.browserFlow == $flow and .rememberMe == true and .ssoSessionIdleRememberMe == 2592000 and .ssoSessionMaxLifespanRememberMe == 2592000' >/dev/null
  kc_curl -H "Authorization: Bearer $token" \
    "$KEYCLOAK_URL/admin/realms/$KEYCLOAK_REALM/authentication/flows/$KEYCLOAK_BROWSER_FLOW/executions" \
    | jq -e '.[] | select(.providerId == "playsay-lesson-assertion" and .requirement == "ALTERNATIVE" and .authenticationConfig != null)' >/dev/null
}

main() {
  require_tool base64
  require_tool curl
  require_tool jq
  require_tool kubectl
  local token
  token=$(admin_token)
  configure_remembered_sessions "$token"
  ensure_browser_flow "$token"
  configure_lesson_execution "$token"
  activate_and_verify "$token"
  echo "Configured conditional lesson access and 30-day remembered sessions for realm '$KEYCLOAK_REALM'."
}

main "$@"
