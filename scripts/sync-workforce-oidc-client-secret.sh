#!/usr/bin/env bash
set -Eeuo pipefail

: "${CLIENT:?Set CLIENT to argocd-prod, argocd-dev, headlamp-prod, headlamp-dev, jenkins, workflows, metrics-dev, or dev-broker}"
: "${SOURCE_KUBECONFIG:?Set SOURCE_KUBECONFIG to the production cluster kubeconfig}"
: "${TARGET_KUBECONFIG:?Set TARGET_KUBECONFIG to the destination cluster kubeconfig}"

SOURCE_NAMESPACE="${SOURCE_NAMESPACE:-keycloak}"
SOURCE_SECRET="${SOURCE_SECRET:-workforce-oidc-client-secrets}"
ISSUER=https://ops.honey.school/keycloak/realms/workforce

for command_name in kubectl base64 openssl; do
  command -v "${command_name}" >/dev/null || exit 2
done
[[ -r "${SOURCE_KUBECONFIG}" && -r "${TARGET_KUBECONFIG}" ]] || {
  echo "Both kubeconfigs must be readable." >&2
  exit 2
}

case "${CLIENT}" in
  argocd-prod)
    client_id=ops-argocd-prod
    namespace=argocd
    secret_name=workforce-oidc
    secret_shape=standard
    ;;
  argocd-dev)
    client_id=ops-argocd-dev
    namespace=argocd
    secret_name=workforce-oidc
    secret_shape=standard
    ;;
  headlamp-prod)
    client_id=ops-headlamp-prod
    namespace=headlamp
    secret_name=workforce-oidc
    secret_shape=headlamp
    callback_url=https://headlamp.ops.honey.school/oidc-callback
    ;;
  headlamp-dev)
    client_id=ops-headlamp-dev
    namespace=headlamp
    secret_name=workforce-oidc
    secret_shape=headlamp
    callback_url=https://headlamp.dev.ops.honey.school/oidc-callback
    ;;
  jenkins)
    client_id=ops-jenkins
    namespace=jenkins
    secret_name=playsay-workforce-jenkins-oidc
    secret_shape=jenkins
    ;;
  workflows)
    client_id=playsay-release-workflows
    namespace=argo-workflows-system
    secret_name=playsay-release-sso
    secret_shape=standard
    ;;
  metrics-dev)
    client_id=ops-metrics-dev
    namespace=monitoring
    secret_name=workforce-metrics-oidc
    secret_shape=metrics
    ;;
  dev-broker)
    client_id=playsay-dev-workforce-broker
    namespace=keycloak
    secret_name=workforce-broker-oidc
    secret_shape=standard
    ;;
  *)
    echo "Unsupported CLIENT: ${CLIENT}" >&2
    exit 2
    ;;
esac

encoded_id="$(
  kubectl --kubeconfig "${SOURCE_KUBECONFIG}" -n "${SOURCE_NAMESPACE}" \
    get secret "${SOURCE_SECRET}" \
    -o "go-template={{index .data \"${client_id}-client-id\"}}"
)"
encoded_secret="$(
  kubectl --kubeconfig "${SOURCE_KUBECONFIG}" -n "${SOURCE_NAMESPACE}" \
    get secret "${SOURCE_SECRET}" \
    -o "go-template={{index .data \"${client_id}-client-secret\"}}"
)"
[[ -n "${encoded_id}" && -n "${encoded_secret}" ]] || {
  echo "Source secret does not contain ${client_id}." >&2
  exit 3
}
actual_id="$(printf '%s' "${encoded_id}" | base64 -d)"
actual_secret="$(printf '%s' "${encoded_secret}" | base64 -d)"
[[ "${actual_id}" == "${client_id}" && -n "${actual_secret}" ]] || exit 3

kubectl --kubeconfig "${TARGET_KUBECONFIG}" create namespace "${namespace}" \
  --dry-run=client -o yaml |
  kubectl --kubeconfig "${TARGET_KUBECONFIG}" apply -f - >/dev/null

secret_args=()
case "${secret_shape}" in
  standard)
    secret_args=(
      "--from-literal=client-id=${actual_id}"
      "--from-literal=client-secret=${actual_secret}"
    )
    ;;
  headlamp)
    secret_args=(
      "--from-literal=OIDC_CLIENT_ID=${actual_id}"
      "--from-literal=OIDC_CLIENT_SECRET=${actual_secret}"
      "--from-literal=OIDC_ISSUER_URL=${ISSUER}"
      "--from-literal=OIDC_SCOPES=openid,profile,email,groups"
      "--from-literal=OIDC_CALLBACK_URL=${callback_url}"
      "--from-literal=OIDC_USE_PKCE=true"
    )
    ;;
  jenkins)
    jenkins_admin_user="$(
      kubectl --kubeconfig "${TARGET_KUBECONFIG}" -n jenkins \
        get secret jenkins -o jsonpath='{.data.jenkins-admin-user}' 2>/dev/null |
        base64 -d || true
    )"
    jenkins_admin_password="$(
      kubectl --kubeconfig "${TARGET_KUBECONFIG}" -n jenkins \
        get secret jenkins -o jsonpath='{.data.jenkins-admin-password}' 2>/dev/null |
        base64 -d || true
    )"
    if [[ -z "${jenkins_admin_user}" || -z "${jenkins_admin_password}" ]]; then
      jenkins_admin_user=playsay-breakglass
      jenkins_admin_password="$(openssl rand -base64 36 | tr -d '\n')"
      kubectl --kubeconfig "${TARGET_KUBECONFIG}" -n jenkins \
        create secret generic jenkins \
        --from-literal=jenkins-admin-user="${jenkins_admin_user}" \
        --from-literal=jenkins-admin-password="${jenkins_admin_password}" \
        --dry-run=client -o yaml |
        kubectl --kubeconfig "${TARGET_KUBECONFIG}" apply -f - >/dev/null
    fi
    secret_args=(
      "--from-literal=client-id=${actual_id}"
      "--from-literal=client-secret=${actual_secret}"
      "--from-literal=escape-hatch-username=${jenkins_admin_user}"
      "--from-literal=escape-hatch-secret=${jenkins_admin_password}"
    )
    ;;
  metrics)
    cookie_secret="$(
      kubectl --kubeconfig "${TARGET_KUBECONFIG}" -n "${namespace}" \
        get secret "${secret_name}" -o jsonpath='{.data.cookie-secret}' 2>/dev/null |
        base64 -d || true
    )"
    [[ -n "${cookie_secret}" ]] || cookie_secret="$(openssl rand -base64 32 | tr -d '\n')"
    secret_args=(
      "--from-literal=client-id=${actual_id}"
      "--from-literal=client-secret=${actual_secret}"
      "--from-literal=cookie-secret=${cookie_secret}"
    )
    ;;
esac

kubectl --kubeconfig "${TARGET_KUBECONFIG}" -n "${namespace}" \
  create secret generic "${secret_name}" "${secret_args[@]}" \
  --dry-run=client -o yaml |
  kubectl --kubeconfig "${TARGET_KUBECONFIG}" apply -f - >/dev/null

unset actual_id actual_secret encoded_id encoded_secret cookie_secret
unset callback_url jenkins_admin_user jenkins_admin_password secret_args
echo "OIDC client ${client_id} was synchronized to ${namespace}/${secret_name} without printing credentials."
