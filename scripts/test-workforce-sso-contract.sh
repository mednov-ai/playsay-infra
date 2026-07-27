#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for command_name in bash helm yq rg; do
  command -v "${command_name}" >/dev/null || {
    echo "Missing test dependency: ${command_name}" >&2
    exit 2
  }
done

for script in \
  "${ROOT_DIR}/scripts/bootstrap-keycloak-workforce-user.sh" \
  "${ROOT_DIR}/scripts/bootstrap-jenkins-ci.sh" \
  "${ROOT_DIR}/scripts/configure-keycloak-dev-workforce-broker.sh" \
  "${ROOT_DIR}/scripts/configure-keycloak-prod-workflows.sh" \
  "${ROOT_DIR}/scripts/configure-keycloak-workforce.sh" \
  "${ROOT_DIR}/scripts/configure-workforce-sso-cluster.sh" \
  "${ROOT_DIR}/scripts/install-argo-workflows-prod.sh" \
  "${ROOT_DIR}/scripts/issue-ax41-honey-certificates.sh" \
  "${ROOT_DIR}/scripts/sync-workforce-oidc-client-secret.sh"
do
  bash -n "${script}"
done

work_dir="$(mktemp -d /tmp/playsay-workforce-sso-contract.XXXXXX)"
trap 'rm -rf "${work_dir}"' EXIT

helm template argocd argo/argo-cd \
  --version 10.2.1 \
  --namespace argocd \
  --values "${ROOT_DIR}/workforce-sso/argocd-prod-values.yaml" \
  >"${work_dir}/argocd-prod.yaml"
helm template argocd argo/argo-cd \
  --version 10.2.1 \
  --namespace argocd \
  --values "${ROOT_DIR}/workforce-sso/argocd-dev-values.yaml" \
  >"${work_dir}/argocd-dev.yaml"
helm template headlamp headlamp/headlamp \
  --version 0.43.0 \
  --namespace headlamp \
  --values "${ROOT_DIR}/workforce-sso/headlamp-prod-values.yaml" \
  >"${work_dir}/headlamp-prod.yaml"
helm template headlamp headlamp/headlamp \
  --version 0.43.0 \
  --namespace headlamp \
  --values "${ROOT_DIR}/workforce-sso/headlamp-dev-values.yaml" \
  >"${work_dir}/headlamp-dev.yaml"
helm template jenkins jenkins/jenkins \
  --version 5.9.22 \
  --namespace jenkins \
  --values "${ROOT_DIR}/jenkins/values-ci.yaml" \
  --set-file controller.JCasC.configScripts.playsay-workforce-sso="${ROOT_DIR}/jenkins/jcasc/playsay-workforce-sso.yaml" \
  >"${work_dir}/jenkins.yaml"

issuer=https://ops.honey.school/keycloak/realms/workforce
for rendered in \
  "${work_dir}/argocd-prod.yaml" \
  "${work_dir}/argocd-dev.yaml" \
  "${work_dir}/jenkins.yaml"
do
  grep -q "${issuer}" "${rendered}"
done
for rendered in "${work_dir}/headlamp-prod.yaml" "${work_dir}/headlamp-dev.yaml"; do
  grep -q 'name: workforce-oidc' "${rendered}"
  grep -q -- '-oidc-client-id=$(OIDC_CLIENT_ID)' "${rendered}"
  grep -q -- '-oidc-callback-url=$(OIDC_CALLBACK_URL)' "${rendered}"
  grep -q -- '-oidc-use-pkce=$(OIDC_USE_PKCE)' "${rendered}"
done

grep -q 'oic-auth:4.715.vf202e4229f61' "${work_dir}/jenkins.yaml"
grep -q 'matrix-auth:3.3' "${work_dir}/jenkins.yaml"
grep -q 'Overall/Administer' "${work_dir}/jenkins.yaml"
grep -q 'allowTokenAccessWithoutOicSession: true' "${work_dir}/jenkins.yaml"
grep -q 'escapeHatch:' "${work_dir}/jenkins.yaml"

