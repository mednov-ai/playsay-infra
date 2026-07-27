#!/usr/bin/env bash
set -Eeuo pipefail

: "${ENVIRONMENT:?Set ENVIRONMENT to dev or prod}"
case "${ENVIRONMENT}" in
  dev)
    argocd_host=argocd.dev.ops.honey.school
    headlamp_host=headlamp.dev.ops.honey.school
    ;;
  prod)
    argocd_host=argocd.ops.honey.school
    headlamp_host=headlamp.ops.honey.school
    ;;
  *)
    echo "ENVIRONMENT must be dev or prod." >&2
    exit 2
    ;;
esac

export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
issuer=https://ops.honey.school/keycloak/realms/workforce
for command_name in kubectl curl jq; do
  command -v "${command_name}" >/dev/null || exit 2
done

curl -fsS "${issuer}/.well-known/openid-configuration" |
  jq -e --arg issuer "${issuer}" '.issuer == $issuer' >/dev/null
kubectl -n argocd get configmap argocd-cm -o json |
  jq -e --arg issuer "${issuer}" \
    '.data["oidc.config"] | contains($issuer)' >/dev/null
kubectl -n argocd get configmap argocd-cm -o json |
  jq -e --arg url "https://${argocd_host}" '.data.url == $url' >/dev/null
kubectl -n argocd get secret argocd-secret -o json |
  jq -e '.data["oidc.workforce.clientSecret"] | length > 0' >/dev/null
kubectl -n headlamp get deployment headlamp -o json |
  jq -e '
    .spec.template.spec.containers[0].envFrom[]
    | select(.secretRef.name == "workforce-oidc")
  ' >/dev/null
kubectl -n headlamp get secret workforce-oidc -o json |
  jq -e --arg callback "https://${headlamp_host}/oidc-callback" '
    (.data.OIDC_CALLBACK_URL | @base64d) == $callback
    and (.data.OIDC_USE_PKCE | @base64d) == "true"
  ' >/dev/null

if [[ "${ENVIRONMENT}" == "dev" ]]; then
  kubectl -n monitoring rollout status deployment/workforce-metrics-oauth2-proxy --timeout=5m
  kubectl -n argocd get configmap argocd-rbac-cm -o json |
    jq -e '
      .data["policy.csv"]
      | contains("p, role:workforce-developer, applications, sync, */*, allow")
    ' >/dev/null
else
  kubectl -n argocd get configmap argocd-rbac-cm -o json |
    jq -e '
      .data["policy.csv"]
      | contains("g, platform-admins, role:workforce-readonly")
      and (contains("role:workforce-readonly, applications, sync") | not)
    ' >/dev/null
fi

kubectl -n argocd rollout status deployment/argocd-server --timeout=5m
kubectl -n headlamp rollout status deployment/headlamp --timeout=5m
echo "Workforce SSO runtime checks passed for ${ENVIRONMENT}."
