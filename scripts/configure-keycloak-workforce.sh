#!/usr/bin/env bash
set -Eeuo pipefail

KUBECONFIG_PATH="${KUBECONFIG_PATH:-${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}}"
KEYCLOAK_NAMESPACE="${KEYCLOAK_NAMESPACE:-keycloak}"
KEYCLOAK_ADMIN_SECRET="${KEYCLOAK_ADMIN_SECRET:-keycloak-admin}"
KEYCLOAK_CONTAINER="${KEYCLOAK_CONTAINER:-keycloak}"
KEYCLOAK_SERVER="${KEYCLOAK_SERVER:-http://localhost:8080/keycloak}"
KCADM_PATH="${KCADM_PATH:-/opt/bitnami/keycloak/bin/kcadm.sh}"
KCADM_CONFIG="${KCADM_CONFIG:-/tmp/kcadm-workforce.config}"
WORKFORCE_REALM="${WORKFORCE_REALM:-workforce}"
WORKFORCE_ISSUER="${WORKFORCE_ISSUER:-https://ops.honey.school/keycloak/realms/workforce}"
CLIENT_SECRET_NAME="${CLIENT_SECRET_NAME:-workforce-oidc-client-secrets}"

for command_name in kubectl jq base64; do
  command -v "${command_name}" >/dev/null || {
    echo "Missing required command: ${command_name}" >&2
    exit 2
  }
done
[[ "${WORKFORCE_REALM}" == "workforce" ]] || {
  echo "The workforce realm name is fixed to 'workforce'." >&2
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

realm_payload="$(
  jq -cn \
    --arg realm "${WORKFORCE_REALM}" \
    '{
      realm:$realm,
      displayName:"Play&Say Workforce",
      enabled:true,
      registrationAllowed:false,
      registrationEmailAsUsername:false,
      resetPasswordAllowed:false,
      editUsernameAllowed:false,
      loginWithEmailAllowed:true,
      duplicateEmailsAllowed:false,
      verifyEmail:true,
      rememberMe:false,
      internationalizationEnabled:true,
      supportedLocales:["ru","en","de","fr"],
      defaultLocale:"ru",
      loginTheme:"playsay",
      accountTheme:"keycloak.v3",
      adminTheme:"keycloak.v2",
      bruteForceProtected:true,
      permanentLockout:false,
      maxFailureWaitSeconds:900,
      minimumQuickLoginWaitSeconds:60,
      waitIncrementSeconds:60,
      quickLoginCheckMilliSeconds:1000,
      maxDeltaTimeSeconds:43200,
      failureFactor:5,
      ssoSessionIdleTimeout:28800,
      ssoSessionMaxLifespan:43200,
      offlineSessionMaxLifespanEnabled:true,
      offlineSessionMaxLifespan:0,
      accessTokenLifespan:300,
      accessTokenLifespanForImplicitFlow:0,
      oauth2DeviceCodeLifespan:300,
      oauth2DevicePollingInterval:5,
      otpPolicyType:"totp",
      otpPolicyAlgorithm:"HmacSHA1",
      otpPolicyInitialCounter:0,
      otpPolicyDigits:6,
      otpPolicyLookAheadWindow:1,
      otpPolicyPeriod:30,
      webAuthnPolicyRpEntityName:"Play&Say Workforce",
      webAuthnPolicySignatureAlgorithms:["ES256","RS256"],
      webAuthnPolicyAttestationConveyancePreference:"none",
      webAuthnPolicyAuthenticatorAttachment:"not specified",
      webAuthnPolicyRequireResidentKey:"not specified",
      webAuthnPolicyUserVerificationRequirement:"preferred",
      webAuthnPolicyCreateTimeout:0,
      webAuthnPolicyAvoidSameAuthenticatorRegister:false,
      webAuthnPolicyPasswordlessRpEntityName:"Play&Say Workforce",
      webAuthnPolicyPasswordlessSignatureAlgorithms:["ES256","RS256"],
      webAuthnPolicyPasswordlessAttestationConveyancePreference:"none",
      webAuthnPolicyPasswordlessAuthenticatorAttachment:"not specified",
      webAuthnPolicyPasswordlessRequireResidentKey:"Yes",
      webAuthnPolicyPasswordlessUserVerificationRequirement:"required",
      webAuthnPolicyPasswordlessCreateTimeout:0,
      webAuthnPolicyPasswordlessAvoidSameAuthenticatorRegister:true,
      browserFlow:"workforce-browser",
      authenticationFlows:[
        {
          alias:"workforce-browser",
          description:"Passkey first; password and TOTP fallback",
          providerId:"basic-flow",
          topLevel:true,
          builtIn:false,
          authenticationExecutions:[
            {
              authenticator:"auth-cookie",
              requirement:"ALTERNATIVE",
              priority:10,
              userSetupAllowed:false,
              authenticatorFlow:false
            },
            {
              authenticator:"webauthn-authenticator-passwordless",
              requirement:"ALTERNATIVE",
              priority:20,
              userSetupAllowed:false,
              authenticatorFlow:false
            },
            {
              flowAlias:"workforce-password-otp",
              requirement:"ALTERNATIVE",
              priority:30,
              userSetupAllowed:false,
              authenticatorFlow:true
            }
          ]
        },
        {
          alias:"workforce-password-otp",
          description:"Emergency fallback requiring password and TOTP",
          providerId:"basic-flow",
          topLevel:false,
          builtIn:false,
          authenticationExecutions:[
            {
              authenticator:"auth-username-password-form",
              requirement:"REQUIRED",
              priority:10,
              userSetupAllowed:false,
              authenticatorFlow:false
            },
            {
              authenticator:"auth-otp-form",
              requirement:"REQUIRED",
              priority:20,
              userSetupAllowed:false,
              authenticatorFlow:false
            }
          ]
        }
      ]
    }'
)"

