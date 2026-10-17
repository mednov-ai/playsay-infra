# Lesson whiteboard DEV integration evidence

## Native develop completion — 2026-10-17

Platform PR [#72](https://github.com/mednov-ai/playsay-platform/pull/72) merged as `54866462e4051272c56315092b9a1b98ada9d561`; infra PR [#46](https://github.com/mednov-ai/playsay-infra/pull/46) merged as `f32a545d7137684c03b041fee1a742e7195e817b`.

[Dispatcher #269](https://jenkins.honey.school/job/playsay-platform-dispatch-develop/269/) and all five exact-source jobs succeeded: API 211, vocabulary 76, web 402, collaboration 61 and keyboard frontend 111. Native API tests and Liquibase stages completed successfully; Jenkins exposes no aggregate testReport endpoint for these jobs, so no aggregate test count is inferred. Web native UI smoke passed. All four JVM dependency gates have zero blocking findings and retain the exact existing Kotlin acceptance through 2026-11-14: `passed-with-accepted-risks`, not remediation. Counts of accepted records are API backend/build-logic 89/24 and vocabulary 39/24.

At 17:53 UTC, all 21 DEV Argo applications were Synced/Healthy. All five updated workloads were ready with zero pod restarts and these immutable digests:

| Module | SHA-256 |
| --- | --- |
| API | `63b7d1a10177f522182afddd97f28cf80d9188c1382114ffa9f3b0aa9c9caa77` |
| Web | `2f17a7cbf736cd3de0c4d3633545ae93c682a45925c545ea4e76a68413482beb` |
| Collaboration | `b82df214715bca23ecc63a62bd303ad9e26ee3c9dc0f3e1352ac2ff0df39cb81` |
| Vocabulary | `c03ff09b771216194b2774b0ed21ace9a845f8a5268514cb3b4116e1827b4fb1` |
| Keyboard | `5daf84ae70479ddc52c110c7e116c5783a06cd5bdd0fc7121a045f2ecdf8a97e` |

The source is `54866462e405` for every image (vocabulary provenance uses GitOps build metadata plus CI/image identity because its legacy Deployment has no source annotation). CI applied all three whiteboard changesets; `lesson_whiteboard` exists. The actual web container has no Node executable or build dependencies. `PLAYSAY_WHITEBOARD_ENABLED=false`; no production publication or real board/media/RF acceptance is claimed.

DEV backup `/var/backups/playsay/lesson-whiteboard-20261017T165832Z/app.dump`, SHA-256 `8d5faab53c590beb7d1a6a3f2b81498fc37fadcac4a46af827cd6a7637f6b122`, passed isolated PostgreSQL 17 restore (1416 materials, 114 collaboration documents, 288 games, 71 changelog records). The temporary restore DB was dropped. Pre-publication consecutive activity snapshots were zero; post-publication snapshots are retained in the evidence directory.

GitHub-to-Argo notifications returned HTTP 502. API rollout recovered through the runbook's Application hard-refresh annotation, without editing workloads or applying manifests. All jobs subsequently succeeded; the underlying callback failure is not claimed fixed.

During investigation the agent accidentally exposed a Jenkins trigger secret embedded in an old GitHub delivery message. It was revoked/replaced consistently in Jenkins, the persistent credential Secret and GitHub. Old token recognition is HTTP 404, new is HTTP 200; GitHub JSON/TLS/push settings and ping were verified. Only sanitized verification booleans/status codes are retained. No secret values belong in this report.
