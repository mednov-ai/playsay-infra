#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
JENKINS_CHART_VERSION="${JENKINS_CHART_VERSION:-5.9.22}"
JENKINS_NODEPORT_HTTP="${JENKINS_NODEPORT_HTTP:-32082}"

for command_name in kubectl helm curl sed grep mktemp; do
  command -v "$command_name" >/dev/null || { echo "Missing command: $command_name" >&2; exit 1; }
done

kubectl cluster-info >/dev/null

helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets >/dev/null 2>&1 || true
helm repo add jenkins https://charts.jenkins.io >/dev/null 2>&1 || true
helm repo update sealed-secrets jenkins >/dev/null

kubectl create namespace sealed-secrets --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace sealed-secrets \
  --wait \
  --timeout 10m

kubectl create namespace jenkins --dry-run=client -o yaml | kubectl apply -f -

if ! kubectl -n jenkins get secret playsay-jenkins-credentials >/dev/null 2>&1; then
  echo "Missing jenkins/playsay-jenkins-credentials. Transfer or rotate credentials before installing Jenkins." >&2
  exit 1
fi

for required_key in github-token webhook-token; do
  encoded_value="$(kubectl -n jenkins get secret playsay-jenkins-credentials -o "jsonpath={.data.${required_key}}")"
  [[ -n "$encoded_value" ]] || { echo "Missing key in playsay-jenkins-credentials: $required_key" >&2; exit 1; }
done

kubectl -n jenkins apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: jenkins-agent-cache
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 30Gi
EOF

helm upgrade --install jenkins jenkins/jenkins \
  --version "$JENKINS_CHART_VERSION" \
  --namespace jenkins \
  --values "$REPO_ROOT/jenkins/values-ci.yaml" \
  --set-file controller.JCasC.configScripts.playsay-appearance="$REPO_ROOT/jenkins/jcasc/playsay-appearance.yaml" \
  --set-file controller.JCasC.configScripts.playsay-credentials="$REPO_ROOT/jenkins/jcasc/playsay-credentials.yaml" \
  --wait \
  --timeout 15m

jenkins_apply_config_tmp="$(mktemp)"
jenkins_patch_tmp="$(mktemp)"
trap 'rm -f "$jenkins_apply_config_tmp" "$jenkins_patch_tmp"' EXIT

kubectl -n jenkins get configmap jenkins -o jsonpath='{.data.apply_config\.sh}' >"$jenkins_apply_config_tmp"
if grep -q 'yes n | cp -i /usr/share/jenkins/ref/plugins/\* /var/jenkins_plugins/;' "$jenkins_apply_config_tmp"; then
  sed -i.bak 's#yes n | cp -i /usr/share/jenkins/ref/plugins/\* /var/jenkins_plugins/;#cp -f /usr/share/jenkins/ref/plugins/* /var/jenkins_plugins/;#' "$jenkins_apply_config_tmp"
  {
    printf 'data:\n  apply_config.sh: |\n'
    sed 's/^/    /' "$jenkins_apply_config_tmp"
  } >"$jenkins_patch_tmp"
  kubectl -n jenkins patch configmap jenkins --type merge --patch-file "$jenkins_patch_tmp"
  kubectl -n jenkins delete pod jenkins-0 --wait=false
fi

kubectl -n jenkins rollout status statefulset/jenkins --timeout=15m
JENKINS_URL="http://127.0.0.1:${JENKINS_NODEPORT_HTTP}" \
  JENKINS_NODEPORT_HTTP="$JENKINS_NODEPORT_HTTP" \
  "$REPO_ROOT/scripts/configure-jenkins-jobs.sh"

kubectl -n jenkins get statefulset,pod,service,pvc