if ! kcadm get "realms/${WORKFORCE_REALM}" >/dev/null 2>&1; then
  printf '%s' "${realm_payload}" |
    "${kubectl_cmd[@]}" -n "${KEYCLOAK_NAMESPACE}" exec -i -c "${KEYCLOAK_CONTAINER}" "${pod}" -- \
      "${KCADM_PATH}" create realms --config "${KCADM_CONFIG}" -f - >/dev/null
else
  current_browser_flow="$(kcadm get "realms/${WORKFORCE_REALM}" | jq -r '.browserFlow // ""')"
  [[ "${current_browser_flow}" == "workforce-browser" ]] || {
    echo "Existing workforce realm uses unexpected browser flow ${current_browser_flow}; refusing auth-flow overwrite." >&2
    exit 4
  }
  printf '%s' "${realm_payload}" |
    jq 'del(.authenticationFlows)' |
    "${kubectl_cmd[@]}" -n "${KEYCLOAK_NAMESPACE}" exec -i -c "${KEYCLOAK_CONTAINER}" "${pod}" -- \
      "${KCADM_PATH}" update "realms/${WORKFORCE_REALM}" --config "${KCADM_CONFIG}" -f - >/dev/null
fi

for action in CONFIGURE_TOTP webauthn-register-passwordless; do
  action_json="$(
    kcadm get authentication/required-actions -r "${WORKFORCE_REALM}" |
      jq -c --arg alias "${action}" '.[] | select(.alias == $alias)'
  )"
  [[ -n "${action_json}" ]] || {
    echo "Required action ${action} is unavailable in Keycloak." >&2
    exit 4
  }
  printf '%s' "${action_json}" |
    jq '.enabled = true | .defaultAction = true' |
    "${kubectl_cmd[@]}" -n "${KEYCLOAK_NAMESPACE}" exec -i -c "${KEYCLOAK_CONTAINER}" "${pod}" -- \
      "${KCADM_PATH}" update "authentication/required-actions/${action}" \
        --config "${KCADM_CONFIG}" -r "${WORKFORCE_REALM}" -f - >/dev/null
done

ensure_group() {
  local name="$1"
  local id
  id="$(
    kcadm get groups -r "${WORKFORCE_REALM}" -q "search=${name}" |
      jq -r --arg name "${name}" '.[] | select(.name == $name) | .id' |
      head -n 1
  )"
  if [[ -z "${id}" ]]; then
    printf '%s' "$(jq -cn --arg name "${name}" '{name:$name}')" |
      "${kubectl_cmd[@]}" -n "${KEYCLOAK_NAMESPACE}" exec -i -c "${KEYCLOAK_CONTAINER}" "${pod}" -- \
        "${KCADM_PATH}" create groups --config "${KCADM_CONFIG}" \
          -r "${WORKFORCE_REALM}" -f - >/dev/null
  fi
}
for group in developers release-operators platform-admins; do
  ensure_group "${group}"
