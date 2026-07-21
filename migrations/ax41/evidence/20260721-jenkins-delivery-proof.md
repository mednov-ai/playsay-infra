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
2. Reserve build capacity (dedicated-CI no-op compatibility stage)
3. Test and build
4. Build and push image
5. Tag source commit
6. Update dev image tag
7. Wait for rollout
8. Post actions

The build pushed `ghcr.io/mednov-ai/playsay-collaboration-service:collab-codex-separate-jenkins-ci-1`, committed the dev values update as `c0ea161`, and waited until the dev ArgoCD application reported `Synced/Healthy`. The running dev deployment then reported that exact image and `1/1` ready replicas.

During and after the build, the prod node stayed `Ready` and all 15 prod ArgoCD applications stayed `Synced/Healthy`. At the post-build check the prod guest load averages were `0.14`, `0.10`, `0.11`.

## Remaining cutover gates

- Publish the eight-host edge/TLS configuration.
- Switch the Keycloak public issuer from `key.*` to `ops.*` together with the matching backend/frontend configuration.
- Repoint and verify the GitHub webhooks through `hooks.honey.school`, then disable the old controller/webhooks.
- Redesign database migrations as Jobs inside dev before enabling database-backed module jobs on the separate CI cluster.
- Complete owner-operated Maria/student login and rendered-material checks.
