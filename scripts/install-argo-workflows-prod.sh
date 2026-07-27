#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_PATH="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
ARGO_WORKFLOWS_CHART_VERSION="1.0.23"
ARGO_WORKFLOWS_CHART_SHA256="a20365b94f3c286eed01c1ca7bd1ec428efa002f5610f140dd4c933322d6bc6d"
WORKFLOWS_HOST="${WORKFLOWS_HOST:-workflows.ops.honey.school}"
EXPECTED_EDGE_IP="${EXPECTED_EDGE_IP:-65.109.55.110}"
: "${RELEASE_OPS_IMAGE:?Set RELEASE_OPS_IMAGE to ghcr.io/mednov-ai/playsay-release-ops@sha256:<digest>}"

[[ "${RELEASE_OPS_IMAGE}" =~ ^ghcr\.io/mednov-ai/playsay-release-ops@sha256:[0-9a-f]{64}$ ]] || {
  echo "RELEASE_OPS_IMAGE must be an immutable GHCR digest." >&2
  exit 2
}
for command_name in kubectl helm yq sha256sum dig git jq; do
  command -v "${command_name}" >/dev/null || {
    echo "Missing required command: ${command_name}" >&2
    exit 2
  }
done
export KUBECONFIG="${KUBECONFIG_PATH}"
kubectl cluster-info >/dev/null

current_release="$(
  git -C "${ROOT_DIR}" show HEAD:argocd-apps/prod/current-release.txt |
    tr -d '[:space:]'
)"
[[ "${current_release}" == "release/1.001.07" ]] || {
  echo "Activation is pinned to the accepted release/1.001.07 baseline; found ${current_release}." >&2
  exit 3
}

resolved_edge="$(dig +short "${WORKFLOWS_HOST}" A | tail -n 1)"
[[ "${resolved_edge}" == "${EXPECTED_EDGE_IP}" ]] || {
  echo "${WORKFLOWS_HOST} must resolve to ${EXPECTED_EDGE_IP}; found ${resolved_edge:-nothing}." >&2
  exit 3
}

check_secret_keys() {
  local namespace="$1"
  local secret="$2"
  shift 2
  kubectl -n "${namespace}" get secret "${secret}" >/dev/null 2>&1 || {
    echo "Missing Secret ${namespace}/${secret}." >&2
    exit 3
  }
  local key
  for key in "$@"; do
    kubectl -n "${namespace}" get secret "${secret}" -o json |
      jq -e --arg key "${key}" '.data[$key] | length > 0' >/dev/null || {
      echo "Secret ${namespace}/${secret} is missing key ${key}." >&2
      exit 3
    }
  done
}

check_secret_keys argo-workflows-system playsay-release-sso client-id client-secret
check_secret_keys playsay-release-system playsay-release-github app-id installation-id private-key.pem
for namespace in playsay-data keycloak storage; do
  check_secret_keys "${namespace}" playsay-release-backup \
    endpoint region bucket access-key secret-key age-recipient
done

readiness="$(
  kubectl -n playsay-release-system get configmap playsay-release-backup-readiness -o json 2>/dev/null || true
)"
jq -e '
  .data["bucket-versioning"] == "Enabled"
  and .data["object-lock"] == "Enabled"
  and (.data["restore-drill-id"] | length > 0)
' <<<"${readiness}" >/dev/null || {
  echo "Backup versioning/Object Lock/restore drill readiness is not recorded." >&2
  exit 3
}

work_dir="$(mktemp -d /tmp/playsay-argo-workflows-install.XXXXXX)"
trap 'rm -rf "${work_dir}"' EXIT
helm repo add argo https://argoproj.github.io/argo-helm --force-update >/dev/null
helm repo update argo >/dev/null
helm pull argo/argo-workflows \
  --version "${ARGO_WORKFLOWS_CHART_VERSION}" \
  --destination "${work_dir}"
chart="${work_dir}/argo-workflows-${ARGO_WORKFLOWS_CHART_VERSION}.tgz"
echo "${ARGO_WORKFLOWS_CHART_SHA256}  ${chart}" | sha256sum -c - >/dev/null

kubectl create namespace argo-workflows-system --dry-run=client -o yaml |
  kubectl apply -f - >/dev/null
kubectl create namespace playsay-release-system --dry-run=client -o yaml |
  kubectl apply -f - >/dev/null

helm upgrade --install argo-workflows "${chart}" \
  --namespace argo-workflows-system \
  --values "${ROOT_DIR}/argo-workflows/values-prod.yaml" \
  --wait \
  --timeout 10m

RELEASE_OPS_IMAGE="${RELEASE_OPS_IMAGE}" \
  kubectl kustomize \
    --load-restrictor=LoadRestrictionsNone \
    "${ROOT_DIR}/kustomize/argo-workflows-production" |
  RELEASE_OPS_IMAGE="${RELEASE_OPS_IMAGE}" yq '
    if .kind == "WorkflowTemplate" then
      (.spec.arguments.parameters[] | select(.name == "releaseOpsImage").value) = strenv(RELEASE_OPS_IMAGE)
    else .
    end
  ' |
  kubectl apply -f -

"${ROOT_DIR}/scripts/validate-argo-workflows-prod.sh"
echo "Argo Workflows production control plane is installed; submit release/1.001.08 only after its reviewed schema v2 candidate is ready."
