#!/usr/bin/env bash
set -Eeuo pipefail

: "${ENVIRONMENT:?Set ENVIRONMENT to dev or prod}"
case "${ENVIRONMENT}" in
  dev)
    ARGOCD_VALUES=argocd-dev-values.yaml
    HEADLAMP_VALUES=headlamp-dev-values.yaml
    HEADLAMP_RBAC=headlamp-rbac-dev.yaml
    HEADLAMP_CLIENT_ID=ops-headlamp-dev
    ;;
  prod)
    ARGOCD_VALUES=argocd-prod-values.yaml
    HEADLAMP_VALUES=headlamp-prod-values.yaml
    HEADLAMP_RBAC=headlamp-rbac-prod.yaml
    HEADLAMP_CLIENT_ID=ops-headlamp-prod
    ;;
  *)
    echo "ENVIRONMENT must be dev or prod." >&2
    exit 2
    ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_PATH="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
OIDC_ISSUER=https://ops.honey.school/keycloak/realms/workforce
for command_name in kubectl helm jq openssl; do
  command -v "${command_name}" >/dev/null || exit 2
done
export KUBECONFIG="${KUBECONFIG_PATH}"
kubectl cluster-info >/dev/null

required_secret() {
  local namespace="$1"
  local name="$2"
  shift 2
  kubectl -n "${namespace}" get secret "${name}" >/dev/null 2>&1 || {
    echo "Missing Secret ${namespace}/${name}." >&2
    exit 3
  }
  local key
  for key in "$@"; do
    kubectl -n "${namespace}" get secret "${name}" -o json |
      jq -e --arg key "${key}" '.data[$key] | length > 0' >/dev/null || {
      echo "Secret ${namespace}/${name} is missing ${key}." >&2
      exit 3
    }
  done
}

required_secret argocd workforce-oidc client-id client-secret
required_secret headlamp workforce-oidc \
  OIDC_CLIENT_ID OIDC_CLIENT_SECRET OIDC_ISSUER_URL OIDC_SCOPES \
  OIDC_CALLBACK_URL OIDC_USE_PKCE

argocd_client_secret="$(
  kubectl -n argocd get secret workforce-oidc -o jsonpath='{.data.client-secret}'
)"
kubectl -n argocd patch secret argocd-secret --type merge \
  -p "$(jq -cn --arg value "${argocd_client_secret}" \
    '{data:{"oidc.workforce.clientSecret":$value}}')" >/dev/null
unset argocd_client_secret

helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/ >/dev/null 2>&1 || true
helm repo update argo headlamp >/dev/null

argocd_chart="$(
  helm list -n argocd -o json |
    jq -r '.[] | select(.name == "argocd") | .chart'
)"
headlamp_chart="$(
  helm list -n headlamp -o json |
    jq -r '.[] | select(.name == "headlamp") | .chart'
)"
[[ "${argocd_chart}" =~ ^argo-cd-[0-9] ]] || {
  echo "Installed ArgoCD chart version could not be resolved." >&2
  exit 3
}
[[ "${headlamp_chart}" =~ ^headlamp-[0-9] ]] || {
  echo "Installed Headlamp chart version could not be resolved." >&2
  exit 3
}
argocd_version="${argocd_chart#argo-cd-}"
headlamp_version="${headlamp_chart#headlamp-}"

helm upgrade argocd argo/argo-cd \
  --version "${argocd_version}" \
  --namespace argocd \
  --reuse-values \
  --values "${ROOT_DIR}/workforce-sso/${ARGOCD_VALUES}" \
  --wait --timeout 10m

helm upgrade headlamp headlamp/headlamp \
  --version "${headlamp_version}" \
  --namespace headlamp \
  --reuse-values \
  --values "${ROOT_DIR}/workforce-sso/${HEADLAMP_VALUES}" \
  --wait --timeout 10m
kubectl apply -f "${ROOT_DIR}/workforce-sso/${HEADLAMP_RBAC}"

if [[ "${ENVIRONMENT}" == "dev" ]]; then
  required_secret monitoring workforce-metrics-oidc client-id client-secret cookie-secret
  kubectl apply -f "${ROOT_DIR}/workforce-sso/metrics-oauth2-proxy-dev.yaml"
  kubectl -n monitoring rollout status deployment/workforce-metrics-oauth2-proxy --timeout=5m
fi

kubectl -n argocd rollout status deployment/argocd-server --timeout=5m
kubectl -n headlamp rollout status deployment/headlamp --timeout=5m
echo "Workforce SSO is configured for ${ENVIRONMENT}; issuer ${OIDC_ISSUER}, Headlamp client ${HEADLAMP_CLIENT_ID}."
