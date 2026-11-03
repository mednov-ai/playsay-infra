# DEV stack-upgrade preparation — 2026-11-03

Status: prepared, **not yet delivered**. Platform hotfix source at this
checkpoint is `ca1e6d401048a42f7a21f3557d2388ba0f89f2bb`; rerun candidate
gates if its head moves. The production rollout is outside this DEV step.

Before any PostgreSQL restart, the DEV guest retained a protected fresh
four-database backup at
`/var/backups/playsay/stack-upgrade-dev-20261103T173744Z`. The application,
keyboard, worksheet-import and Keycloak custom archives passed checksums and
PostgreSQL 17 catalog validation. A temporary isolated PostgreSQL 17 instance
restored all four with `--exit-on-error` and `--no-owner --no-privileges`;
the restored public schema contained 93, 11, 5 and 101 tables respectively.
The same four backups were then restored into the intended CNPG PostgreSQL
`17.11 (Debian 17.11-1.pgdg13+2)` image, with the same table counts. The
temporary pods were deleted. This verifies those four archive restores, not a
coordinated application/object-store disaster recovery.

An earlier task-created attempt at
`/var/backups/playsay/stack-upgrade-dev-20261103T173353Z` was not validated
because a temporary path was read-only. It remains protected and is marked
`INCOMPLETE.txt`; it must not be treated as a verified backup.

At the preliminary activity observation, the DEV authoritative lesson
windows, LiveKit rooms/participants, collaboration connections and snapshot
queue were zero. This is historical evidence only: refresh admission, drain,
host capacity, backup currency and live revisions immediately before a
rollout. The application database was healthy on PostgreSQL 17.6; its
separate Keycloak database remained on Bitnami legacy PostgreSQL 17.4.

Full exact-candidate CI, a GitOps rollout and authenticated multi-student
classroom/media acceptance on DEV are still pending. The platform's previous
local tests and preliminary security findings are recorded in its
`docs/security/2026-11-03-stack-upgrade-local.md`.
