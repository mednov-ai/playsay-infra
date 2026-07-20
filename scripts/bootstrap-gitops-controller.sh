#!/usr/bin/env bash
set -Eeuo pipefail

environment_name="${1:-}"
case "$environment_name" in
  dev|prod) ;;
  *) echo "Usage: $0 dev|prod" >&2; exit 2 ;;
esac

helm_version="v3.21.0"
argocd_chart_version="10.1.4"
sealed_secrets_chart_version="2.18.6"
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

if ! command -v helm >/dev/null; then
  installer="$(mktemp)"
  trap 'rm -f -- "$installer"' EXIT
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o "$installer"
  chmod 0700 "$installer"
  "$installer" --version "$helm_version"
fi

kubectl cluster-info >/dev/null
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets >/dev/null
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo update >/dev/null

kubectl create namespace sealed-secrets --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace sealed-secrets \
  --version "$sealed_secrets_chart_version" \
  --wait --timeout 10m

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

kubectl -n sealed-secrets rollout status deployment/sealed-secrets --timeout=5m
kubectl -n argocd rollout status deployment/argocd-server --timeout=5m
echo "GitOps controllers are ready in the ${environment_name} cluster"
