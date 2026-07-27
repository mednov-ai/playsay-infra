#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for command_name in bash helm kubectl yq; do
  command -v "${command_name}" >/dev/null || {
    echo "Missing test dependency: ${command_name}" >&2
    exit 2
  }
done

for script in \
  "${ROOT_DIR}"/scripts/argo-workflows/*.sh \
  "${ROOT_DIR}/scripts/build-release-ops-image.sh" \
  "${ROOT_DIR}/scripts/configure-keycloak-prod-workflows.sh" \
  "${ROOT_DIR}/scripts/install-argo-workflows-prod.sh" \
  "${ROOT_DIR}/scripts/record-release-backup-readiness.sh" \
  "${ROOT_DIR}/scripts/validate-argo-workflows-prod.sh" \
  "${ROOT_DIR}/argo-workflows/release-ops/backup.sh"
do
  bash -n "${script}"
done

work_dir="$(mktemp -d /tmp/playsay-argo-workflows-contract.XXXXXX)"
trap 'rm -rf "${work_dir}"' EXIT
rendered="${work_dir}/rendered.yaml"
kubectl kustomize \
  --load-restrictor=LoadRestrictionsNone \
  "${ROOT_DIR}/kustomize/argo-workflows-production" > "${rendered}"

for kind_name in \
  "WorkflowTemplate/playsay-production-promotion" \
  "WorkflowTemplate/playsay-production-rollback" \
  "ServiceAccount/release-validator" \
  "ServiceAccount/release-backup" \
  "ServiceAccount/release-migrator" \
  "ServiceAccount/release-argocd" \
  "ServiceAccount/release-git-updater"
do
  kind="${kind_name%/*}"
  name="${kind_name#*/}"
  yq -e \
    "select(.kind == \"${kind}\" and .metadata.name == \"${name}\")" \
    "${rendered}" >/dev/null
done

promotion="${ROOT_DIR}/kustomize/argo-workflows-production/workflow-template-promotion.yaml"
rollback="${ROOT_DIR}/kustomize/argo-workflows-production/workflow-template-rollback.yaml"
[[ "$(yq -r '.spec.synchronization.mutexes[0].name' "${promotion}")" == "playsay-production-operation" ]]
[[ "$(yq -r '.spec.synchronization.mutexes[0].name' "${rollback}")" == "playsay-production-operation" ]]
[[ "$(yq -r '[.spec.templates[] | select(.name == "promote").dag.tasks[] | select(.name == "approve-backup" or .name == "approve-deploy")] | length' "${promotion}")" == "2" ]]
grep -q '{{workflow.parameters.dryRun}} == true' "${promotion}"
grep -q '{{workflow.parameters.dryRun}} == false' "${promotion}"
grep -q '{{workflow.parameters.dryRun}} == true' "${rollback}"
grep -q '{{workflow.parameters.dryRun}} == false' "${rollback}"
grep -q "schemaVersion" "${ROOT_DIR}/scripts/argo-workflows/validate-candidate.sh"
grep -q "infraSha" "${ROOT_DIR}/scripts/argo-workflows/validate-candidate.sh"
grep -q "approved_count" "${ROOT_DIR}/scripts/argo-workflows/validate-candidate.sh"
grep -q "rollback-on-failure" "${promotion}"
grep -q "status.failed > 0" "${promotion}"
grep -q 'git add argocd-apps/prod/current-release.txt' \
  "${ROOT_DIR}/scripts/argo-workflows/update-current-release.sh"
if grep -q 'git add .*promotion-history' \
  "${ROOT_DIR}/scripts/argo-workflows/update-current-release.sh"; then
  echo "The current-release PR must change only current-release.txt." >&2
  exit 1
fi
grep -q 'versioning' "${ROOT_DIR}/argo-workflows/release-ops/backup.sh"
grep -q 'Object Lock' "${ROOT_DIR}/argo-workflows/release-ops/backup.sh"
grep -q 'age --encrypt' "${ROOT_DIR}/argo-workflows/release-ops/backup.sh"
grep -q 'release/1.001.07' "${ROOT_DIR}/argocd-apps/prod/current-release.txt"
grep -q 'release/1.001.07' "${ROOT_DIR}/argocd-apps/prod/promotion-history/1-001-07.yaml"

helm repo add argo https://argoproj.github.io/argo-helm --force-update >/dev/null
helm template argo-workflows argo/argo-workflows \
  --version 1.0.23 \
  --namespace argo-workflows-system \
  --values "${ROOT_DIR}/argo-workflows/values-prod.yaml" \
  > "${work_dir}/helm.yaml"
grep -q 'templateReferencing: Secure' "${work_dir}/helm.yaml"
grep -q 'nodePort: 32088' "${work_dir}/helm.yaml"
grep -q 'https://workflows.ops.honey.school/oauth2/callback' "${work_dir}/helm.yaml"
grep -q 'https://ops.honey.school/keycloak/realms/workforce' "${work_dir}/helm.yaml"

if rg -n '^(data|stringData):' "${ROOT_DIR}/kustomize/argo-workflows-production" |
  grep -v 'prod-liquibase-runner.yaml'; then
  echo "Plain Kubernetes Secret data must not be committed." >&2
  exit 1
fi

echo "Argo Workflows production contracts are valid."
