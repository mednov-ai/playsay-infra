# Shared HTML-game library — DEV delivery, 2026-10-16

Owner authorized «мерджи в develop проследи за развертыванием»: both develop integrations and DEV only. Production promotion and production migration are not included. Original dirty checkouts are retained; delivery uses isolated clean clones.

**DEV delivery outcome:** both develop integrations and native DEV functional acceptance are complete: cutoff275 mapped / 255 active games / 241 verified material references; primary14/14 and RF19/19; final normal snapshot queue zero. Production promotion/backfill and OpenSpec archive remain pending. **Incident:** agent diagnostics caused two earlier DEV collaboration process exits and eleven in-memory pending payloads were not recovered; see the incident section below.

## Integration and migration

- Feature sources: platform `7cd6afa2`, infra `45783f4`; integrated through platform PR61 and infra PR34, preserving newer scheduling/auth/Keycloak and desired state.
- Platform PR62–69 correct CI routing/drain, classroom layout, native build gates, legacy JPEG metadata, preview Escape, iframe focus and immediate learner reconnect.
- Infra PR35–44 scope DEV upload edges, pause admission/writers, run inventory/apply, bound Job memory and restore admission/writers after reconciliation.
- Upload envelopes are 21 MiB for the exact HTML-game routes; application file limit is 20 MiB. AX41 and RF DEV changes use scoped existing Ansible plays, nginx validation and backup recovery. Production virtual hosts are retained.
- Liquibase schema converged via the native API migration Job. Migration writes use only the guarded immutable application Job; no manual SQL migration, source edits or object deletions.
- Inventory A: 275 READY / zero blocked. First apply retains partial transactions and failed on valid JPEGs with generic metadata and inherited JVM OOM137; it is not reported successful.
- Forward fix recognizes only JPEG/PNG signatures for generic legacy covers, preserves exact bytes and rejects unknown MIME. The Job has bounded `-Xms128m -Xmx384m`, bounded metadata/direct/code caches and a 1 GiB cgroup.
- Inventory B completes 16:32:53 UTC. Apply B `dev-cutover-1016-b` completes 16:37:30 UTC: **275 mapped, zero candidates, 241 verified references, zero unresolved/blocked**. Every source, independent HTML, cover and effective material reference is verified.
- 275 aliases / mapped checkpoints resolve to **255 ACTIVE games**, including twenty verified copies merged with originals. Originals, aliases, schema and checkpoints remain retained.
- Migration disabled, normal lesson admission restored and game writers enabled through separate GitOps merges after reconciliation. Historical expired lessons are unchanged.

## Protected recovery evidence

Before successful resume, two drain snapshots (16:30:32/16:32:50 UTC) confirm zero open lesson access windows, processing, collaboration activity and LiveKit participants. Host free space is 22,419,398,656 bytes; private migration storage is 10 GiB.

DB backup `/var/backups/playsay/shared-html-games-20261016T162909Z`: actual isolated PostgreSQL restore verifies 275 legacy assets. Dump SHA256 `b0e65c8227fe6acf9912f0a9e84650b1d80060eaad03e0190dd3db0c479edc58`.

Objects `/var/backups/playsay/game-library-objects-20261016T162909Z`: 1,502 objects / 668,021,781 bytes, restored into an isolated temporary bucket and downloaded with every hash matched. Manifest SHA256 `ee0d2ec944edc35275bd90f72796683f9f66d9e0e17017eb7eec3796bd6d4fe2`. Backups remain protected on DEV.

## Acceptance boundaries

Native API210 and vocabulary75 fresh full JVM gates pass with exact valid Kotlin accepted-risk records and zero blocking findings; no expired exception is renewed. Native frontend full audit and actual static nginx runtime inventory are retained independently under the owner's outside-server-runtime policy; findings remain unresolved findings.

Both DEV origins already pass actual exact-20-MiB upload, idempotent retry with the same game/revision and 20-MiB-plus-one rejection with application 413. API/edge revisions are unchanged by frontend recovery fixes. These authenticated browser/API checks preserve TLS verification and clean only their own fixtures.

Local regression: 943 frontend tests, lint/build and eight Chromium/WebKit desktop/mobile light/dark cases. Candidate static assets with real DEV services pass 15 checks including early-action reload recovery and subsequent synchronized action; these are preparatory evidence, separate from final published-source acceptance.

Protected task reports: `/Users/evgeniymednov/Documents/Projects/Play&Say/local-results/shared-html-game-library-20261016`. Application evidence and exact source mapping are in platform `docs/testing/evidence/2026-10-16-shared-html-game-library-develop.md` and `docs/implementation/html-game-library-source-map.md`.


## DEV diagnostic incident — 18:23 UTC

After RF19 acceptance, final metrics exposed 11 retained unsaved snapshots, with zero live windows/connections/rooms/participants. Generic queue handling retained the exact retired-game HTTP403 response indefinitely; platform PR70 adds narrowly scoped retirement invalidation and 86 passing collaboration tests.

An agent Inspector diagnostic then caused two collaboration59 process exits through unsupported Runtime.evaluate dynamic import (`ERR_VM_DYNAMIC_IMPORT_CALLBACK_MISSING`), last exit1 18:23:28 UTC. Eleven pending in-memory payloads were not recovered or individually attributed. This is an agent error, **not a lossless drain or an authorized restart to clear retained state**. The user was informed. Durable DB/object data was not edited; cutoff MAPPED275 / ACTIVE255 remain, with zero active launches and zero retained game documents. Debug port is closed. Protected previous logs: `/var/tmp/playsay-shared-games-inspector-incident-previous.log`; local incident evidence: `snapshot-diagnostic-incident.json`.

