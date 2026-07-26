#!/usr/bin/env bash
set -Eeuo pipefail

export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

kubectl -n argo-workflows-system rollout status deployment/argo-workflows-workflow-controller --timeout=300s
kubectl -n argo-workflows-system rollout status deployment/argo-workflows-server --timeout=300s
[[ "$(kubectl -n argo-workflows-system get service argo-workflows-server -o jsonpath='{.spec.type}')" == "NodePort" ]]
[[ "$(kubectl -n argo-workflows-system get service argo-workflows-server -o jsonpath='{.spec.ports[0].nodePort}')" == "32088" ]]

controller_config="$(
  kubectl -n argo-workflows-system get configmap argo-workflows-workflow-controller-configmap -o yaml
)"
grep -q 'templateReferencing: Secure' <<<"${controller_config}"

for template in playsay-production-promotion playsay-production-rollback; do
  kubectl -n playsay-release-system get workflowtemplate "${template}" >/dev/null
done

kubectl auth can-i patch applications.argoproj.io/playsay-prod-root \
  -n argocd \
  --as=system:serviceaccount:playsay-release-system:release-argocd |
  grep -qx yes
kubectl auth can-i get secrets \
  -n playsay-prod \
  --as=system:serviceaccount:playsay-release-system:release-argocd |
  grep -qx no
kubectl auth can-i create jobs.batch \
  -n playsay-prod \
  --as=system:serviceaccount:playsay-release-system:release-migrator |
  grep -qx yes
kubectl auth can-i get secrets \
  -n playsay-prod \
  --as=system:serviceaccount:playsay-release-system:release-migrator |
  grep -qx no

image="$(
  kubectl -n playsay-release-system get workflowtemplate playsay-production-promotion \
    -o json |
    jq -r '.spec.arguments.parameters[] | select(.name == "releaseOpsImage") | .value'
)"
[[ "${image}" =~ @sha256:[0-9a-f]{64}$ ]] || {
  echo "Installed WorkflowTemplate does not pin the release-ops image by digest." >&2
  exit 1
}

echo "Argo Workflows controller, templates, immutable image and least-privilege RBAC are valid."