workforce_script="${ROOT_DIR}/scripts/configure-keycloak-workforce.sh"
grep -q 'webauthn-authenticator-passwordless' "${workforce_script}"
grep -q 'auth-username-password-form' "${workforce_script}"
grep -q 'auth-otp-form' "${workforce_script}"
grep -q 'webAuthnPolicyPasswordlessUserVerificationRequirement:"required"' "${workforce_script}"
grep -q 'directAccessGrantsEnabled:false' "${workforce_script}"
grep -q 'protocolMapper:"oidc-audience-mapper"' "${workforce_script}"
if rg -n 'totp-only|otp-only' \
  --glob '!test-workforce-sso-contract.sh' \
  "${ROOT_DIR}/scripts" "${ROOT_DIR}/workforce-sso"; then
  echo "TOTP-only authentication is forbidden." >&2
  exit 1
fi

broker_script="${ROOT_DIR}/scripts/configure-keycloak-dev-workforce-broker.sh"
grep -q 'trustEmail:false' "${broker_script}"
grep -q 'pkceEnabled:"true"' "${broker_script}"
grep -q 'validateSignature:"true"' "${broker_script}"
grep -q 'oidc-advanced-role-idp-mapper' "${broker_script}"
grep -q 'workforce-developers-teacher developers TEACHER' "${broker_script}"
grep -q 'workforce-platform-admins-admin platform-admins ADMIN' "${broker_script}"

for hostname in \
  argocd.ops.honey.school \
  argocd.dev.ops.honey.school \
  headlamp.ops.honey.school \
  headlamp.dev.ops.honey.school \
  metrics.dev.ops.honey.school \
  jenkins.ops.honey.school \
  workflows.ops.honey.school \
  cockpit.ops.honey.school
do
  grep -q "hostname: ${hostname}" "${ROOT_DIR}/ansible/group_vars/ax41_hosts.yaml"
done
grep -q 'realms:' "${ROOT_DIR}/ansible/group_vars/rf_edges.yaml"
grep -q -- '- workforce' "${ROOT_DIR}/ansible/group_vars/rf_edges.yaml"
grep -q 'oidc-username-prefix={{ k3s_workforce_oidc_username_prefix }}' \
  "${ROOT_DIR}/ansible/roles/k3s-server/templates/workforce-oidc.yaml.j2"
grep -q 'k3s_workforce_oidc_groups_prefix: "workforce:"' \
  "${ROOT_DIR}/ansible/group_vars/ax41_guests.yaml"
grep -q 'cockpit_public_origin: https://cockpit.ops.honey.school' \
  "${ROOT_DIR}/ansible/group_vars/ax41_hosts.yaml"
grep -q 'Origins = {{ cockpit_public_origin }}' \
  "${ROOT_DIR}/ansible/roles/cockpit/tasks/main.yaml"
grep -q 'ProtocolHeader = X-Forwarded-Proto' \
  "${ROOT_DIR}/ansible/roles/cockpit/tasks/main.yaml"
grep -q 'ForwardedForHeader = X-Forwarded-For' \
  "${ROOT_DIR}/ansible/roles/cockpit/tasks/main.yaml"
grep -q 'proxy_set_header X-Forwarded-For \$remote_addr;' \
  "${ROOT_DIR}/ansible/roles/edge-proxy/templates/playsay-honey.conf.j2"

for manifest in \
  "${ROOT_DIR}/workforce-sso/headlamp-rbac-prod.yaml" \
  "${ROOT_DIR}/workforce-sso/headlamp-rbac-dev.yaml" \
  "${ROOT_DIR}/workforce-sso/metrics-oauth2-proxy-dev.yaml"
do
  yq eval-all '.' "${manifest}" >/dev/null
done
grep -q 'location ~ \^/(api/v1/admin|debug|flags|metrics)' \
  "${ROOT_DIR}/workforce-sso/metrics-oauth2-proxy-dev.yaml"

if rg -n 'client-secret:[[:space:]]+[^$<{]' \
  "${ROOT_DIR}/workforce-sso" \
  "${ROOT_DIR}/jenkins/jcasc/playsay-workforce-sso.yaml"; then
  echo "A literal OIDC client secret appears in Git-managed configuration." >&2
  exit 1
fi

echo "Workforce SSO contracts, RBAC, canonical hosts and passwordless fallback are valid."
