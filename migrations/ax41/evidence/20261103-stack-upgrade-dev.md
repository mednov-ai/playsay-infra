# DEV stack-upgrade preparation — 2026-11-03

Status: prepared, **not yet delivered**. Platform hotfix source at this
checkpoint is `ca1e6d401048a42f7a21f3557d2388ba0f89f2bb`; rerun candidate
gates if its head moves. The production rollout is outside this DEV step.

The proposed PostgreSQL and LiveKit images are now **security-blocked** by
fresh container findings; see the retained [raw reports and runtime
evidence](security/20261103-stack-upgrade/README.md). DEV lesson admission
was restored through infra PR #62, and the gateway is Synced/Healthy with the
maintenance flag off. No database, Keycloak or LiveKit upgrade was deployed.

The current platform candidate is `ce42081191dd6efbe5070f4143b92932063dfd0a`.
Non-deploy Jenkins web build 417, keyboard build 114, game-adapter build 45
and collaboration build 63 passed their test/build stages for its previous
commit `e830a539a33e9b787232ff1ad8e79e8b0c127b1a`. The current commit changes
only the classroom smoke script, which passed its focused DEV baseline run
and CI target-routing tests locally. Those Jenkins image publication,
environment update and rollout stages were not executed. The earlier
application/security commit was
`1434bc7fc81f0427d9bb0f94d1f463f2c291864f`: Keycloak build 27 passed
provider tests and its security gate, and full JVM security build 13 passed
with scoped accepted risks and 49 archived artifacts. Backend and build-logic
each reported zero blocking findings for that earlier commit. Subsequent
commits change four runtime Dockerfiles, the classroom smoke script, a
configuration comment and local security evidence; backend, scanner scripts
and JVM Jenkinsfiles are unchanged.
Fresh exact-candidate full gates and scans of the CI-built images remain
required before delivery. DEV delivery and acceptance of the upgraded
candidate remain pending.

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

## Existing DEV baseline classroom, 2026-11-03

The currently deployed, **not upgraded**, direct DEV environment was exercised
with one demo teacher and two demo students in independent Chromium profiles.
Synthetic camera and microphone produced increasing inbound and outbound RTP
for all three participants; both students saw a synthetic teacher screen
share. Shared-presence cursors, student annotation synchronization after
scroll/resize, collaborative exercise answers, student reconnect and
restoration of media/annotations/answers, and student submission passed.
The task-owned lesson was deleted, its material archived, and the three
task-created sessions logged out. A separate API check confirmed fixture
cleanup. Physical devices and the upgraded candidate were not validated by
this run.

A separate two-person test used the DEV RF origin and DEV-only relay, after
fresh zero-activity observations in DEV and production and a healthy, idle RF
TURN snapshot. Actual synthetic audio/video RTP increased in both directions;
both browser connections selected the DEV regional TURN, the student saw the
screen share, shared exercises synchronized, and rejoining restored RF media
and shared work. The task-owned lesson was deleted, material archived, and
both sessions logged out; a separate API check confirmed cleanup. During the
test the shared edge had 1,347 MiB available memory, 25.6% sampled CPU and
upper-bound aggregate RX/TX rates of 1.98/6.35 Mbps; nginx and both TURN
services were active. This short synthetic-media developer-network check does
not validate a physical device, real RF last mile or the new candidate.

Earlier attempts first timed out because the test recorder acted before the
microphone was ready and because the teacher task returned to its hidden view
after participant selection settled. The harness was corrected. A later
focused run saw a text-annotation compact-width assertion return 72 px
instead of the expected greater-than-72 value immediately after typing. The
core run explicitly skipped that assertion. A separate three-participant run
waited for the scheduled size calculation and passed the compact text,
mind-map and teacher/student anchored-scroll checks. Its lesson was deleted,
material archived and sessions logged out. The corrected checked-in smoke
script subsequently passed the focused three-participant DEV baseline run;
its task-owned lesson and archived material were independently verified.
Repeat the multi-student acceptance against the exact candidate after an
authorized, security-cleared DEV delivery.
