# AX41 scoped Liquibase Job proof — 2026-07-21

This record contains no credentials or personal data.

## Revisions and live boundary

- Platform branch: `codex/separate-jenkins-ci`
- Platform revision: `a8aded8`
- Infrastructure branch: `codex/separate-jenkins-ci`
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
