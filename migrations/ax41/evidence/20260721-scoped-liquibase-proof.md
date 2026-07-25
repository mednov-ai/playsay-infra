# AX41 scoped Liquibase Job proof — 2026-07-21

This record contains no credentials or personal data.

## Revisions and live boundary

- Platform branch: `codex/separate-jenkins-ci`
- Platform revision: `a8aded8`
- Infrastructure branch: `codex/separate-jenkins-ci`
- Infrastructure revision: `d6a77af`
- Dev identity: `system:serviceaccount:playsay-ci-access:playsay-ci-deployer`
- Target namespace: `playsay-dev`

The CI identity may create/delete only `playsay-migrate-*` Jobs and
`playsay-migration-*` ConfigMaps in dev. It may read rollout/ArgoCD status, but
cannot read Secrets, create Pods, access prod, or obtain a service-account token
inside the migration Job. A ValidatingAdmissionPolicy fixes the Liquibase image,
driver download, command, resources, volumes, non-privileged security context
and the three allowed keys from `playsay-app-db` or `playsay-keyboard-db`.

An attempted non-conforming privileged Job was denied by admission. The reviewed
API Gateway migration Job was then created using the same scoped kubeconfig held
by Jenkins. It mounted the DB Secret only inside dev, found the 39 existing
Liquibase history rows restored from the old VPS, reported no pending API
changesets and completed successfully. The launcher removed the temporary Job
and ConfigMap after completion.

The history count was checked independently on old dev, new dev and new prod;
all three contained 39 application changelog rows and one lock row. No
`changelog-sync`, manual baseline or schema/data rewrite was performed.

## Pipeline cleanup

- All module and aggregate Jenkinsfiles now invoke
  `scripts/ci/run-dev-liquibase-job.sh` for owned DB migrations.
- Jenkins agent pod templates no longer contain Liquibase containers or DB
  Secret references.
- Legacy capacity acquire/restore stages, `capacity-guard` sidecars, watchdog,
  state ConfigMap/Lease and capacity-manager manifests were removed from Git.
- The compatibility ConfigMap was deleted from the dedicated CI cluster; legacy
  resources on the old rollback VPS were deliberately left untouched.
- Four CI boundary tests passed and all 13 Jenkinsfiles passed the live Jenkins
  declarative-pipeline validator.

This closes the technical CI/Liquibase blocker for retiring the old VPS. The
remaining gates are owner-operated login/material acceptance, real-device VPN
handshakes, the stabilization window and explicit approval to delete the VPS.

## End-to-end Jenkins proof

After both revisions were pushed, `playsay-api-gateway-develop` build `1` ran
from platform revision `a8aded849378` and completed `SUCCESS` in 928.260
seconds. Checkout, test/package, OpenAPI contract, scoped DB migrate, image
build/push, source tag, GitOps update, ArgoCD rollout wait and post actions all
succeeded.

- Build label/image tag: `api-codex-separate-jenkins-ci-1`
- Dev GitOps revision: `ac9ba89da113b0e6fe86fde8b777fcbb329b3800`
- Dev ArgoCD API application: `Synced/Healthy`
- Dev API deployment: `1/1` ready on the exact new tag
- Generated migration Job/ConfigMap after completion: absent
- CI controller after build: `2/2` ready, zero restarts
- Prod after build: zero unready pods, zero unhealthy/out-of-sync ArgoCD apps,
  approximately 31 GiB available RAM
