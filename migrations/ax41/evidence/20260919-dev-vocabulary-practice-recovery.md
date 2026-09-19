# DEV vocabulary practice recovery — 2026-09-19

Owner authorized implementation, develop integration, DEV GitOps delivery and browser acceptance with DEV accounts. No production operation or promotion was performed.

## Source and delivery

Platform changes were built from develop using normal dispatcher jobs. Source ancestry and final immutable image identities are recorded below after the final rollout. Infrastructure commit `004bbdf` changes only the DEV vocabulary memory limit from 512 MiB to 768 MiB, retaining a 256 MiB heap and 384 MiB request. It followed observed OOMKilled/137 and a simultaneous key-set 502 at 00:44:14 UTC; no memory leak attribution is claimed. Helm lint passed.

Dependency security for vocabulary build 66 archived 19 artifacts. Backend gate evaluated at 01:24:08 UTC and build-logic at 01:20:49 UTC: `passed-with-accepted-risks`, policy SHA256 `05a67abe7f8dbe24fc2a47985919fe8333b7209aba4a9590e3fa65368cf95a96`. The existing exact Kotlin CVE-2026-53914 exception expires 2026-10-08; no exception was extended or broadened. Raw reports remain in Jenkins. No dependencies or schemas changed.

## Initial acceptance boundaries

Authenticated external Playwright used the DEV teacher and two DEV students. Real acceptance passed dictionary mutations/search/undo; self and homework exercise feedback including the last answer; lost final HTTP response followed by explicit retry; all four frozen homework publication policies; Key three modes with custom settings, fresh authentication, typing, callback replay and return; live API controls/private progress/continuation deduplication; and media candidate approval, regeneration retaining approved delivery, owner authorization and cross-owner denial. Four locales were checked at 1440 and 390 pixels after actual profile updates, then restored.

Local injected failures cover media provider/storage. Group partial-save passed through the real UI with one real insert, one injected 503 and retry of only the failed owner. They are not claimed as real provider outages. Initial acceptance found teacher RETURN blocked on a product decision: the assignment is returned but its immutable completed session cannot be reworked. Teacher ACCEPT after a settled completion callback passed. Mastery remains IN_PROGRESS at its true 33.33% despite 100% diagnostic accuracy, as required by its distinct policy.

Detailed application evidence: `playsay-platform/docs/testing/evidence/2026-09-19-vocabulary-practice-recovery.md`. The initial acceptance was incomplete; the final approved follow-up below closes both remaining flows.

## Initial verified runtime identities

At the final source rollout, all 13 DEV product deployments were ready. Web, vocabulary and Key ArgoCD applications were Synced/Healthy; their pods had zero restarts. Jenkins dispatcher 213, web 338 and vocabulary 66 succeeded; Key frontend 99 had already succeeded.

| Component | Source commit | Immutable digest |
| --- | --- | --- |
| web-app / web-dev-338 | `dba43986b100080bafe536ce0c4c36d89ee0e001` | `sha256:ac89823995dd80db7de344031c6a32e992705da18ead669ec7a4964b22e1e0fd` |
| vocabulary-service / vocabulary-dev-66 | `36d95e9d94e603b0ae184ec3ed81e4a13d8eefc8` | `sha256:0a7ed3f9bf59964ad0b0064655aff48f515675b15fe80d185b0a2df440a664dd` |
| keyboard-app / key-frontend-dev-99 | `a93c03a9cd6d4a5c016f8d69be0e178d8a8e1684` | `sha256:219f7d051bb81b5b651de25398949abb9a75e0b1c5206d4efa5c77fe12ed4110` |

Infra image commits: `7045605` (vocabulary 65), `c9bbea1` (web 335), `27f8c1a` (Key 99), `e18f351` (vocabulary 66), `f048ae1` (web 336), `0489904` (web 338). Backend composer/adaptive-policy/delivery-policies/key-ngrams/generated-media flags were true. Web 338 console confirmed all corresponding VITE flags plus practice/homework/live/key and personal-practice-v2 true, with the DEV Key origin.