done

client_secret_args=()
upsert_client() {
  local client_id="$1"
  local origin="$2"
  local redirect_uri="$3"
  local uuid
  local payload
  payload="$(
    jq -cn \
      --arg clientId "${client_id}" \
      --arg origin "${origin}" \
      --arg redirectUri "${redirect_uri}" \
      '{
        clientId:$clientId,
        name:$clientId,
        enabled:true,
        protocol:"openid-connect",
        publicClient:false,
        bearerOnly:false,
        standardFlowEnabled:true,
        implicitFlowEnabled:false,
        directAccessGrantsEnabled:false,
        serviceAccountsEnabled:false,
        consentRequired:false,
        frontchannelLogout:true,
        redirectUris:[$redirectUri],
        webOrigins:(if $origin == "" then [] else [$origin] end),
        defaultClientScopes:["web-origins","acr","profile","roles","email"],
        optionalClientScopes:[],
        attributes:{
          "pkce.code.challenge.method":"S256",
          "post.logout.redirect.uris":(if $origin == "" then "" else ($origin + "/*") end)
        },
        protocolMappers:[
          {
            name:"workforce-groups",
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
  uuid="$(
    kcadm get clients -r "${WORKFORCE_REALM}" -q "clientId=${client_id}" |
      jq -r 'if length == 1 then .[0].id else empty end'
  )"
  if [[ -n "${uuid}" ]]; then
    printf '%s' "${payload}" |
      "${kubectl_cmd[@]}" -n "${KEYCLOAK_NAMESPACE}" exec -i -c "${KEYCLOAK_CONTAINER}" "${pod}" -- \
        "${KCADM_PATH}" update "clients/${uuid}" --config "${KCADM_CONFIG}" \
          -r "${WORKFORCE_REALM}" -f - >/dev/null
  else
    printf '%s' "${payload}" |
      "${kubectl_cmd[@]}" -n "${KEYCLOAK_NAMESPACE}" exec -i -c "${KEYCLOAK_CONTAINER}" "${pod}" -- \
        "${KCADM_PATH}" create clients --config "${KCADM_CONFIG}" \
          -r "${WORKFORCE_REALM}" -f - >/dev/null
    uuid="$(
      kcadm get clients -r "${WORKFORCE_REALM}" -q "clientId=${client_id}" |
        jq -r 'if length == 1 then .[0].id else empty end'
    )"
  fi
  [[ -n "${uuid}" ]] || exit 4
  secret="$(kcadm get "clients/${uuid}/client-secret" -r "${WORKFORCE_REALM}" | jq -r '.value // empty')"
  [[ -n "${secret}" ]] || exit 4
  client_secret_args+=("--from-literal=${client_id}-client-id=${client_id}")
  client_secret_args+=("--from-literal=${client_id}-client-secret=${secret}")
}

upsert_client ops-argocd-prod https://argocd.ops.honey.school https://argocd.ops.honey.school/auth/callback
upsert_client ops-argocd-dev https://argocd.dev.ops.honey.school https://argocd.dev.ops.honey.school/auth/callback
upsert_client ops-headlamp-prod https://headlamp.ops.honey.school https://headlamp.ops.honey.school/oidc-callback
upsert_client ops-headlamp-dev https://headlamp.dev.ops.honey.school https://headlamp.dev.ops.honey.school/oidc-callback
upsert_client ops-jenkins https://jenkins.ops.honey.school https://jenkins.ops.honey.school/securityRealm/finishLogin
upsert_client playsay-release-workflows https://workflows.ops.honey.school https://workflows.ops.honey.school/oauth2/callback
upsert_client ops-metrics-dev https://metrics.dev.ops.honey.school https://metrics.dev.ops.honey.school/oauth2/callback
upsert_client playsay-dev-workforce-broker "" https://dev.ops.honey.school/keycloak/realms/playsay/broker/workforce/endpoint

"${kubectl_cmd[@]}" -n "${KEYCLOAK_NAMESPACE}" create secret generic "${CLIENT_SECRET_NAME}" \
  "${client_secret_args[@]}" \
  --dry-run=client -o yaml |
  "${kubectl_cmd[@]}" apply -f - >/dev/null
unset secret client_secret_args

echo "Workforce realm, passwordless flow, groups and OIDC clients are configured."