CI publication was held and the collaboration module temporarily disabled during investigation, then re-enabled after two current zero queue/runtime/window snapshots. These post-incident snapshots do not recover or certify the earlier lost payloads. Production was not touched. Post-correction native acceptance and queue checks follow below.


## Retirement correction publication

Native collaboration60 uses platform `cd7930ce217d5625447a8f55066091fbf4b9cc24`; infra `56963d9` publishes digest `sha256:eb1f2cb8a8c95b39a97bac8b606df9421250cd774a0706b8ef3ef05b227d2750`. Exact pod imageID/readiness and Argo Synced/Healthy are independently verified. The new pod starts with zero restarts; this does not erase the two earlier agent-caused collaboration59 exits documented above. No active teaching/test activity occurred before this rollout, and current pre-rollout queue was zero.

Fresh native full npm audit for collaboration60 reports zero findings, including development dependencies. Lock SHA256 `a6f732a5ef8867f666c2af85315aff7f07a4b4ddce7d9dbd7fdf34d6d287955d`; retained raw wrapper SHA256 `cde86008d2153b127915ddb8c11f4ea18871526bb6d2651c2d35bdeae8790950` (`native-collab60-audit.json`). Previously published web401 and API210 images remain unchanged. Final post-correction browser/queue acceptance follows below.

Post-correction primary-origin native acceptance passes all 14 scenarios with no candidate asset routing; supported cleanup archives own games/materials and removes own lessons. At 18:34:17 UTC, active windows/processing/connections/rooms/media participants and **snapshot queue are all zero** after those real stop/relaunch/reload operations. This is normal post-correction queue acceptance, distinct from the earlier incident reset. The result is retained as `native-school-retirement-final-results.json`; extended RF acceptance follows.


## Final DEV acceptance

Post-correction native acceptance uses published web401 / collaboration60 with real DEV Keycloak/API/collaboration/media and no candidate asset routing: **primary14/14; RF19/19**, including five additional start/action/stop cycles. Both origins verify shared teacher access, learner catalog denial, migrated search/content, UI upload, preview Escape, new/existing material reuse, canonical upload retry, no-material lesson, minimize/state, learner reload with continued synchronization, explicit stop/fresh state, attached-material preservation and mobile learner actions. Separate loaded-card layout checks render 24 cards on desktop/mobile at each origin with no horizontal overflow; representative desktop/mobile screenshots were inspected. Both origin upload-boundary tests pass exact20MiB, idempotent same game/revision retry and 20MiB+1 application413 on unchanged API210/edges.

All own browser game/material/lesson cleanup sets are empty; games/materials are archived using supported retention semantics, lessons removed, teacher assignment/profile settings reset. Both four-account batches are removed from Keycloak with absence verified; local task credentials are deleted. Original checkout status lists exactly match the initial lists (platform152 changes / infra33), preserving unrelated work.

After real post-correction stop/relaunch/reload operations, primary snapshot queue is zero at 18:34:17 UTC. Two final post-RF snapshots also show zero live lesson windows, processing, collaboration connections/rooms/queue and media participants/rooms. Migration remains disabled; writers=true / maintenance=false. Exact imageIDs, observed generations, ready counts and affected Argo Synced/Healthy are independently verified. Native dispatcher268 / collaboration60 and prior dispatcher267 / web401 are SUCCESS. New collaboration60 remains at zero restarts; the earlier two collaboration59 diagnostic exits and eleven unrecovered pending payloads remain an explicit incident, not erased by this acceptance.

Protected final reports: `native-school-retirement-final-results.json`, `native-rf-retirement-final-results.json`, `dev-post-retirement-final-1.log`, `dev-post-retirement-final-2.log`, `dev-accepted-runtime.json`, `native-ci-retirement-final.jsonl`. Media is synthetic: these checks do not establish physical speaker/camera or human validation of every historical game's mechanics. The earlier one-off RF loading timeout is retained; it does not recur in unchanged-source repeats or post-correction repeated-launch acceptance.

| Service | Build | Published source | Immutable image |
| --- | --- | --- | --- |
| api-gateway | 210 | `bf6736ec79873cb39e40aa64af80f614d2cce054` | `ghcr.io/mednov-ai/playsay-api-gateway@sha256:4527635c11e34b3f78bb43ec5285088cf93f48b9c125c4722f8d7d6a7932a489` |
| web-app | 401 | `977a504e6c886cee4891ce5661cea4f5798b8ae6` | `ghcr.io/mednov-ai/playsay-web-app@sha256:05c3b6c584b38eaf04a35f5360b7b2029b3473385e865814f68c3bf3d7b0bccf` |
| collaboration-service | 60 | `cd7930ce217d5625447a8f55066091fbf4b9cc24` | `ghcr.io/mednov-ai/playsay-collaboration-service@sha256:eb1f2cb8a8c95b39a97bac8b606df9421250cd774a0706b8ef3ef05b227d2750` |
| vocabulary-service | 75 | `de3060983fa0d7d3f79d915b079f6cb6936f39fd` | `ghcr.io/mednov-ai/playsay-vocabulary-service@sha256:f76128c5cf0a63b8635a7bebb08df6ae16cc3d1e598fc1c0f7edd492e71dc4fd` |
| keyboard-app | 110 | `de3060983fa0d7d3f79d915b079f6cb6936f39fd` | `ghcr.io/mednov-ai/playsay-keyboard-app@sha256:96c7ec18a88e89a3a52933fb09dd853cc14ed1d45124af98877ed155f2ee98d5` |