Post-rollout list/preview agreement passed for all seven sources on the same six owned entries, including paused pinned-word exclusion. Actual Key n-gram callback and replay left the entire SPELLING state unchanged. Mobile keyboard search/clear/refocus and no horizontal overflow passed on web 336.

Final deployed web 338 passed the three-browser live scenario, including no-material discovery, hint revision synchronization, independent learner progress, pause/resume draft preservation and recoverable command failures. A bounded transport interruption followed by a new WebSocket restored the subscription without losing the draft. A separate mastery assignment completed at actual 66.67% against its frozen 20% target. Dispatcher 212/web 337 were intentionally stopped before publication when the hint-ordering defect was found; dispatcher 213/web 338 contain the fix and succeeded.

Initial acceptance also found used-recipe deletion failing: DELETE returns 500 because `fk_vocabulary_plan_recipe` preserves historical plan references (confirmed at 02:11:01 UTC). The subsequent owner decision selected archival. No direct database mutation was attempted.

Cleanup archived 12 task-owned words, cancelled 10 recorded unfinished practices and deleted 5 created lessons. Eight assignment/audit histories and one referenced recipe remain. A subsequent authenticated audit found no task-owned active words or unfinished recorded self/live sessions. Existing learner data was preserved.

## Final approved follow-up delivery and acceptance

Owner selected mistakes-only rework with whole-frozen-set fallback and recipe archival. Platform source `012d131923282a8bff847f4b193effa967327905` is in develop. Dispatcher 215 and API 189, vocabulary 67, web 339 and Key 100 all succeeded. Vocabulary migration Job `playsay-migrate-vocabulary-service-67-012d1319` completed at 06:29:57 UTC through Jenkins. API and vocabulary security gates were passed-with-accepted-risks under the unchanged policy above; API retained 30 artifacts, vocabulary 19. No dependency exception was broadened.

| Component | Final immutable digest |
| --- | --- |
| api-gateway / api-dev-189 | `sha256:af6001f6d7e5b41675eac81f12a1f83654b998e463664376a1f99d48b412774c` |
| vocabulary-service / vocabulary-dev-67 | `sha256:91c844800c1a9ad5d6056ae9c8aca164e3429091b6f0e775604f7f01a9424c36` |
| web-app / web-dev-339 | `sha256:c470b802b13538c2ab5d794f90915bc4ff911e2ae6b43758d1f20580167b28ac` |
| keyboard-app / key-frontend-dev-100 | `sha256:62bc45f0f5a0ef81a53c92935a4346bad3554f46daa4c74a46f8f49894471c11` |

Image-pointer commits `5189052`, `9e3c08c`, `4729ad5`, `45d50e1` are in infra develop. All four applications were Synced/Healthy with zero pod restarts; all 13 DEV deployments were ready. Runtime vocabulary feature flags were enabled and runtime Liquibase disabled.

Authenticated browser acceptance passed teacher RETURN, two students completing rework and teacher ACCEPT. The student with one mistake received one task; the all-correct student received the entire five-task frozen set. Repeated RETURN reused the child, peer progress and old history stayed unchanged, and foreign child-session access was denied. Desktop/mobile screenshots were inspected. Used-recipe DELETE and repeats returned 204, foreign deletion 404, the recipe disappeared from the loaded selector, and prior history counters stayed unchanged. Late old-session callbacks are covered by gateway integration tests.

Final cleanup: 16 task-owned words archived, 12 unfinished self/live practices cancelled, 4 recipes archived, 5 lessons deleted. Nine assignment/audit histories remain because no public deletion endpoint exists. No recipe remains blocked by the old FK deletion failure. All 31 OpenSpec tasks are complete; no production operation or OpenSpec archive was performed. Migration/rollback restrictions are documented in the runbook.
