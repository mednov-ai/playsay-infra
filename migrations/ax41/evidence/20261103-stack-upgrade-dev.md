# DEV stack-upgrade preparation — 2026-11-03

Status: prepared, **not yet delivered**. Platform hotfix source at this
checkpoint is `ca1e6d401048a42f7a21f3557d2388ba0f89f2bb`; rerun candidate
gates if its head moves. The production rollout is outside this DEV step.

The current platform candidate is `1434bc7fc81f0427d9bb0f94d1f463f2c291864f`.
Non-deploy Jenkins web build 416 passed lint, tests and build for that exact
commit; its image and deployment stages did not execute. Full JVM security
previously passed for `d23cd788731da7d60a3c55c67d9351449aa81934`; rerun it
for the current commit. Keycloak native CI and DEV delivery remain pending.

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

A second protected backup at
`/var/backups/playsay/stack-upgrade-dev-20261103T184845Z` used the guarded
active-JDBC selection: the identity source was still Bitnami. All four
checksums and catalogs passed, and a fresh isolated 17.11 restore again found
93, 11, 5 and 101 public tables. The backup must be refreshed immediately
before the actual rollout and after stopping Keycloak for its import.

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

A disposable local Kubernetes fixture used CNPG operator 1.29.1, the same
Bitnami PostgreSQL 17.4 source version, Keycloak 26.8.1 and a CNPG 17.11
target. A synthetic Keycloak realm/user was created and signed in; the source
Keycloak stopped before declarative import. All 101 public tables and the
checked user, realm and persisted-session counts matched. The database owner,
`en_US.UTF-8` collation/ctype, `pgaudit` and application password were
preserved. The old refresh token and a new login worked after switching the
fixture. The test passed again with DEV-equivalent 500m/384Mi database
limits. This is synthetic local evidence, not acceptance of the real DEV
database, its custom provider, or a production migration. The DEV controller
validated the newly sealed copy of the existing application credential
without printing or exporting its plaintext.

An isolated, non-host-networked DEV pod started the native LiveKit
`1.13.11` image with a synthetic key, TURN secret and webhook URL, using the
same relevant RTC, TURN, metrics and service-link settings as the chart.
The room, participant and process-start gauges required by the host activity
collector were present. The first disposable fixture omitted
`enableServiceLinks: false` and failed because Kubernetes injected
`LIVEKIT_PORT`; the corrected fixture matched the actual chart and passed.
This proves startup/configuration and those metrics only, not signaling,
TURN or user media on either origin.

Full exact-candidate CI, a GitOps rollout and authenticated multi-student
classroom/media acceptance on DEV are still pending. The platform's previous
local tests and preliminary security findings are recorded in its
`docs/security/2026-11-03-stack-upgrade-local.md`.
