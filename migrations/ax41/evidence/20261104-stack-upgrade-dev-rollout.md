# DEV stack upgrade rollout — 2026-11-04

## Scope and security

The owner authorized DEV deployment and accepted only PostgreSQL and Keycloak findings also present in the corresponding previous DEV images. This DEV exception is not production authorization. Exact comparisons, candidate image findings and retained scans are in [security evidence](security/20261103-stack-upgrade/README.md). The LiveKit HTTP/2 dependency was addressed in the separately built and scanned server image.

The thirteen application images were built from platform `b5d4da6d86f49a3fed18279f43dd7d4fbdca1d6f`; their exact published digests and full scan reports are retained in the security evidence directory. The Keycloak image is `sha256:f79ab63440522b836f91ecf9ce420709a442d298246c4a5502666753fd9292cf` and LiveKit is `sha256:5bd1c9b8248dd70583d63fa1462104efd41f5d077d9cc7f16135cbb83932e6fe`. The tested PostgreSQL image is `sha256:03a1c6a62b27e8ad31cae5c085131b5ac706b09403d6fcb6c58d16c8daa257cd`.

## Protected data and deployment

Lesson admission was closed through infra PR #67. From 07:54:19 to 08:55:34 UTC, 222 samples observed zero DEV activity, with a maximum 18-second gap; the observation covered the 3,600-second issued-token lifetime and an additional margin. Fresh two-sided DEV/PROD lesson observations admitted the stateful steps.

Four-database backups taken at `/var/backups/playsay/stack-upgrade-dev-20261104T085409Z` and, after Keycloak stopped, `/var/backups/playsay/stack-upgrade-dev-20261104T085810Z` passed SHA256, archive-catalog and isolated PostgreSQL 17.11 restores. After Keycloak cutover, `/var/backups/playsay/stack-upgrade-dev-20261104T090512Z` backed up the new active identity database and the application databases and also passed the isolated restore. Each restore contained 93, 11, 5 and 101 public tables respectively for playsay, keyboard, worksheet import and Keycloak.

Infra PRs #61, #68 and #63 stopped Keycloak, imported its source PostgreSQL 17.4 into a separate 17.11 CNPG cluster, and switched the reviewed Keycloak image and JDBC host. Before the switch there were no other source clients. The two databases matched across 101 table row digests, schema, index and constraint counts, locale, owner, audit configuration and application password. Three pre-existing DEV demo sessions refreshed and profiles loaded after the switch; new logins also passed. The old source PVC, workload and secret remain; since the new target received writes, the old source is stale and is not a lossless rollback.

Infra PR #64 updated the application CNPG instance to PostgreSQL 17.11. The primary reported the exact candidate digest, version 17.11, healthy state and non-recovery status. PR #66 deployed the scanned LiveKit image. An initial `ImagePullBackOff` exposed a missing registry credential in the `livekit` namespace; PR #71 added a DEV-scoped SealedSecret using the existing DEV registry credential. Its decrypted value matched the existing DEV credential without being printed, and LiveKit became healthy on the expected digest.

PRs #72, #73, #74 and #70 rolled out application images in bounded groups. All thirteen deployed workloads were observed ready on their exact candidate image references; 22 Argo applications were Synced/Healthy. PR #69 restored DEV lesson admission, and authenticated checks on both DEV origins confirmed the maintenance guard no longer blocked entry. A before/after snapshot in the application, database, Keycloak and operator namespaces showed no unplanned increases in restart counts or restarted new pods; the new LiveKit container reported zero restarts.

## Lesson acceptance

On the direct DEV origin, independent browser sessions for a teacher and two students passed 19 checks: access and profiles, group classroom entry, real WebRTC transport with synthetic camera/microphone, screen sharing to both students, shared material and annotations, live exercise answers, student reconnect and submission. The task-owned lesson was deleted and the material archived.

On the DEV RF origin, a separate teacher/student scenario passed nine checks including forced DEV TURN relay for both peers, two-way synthetic audio/video RTP, screen share, collaboration, reconnect and cleanup. Before the RF test, both environments had zero observed lesson activity, DEV/PROD TURN counts were zero, and two subsequent RF CPU samples were below 20%; an earlier sample had briefly reached 93.5%. These are automated browser tests using synthetic media; physical cameras, microphones, devices and a genuine RF last-mile were not tested. A second group run captured desktop and 390-by-844 mobile viewport layouts; it passed its focused checks and cleaned up. This is viewport emulation, not a physical mobile-device acceptance.

The activity panel displayed the untranslated key `vocabulary.practice.reason.DUE` in the desktop and mobile captures. The relevant composer and English resources are unchanged from the platform commit recorded for the previous DEV web image (`e37bb8aa3107c71dd31edfaea8c3735b2025532d`); its previous deployed UI was not retested. This visible defect was not changed as part of the dependency hotfix.

The CloudNativePG operator remains at 1.29.1; its 1.30.1 candidate requires separate isolated upgrade/recovery tests and pull credentials before activation. Production was not deployed and requires a separate owner command and its own release, security, backup, schema and lesson-safe gates. Platform `develop` integration remains to be completed without allowing automatic builds to interrupt lessons.
