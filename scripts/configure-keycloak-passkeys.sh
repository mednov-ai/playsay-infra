#!/usr/bin/env bash
set -euo pipefail

KEYCLOAK_URL="${KEYCLOAK_URL:-https://dev.ops.honey.school/keycloak}"
KEYCLOAK_NAMESPACE="${KEYCLOAK_NAMESPACE:-keycloak}"
KEYCLOAK_ADMIN_SECRET="${KEYCLOAK_ADMIN_SECRET:-keycloak-admin}"
KEYCLOAK_REALM="${KEYCLOAK_REALM:-playsay}"
KEYCLOAK_WEBAUTHN_RP_ID="${KEYCLOAK_WEBAUTHN_RP_ID:-dev.ops.honey.school}"
KEYCLOAK_INSECURE_TLS="${KEYCLOAK_INSECURE_TLS:-false}"

CURL_TLS_ARGS=()
if [[ "$KEYCLOAK_INSECURE_TLS" == "true" ]]; then
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

admin_token() {
  local password
  password=$(kubectl -n "$KEYCLOAK_NAMESPACE" get secret "$KEYCLOAK_ADMIN_SECRET" \
    -o jsonpath='{.data.admin-password}' | base64 -d)

  kc_curl -X POST "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
    -d client_id=admin-cli \
    -d username=admin \
    --data-urlencode password="$password" \
    -d grant_type=password | jq -er .access_token
}

configure_passwordless_policy() {
  local token="$1"

  kc_curl -H "Authorization: Bearer $token" \
    "$KEYCLOAK_URL/admin/realms/$KEYCLOAK_REALM" \
    | jq \
      --arg rpId "$KEYCLOAK_WEBAUTHN_RP_ID" \
      '. + {
        webAuthnPolicyPasswordlessRpEntityName: "Honey School",
        webAuthnPolicyPasswordlessSignatureAlgorithms: ["ES256", "RS256"],
        webAuthnPolicyPasswordlessRpId: $rpId,
        webAuthnPolicyPasswordlessAttestationConveyancePreference: "none",
        webAuthnPolicyPasswordlessAuthenticatorAttachment: "not specified",
        webAuthnPolicyPasswordlessResidentKey: "required",
        webAuthnPolicyPasswordlessUserVerificationRequirement: "required",
        webAuthnPolicyPasswordlessCreateTimeout: 60,
        webAuthnPolicyPasswordlessAvoidSameAuthenticatorRegister: true,
        webAuthnPolicyPasswordlessAcceptableAaguids: [],
        webAuthnPolicyPasswordlessExtraOrigins: [],
        webAuthnPolicyPasswordlessPasskeysEnabled: true,
        webAuthnPolicyPasswordlessMediation: "conditional"
      }' \
    | kc_curl -X PUT \
      -H "Authorization: Bearer $token" \
      -H "Content-Type: application/json" \
      -d @- "$KEYCLOAK_URL/admin/realms/$KEYCLOAK_REALM" >/dev/null
}

enable_passwordless_registration_action() {
  local token="$1"
  local action

  action=$(kc_curl -H "Authorization: Bearer $token" \
    "$KEYCLOAK_URL/admin/realms/$KEYCLOAK_REALM/authentication/required-actions" \
    | jq -ec '.[] | select(.alias == "webauthn-register-passwordless")')

  printf '%s' "$action" \
    | jq '. + {enabled: true, defaultAction: false}' \
    | kc_curl -X PUT \
      -H "Authorization: Bearer $token" \
      -H "Content-Type: application/json" \
      -d @- "$KEYCLOAK_URL/admin/realms/$KEYCLOAK_REALM/authentication/required-actions/webauthn-register-passwordless" \
      >/dev/null
}

verify_configuration() {
  local token="$1"

  kc_curl -H "Authorization: Bearer $token" \
    "$KEYCLOAK_URL/admin/realms/$KEYCLOAK_REALM" \
    | jq -e \
      --arg rpId "$KEYCLOAK_WEBAUTHN_RP_ID" \
      '.webAuthnPolicyPasswordlessRpEntityName == "Honey School"
        and .webAuthnPolicyPasswordlessRpId == $rpId
        and .webAuthnPolicyPasswordlessSignatureAlgorithms == ["ES256", "RS256"]
        and .webAuthnPolicyPasswordlessResidentKey == "required"
        and .webAuthnPolicyPasswordlessUserVerificationRequirement == "required"
        and .webAuthnPolicyPasswordlessPasskeysEnabled == true
        and .webAuthnPolicyPasswordlessMediation == "conditional"' >/dev/null

  kc_curl -H "Authorization: Bearer $token" \
    "$KEYCLOAK_URL/admin/realms/$KEYCLOAK_REALM/authentication/required-actions" \
    | jq -e '.[] | select(
        .alias == "webauthn-register-passwordless"
        and .enabled == true
        and .defaultAction == false
      )' >/dev/null
}

main() {
  require_tool base64
  require_tool curl
  require_tool jq
  require_tool kubectl

  local token
  token=$(admin_token)
  configure_passwordless_policy "$token"
  enable_passwordless_registration_action "$token"
  verify_configuration "$token"

  echo "Configured optional Passkeys for realm '$KEYCLOAK_REALM' with RP ID '$KEYCLOAK_WEBAUTHN_RP_ID'."
}

main "$@"
