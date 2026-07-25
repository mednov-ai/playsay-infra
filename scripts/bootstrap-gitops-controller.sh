#!/usr/bin/env bash
set -Eeuo pipefail

environment_name="${1:-}"
case "$environment_name" in
  dev|prod) ;;
  *) echo "Usage: $0 dev|prod" >&2; exit 2 ;;
esac

helm_version="v3.21.0"
argocd_chart_version="10.1.4"
sealed_secrets_version="0.37.0"
sealed_secrets_manifest_sha256="70438d647f716a634afbbec713aaeb8f6e031d74528d8043ae2b090c41bc923c"
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
work_dir="$(mktemp -d)"
trap 'rm -rf -- "$work_dir"' EXIT

if ! command -v helm >/dev/null; then
  installer="$work_dir/get-helm-3"
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o "$installer"
  chmod 0700 "$installer"
  "$installer" --version "$helm_version"
fi

kubectl cluster-info >/dev/null
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo update >/dev/null

kubectl create namespace sealed-secrets --dry-run=client -o yaml | kubectl apply -f -
sealed_secrets_manifest="$work_dir/sealed-secrets-controller.yaml"
curl -fsSL \
  "https://github.com/bitnami/sealed-secrets/releases/download/v${sealed_secrets_version}/controller.yaml" \
  -o "$sealed_secrets_manifest"
printf '%s  %s\n' "$sealed_secrets_manifest_sha256" "$sealed_secrets_manifest" | sha256sum -c -
sed -i 's/namespace: kube-system/namespace: sealed-secrets/g' "$sealed_secrets_manifest"
kubectl apply -f "$sealed_secrets_manifest"

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --version "$argocd_chart_version" \
  --set configs.params."server\\.insecure"=true \
  --set configs.params."server\\.basehref"=/argocd \
  --set configs.params."server\\.rootpath"=/argocd \
  --set server.service.type=NodePort \
  --set server.service.nodePortHttp=32080 \
  --set server.ingress.enabled=false \
  --wait --timeout 10m

kubectl -n sealed-secrets rollout status deployment/sealed-secrets-controller --timeout=5m
kubectl -n argocd rollout status deployment/argocd-server --timeout=5m
echo "GitOps controllers are ready in the ${environment_name} cluster"
