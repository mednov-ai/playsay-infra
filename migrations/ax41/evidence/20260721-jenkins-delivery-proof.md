# AX41 dedicated Jenkins delivery proof — 2026-07-21

This record contains no credentials or personal data.

## Revisions

- Infrastructure branch: `codex/separate-jenkins-ci`
- Infrastructure bootstrap revision: `8d1f244`
- Platform branch: `codex/separate-jenkins-ci`
- Platform pipeline revision: `51c6e225ab9a`
- Jenkins-created dev GitOps revision: `c0ea1613aa19f212dd59c8d33446fb67c2567eab`
- Jenkins-created source tag: `collab-codex-separate-jenkins-ci-1`

## CI boundary

- `playsay-ci` is `10.60.0.40`, with 2 vCPU, 8 GiB RAM and a 100 GiB disk.
- Jenkins chart `5.9.22` runs at app version `2.555.2` with controller pod `2/2 Running`.
- The controller PVC is 16 GiB and the one-agent cache PVC is 30 GiB.
- Jenkins holds a scoped dev kubeconfig. Authorization checks deny secret reads and prod access.
- No ArgoCD, Keycloak, MinIO or product application runs in the CI cluster.
- Jenkins has no production kubeconfig and does not run OpenTofu.

## Affected-target proof

Job `playsay-collaboration-service-develop` build `1` ran from platform commit
`51c6e225ab9a` and completed `SUCCESS` in 191.538 seconds.

Every stage succeeded:

1. Checkout
2. Reserve build capacity (initial dedicated-CI no-op compatibility stage; removed by later revision `a8aded8`)
3. Test and build
4. Build and push image
5. Tag source commit
6. Update dev image tag
7. Wait for rollout
8. Post actions

The build pushed `ghcr.io/mednov-ai/playsay-collaboration-service:collab-codex-separate-jenkins-ci-1`, committed the dev values update as `c0ea161`, and waited until the dev ArgoCD application reported `Synced/Healthy`. The running dev deployment then reported that exact image and `1/1` ready replicas.

During and after the build, the prod node stayed `Ready` and all 15 prod ArgoCD applications stayed `Synced/Healthy`. At the post-build check the prod guest load averages were `0.14`, `0.10`, `0.11`.

## Cutover work completed after this proof

- The eight-host edge/TLS configuration was published and verified.
- The canonical Keycloak issuer moved from `key.*` to `ops.*` with matching backend/frontend configuration.
- Both GitHub webhooks were repointed to `hooks.honey.school` and returned 200 to GitHub ping deliveries.
- Web and keyboard release builds completed successfully and production was manually promoted through infra `release/1.001.01` without granting Jenkins production access.
- A final encrypted source-VPS bundle was copied off the VPS and fully decrypted/checksum-verified.

## Remaining gates

- Database-backed module jobs were enabled by later revision `a8aded8`; the scoped Job proof is recorded separately.
- Complete owner-operated Maria/student login and rendered-material checks.
- Stop the old controller after stabilization and delete the VPS only with explicit owner approval.
