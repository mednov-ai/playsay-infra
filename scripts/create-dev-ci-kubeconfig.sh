#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
DEV_API_SERVER="${DEV_API_SERVER:-https://10.60.0.30:6443}"
OUTPUT_FILE="${1:-}"

[[ -n "$OUTPUT_FILE" ]] || { echo "Usage: $0 OUTPUT_FILE" >&2; exit 2; }
command -v kubectl >/dev/null || { echo "kubectl is required" >&2; exit 1; }

kubectl apply -k "$REPO_ROOT/kustomize/jenkins-remote-deployer"

for _ in $(seq 1 30); do
  token="$(kubectl -n playsay-ci-access get secret playsay-ci-deployer-token -o jsonpath='{.data.token}' 2>/dev/null | base64 -d || true)"
  ca_data="$(kubectl -n playsay-ci-access get secret playsay-ci-deployer-token -o jsonpath='{.data.ca\.crt}' 2>/dev/null || true)"
  [[ -n "$token" && -n "$ca_data" ]] && break
  sleep 1
done

[[ -n "${token:-}" && -n "${ca_data:-}" ]] || { echo "Service-account token was not populated" >&2; exit 1; }

umask 077
kubectl config --kubeconfig="$OUTPUT_FILE" set-cluster playsay-dev \
  --server="$DEV_API_SERVER" \
  --certificate-authority=<(printf '%s' "$ca_data" | base64 -d) \
  --embed-certs=true >/dev/null
kubectl config --kubeconfig="$OUTPUT_FILE" set-credentials playsay-ci-deployer --token="$token" >/dev/null
kubectl config --kubeconfig="$OUTPUT_FILE" set-context playsay-dev \
  --cluster=playsay-dev \
  --user=playsay-ci-deployer \
  --namespace=playsay-dev >/dev/null
kubectl config --kubeconfig="$OUTPUT_FILE" use-context playsay-dev >/dev/null
chmod 600 "$OUTPUT_FILE"

KUBECONFIG="$OUTPUT_FILE" kubectl auth can-i get deployment -n playsay-dev | grep -qx yes
KUBECONFIG="$OUTPUT_FILE" kubectl auth can-i patch application/api-gateway -n argocd | grep -qx yes
KUBECONFIG="$OUTPUT_FILE" kubectl auth can-i get secret -n playsay-data | grep -qx no
KUBECONFIG="$OUTPUT_FILE" kubectl auth can-i '*' '*' -n playsay-prod | grep -qx no

echo "Scoped dev kubeconfig created and negative prod/secret checks passed: $OUTPUT_FILE"
