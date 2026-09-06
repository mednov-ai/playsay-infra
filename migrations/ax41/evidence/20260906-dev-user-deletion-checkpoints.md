# Dev administrative deletion checkpoints — 2026-09-06

## Scope and authorization

The owner explicitly approved scoped commit/push, AX41 dev delivery and an end-to-end check using a newly created disposable account. Production promotion and deletion of existing real accounts are not authorized by this acceptance. No legacy host is involved.

## Source isolation

- Standalone product change: platform `codex/hotfix-user-deletion-checkpoints`, `751b8b7b` (initial change `1b712d39`).
- Dev delivery candidate: platform `codex/hotfix-user-deletion-dev`, `afde004240394d54432a1cb47cf49b640c81fe0b` (initial candidate `68d77853f98f9f624e0874239e226896d641334e`).
- Dev candidate preserves the already deployed RF routing/login baseline `00e53fe7e7beec3f68ace18d6852c8731a0cc9e7`; delivering directly from develop would remove those changes. Gateway and registration trees at that baseline match their deployed `4be2794e` / `5e097560` module trees.
- Main dirty workspaces and unrelated unpushed CI/classroom/infra work were not committed or deployed. Root `spec.md` and `sign-in.md` remain synchronized locally in the parent repository, which has no configured remote.

## Preflight and local checks

- AX41 dev ArgoCD applications were Synced/Healthy; all four affected Deployments were ready.
- Jenkins was not quieting down; queue and running-job list were empty before dispatch.
- Read-only PostgreSQL preflight found zero deletion operations, hence no old PENDING/RUNNING worker to drain. The separate aggregate lesson query found 63 IN_PROGRESS rows; this was not treated as a production zero-active-lesson gate or authority to end lessons.
- Current-dev candidate: gateway 420 tests (1 skipped), registration 53, vocabulary 85, zero failures/errors. Frontend lint, full test suite and production-mode build passed. Internal registration OpenAPI validate/generate passed.
- Synthetic browser regression passed ru/en/de/fr at 1440×900 and 390×844: navigation, long list, explicit confirmation, cancel/Escape/focus, unavailable native confirm, injected 409 and visible toast. This is not backend/IdP acceptance.
- Jenkins vocabulary #51 failed before tests/image delivery on Detekt LongParameterList. The fix split shared-vocabulary cleanup and gateway teacher/student cleanup into focused services, retained JPA checkpoint persistence and did not disable rules or add suppressions. All three modules' detektMain checks and the affected full gateway/vocabulary tests passed locally afterward.

## Delivery and acceptance

- Registration #65: SUCCESS, including image publication, GitOps update and rollout; source `68d77853`.
- Vocabulary #52: SUCCESS, including tests, normal DB migration, image/GitOps update and rollout; source `62ebc410`. Before gateway dispatch both dependency Deployments were ready with these source/build identities, and the old PENDING/RUNNING deletion count was still zero.
- Gateway #160: SUCCESS (tests/package, OpenAPI contract, normal DB migration, image publication, GitOps and rollout). Dev Deployment is ready at `62ebc410`; all four affected ArgoCD apps were Synced/Healthy before web dispatch.
- Web #311: build, tests, publication and rollout passed at `62ebc410`; the overall job was deliberately stopped (ABORTED) during UI smoke after gateway connection-pool exhaustion. It is not a successful acceptance run.
- The first real authenticated disposable-account attempt timed out during creation, before any DELETE. Read-only reconciliation found zero matching new platform users and zero recent disposable Keycloak identities; no test account was created.
- Gateway diagnostics showed all eight pool connections active with queued waiters and no PostgreSQL blocked sessions. Code inspection found an added repository read before a REQUIRES_NEW identity upsert, allowing the outer transaction to retain a connection while waiting for another. Candidate `afde0042` removes only that redundant read; the atomic upsert and JWT filter retain deletion-intent protection. Its regression test failed before the fix and passed afterward; full gateway tests and detektMain passed locally. This remains a code-supported diagnosis until live acceptance passes.
- Gateway #161: SUCCESS, source `afde004240394d54432a1cb47cf49b640c81fe0b`, digest `sha256:59fecdc1e39644057c97d26c767aa42c6cb3fba32c2fa52863b306f6252b8140`. Tests/package, OpenAPI, image publication, source tag, GitOps and rollout passed; migration was correctly skipped for this schema-unchanged commit.
- Real deletion acceptance PASSED on `https://dev.online.honey.school` in Chromium: a fresh disposable STUDENT was created, its Keycloak identity existence confirmed, the application dialog opened/cancelled with zero DELETEs, then explicitly confirmed. Exactly one DELETE returned 202; read-only polling reached COMPLETED, the UI card disappeared, the active API list excluded the target, and Keycloak returned 404. Native window.confirm was disabled by the test. The disposable account was permanently removed by the requested workflow; no existing user was deleted.
- Post-rollout ArgoCD: all four affected applications Synced/Healthy. A five-minute gateway log check during real deletion and smoke startup found zero connection-acquisition timeout markers. This is bounded acceptance evidence, not a capacity guarantee.
- Homework smoke: PASS, all 16 checks including mobile private-image access, permission isolation, draft autosave, teacher progress, resubmission and cleanup.
- Classroom smoke with the extra `PLAY_SAY_SMOKE_FAKE_MEDIA=true` option failed waiting for `.playsay-prejoin-audio-confirm button`, after successful login, profile reads, temporary material/lesson creation and collaboration setup.
- Standard CI-mode classroom smoke (without that extra option) passed eight checks, including opening the classroom for a teacher and two students, then failed the text-annotation content-sized-bounds assertion (transparent background, measured 72×56). The hotfix has no diff from its preserved dev baseline in this smoke script, classroom UI directory or classroom stylesheet. This is not a passed classroom gate; its precise cause remains uninvestigated and outside the deletion fix. These runs do not change the ABORTED result of web #311.
- Read-only reconciliation confirmed both failed classroom attempts' temporary lessons absent and materials ARCHIVED. The deletion table contained exactly one operation, COMPLETED/COMPLETED, and no unfinished operation. A subsequent ten-minute gateway log check found zero connection-acquisition timeout markers.

## Safety and remaining acceptance

The rollout order is registration plus safe vocabulary purge, then gateway migration/application, then web. Migration uses the normal Jenkins in-dev Liquibase Job, never manual SQL. Reading an operation never retries deletion. A new confirmed DELETE may resume FAILED while retaining suspension and checkpoint.

Rollback to a checkpoint-unaware gateway is prohibited while any non-LEGACY operation is not COMPLETED, including FAILED. Keep the additive stage column. Rollback cannot restore deleted accounts or personal data.

Maria's original browser/origin/runtime, target role discrepancy and production incident acceptance remain unverified. Successful dev delivery does not close that incident or authorize a production rollout.

The dev candidate includes previously deployed topic-branch RF work to avoid rolling it back. Do not promote that combined branch blindly: a future numeric release must reconcile the runbook's exact dev-accepted ancestry gate with its separately reviewed production scope. The standalone hotfix branch is retained for source review, not represented as independently deployed dev ancestry.
