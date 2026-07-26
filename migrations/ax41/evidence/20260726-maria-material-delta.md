# Maria material delta from retired VDSina — 2026-07-26

This record contains no credentials, material bodies or personal identifiers.

## Scope and safety

- Source: retired VDSina application data plane at `89.124.113.223`.
- Target: AX41 production guest `playsay-prod`.
- PostgreSQL Liquibase histories matched before the transfer.
- The owner UUID was preserved; the test material `hello` was excluded.
- No lesson, assignment, submission, collaboration, annotation, template or
  derived YouTube cache rows were imported.
- A full production application PostgreSQL dump was encrypted off-host before
  the first write. Its PostgreSQL 17 catalog and RSA/AES decrypt path passed.
- The selected migration rows, production baseline, object manifest and
  verification result are stored in a separate encrypted off-host bundle.

## Applied delta

- 15 new materials inserted.
- 3 existing materials refreshed from the stable source snapshot.
- 59 new material asset rows and MinIO objects inserted.
- 13 new HTML-game enrichment rows inserted.
- Objects were copied through authenticated S3 operations, never from the MinIO
  PVC. Every destination object was read back and matched by SHA-256.
- Total copied object bytes: `10,385,717`.
- Object manifest digest:
  `2d3beb727fefcd4fdb863e4dbfa8e117d1b2009b48fc269ca878e168b77f12ef`.

## Verification

- Source remained stable before and after the transaction.
- Source and production database signature:
  `37/110/24/dbc080ff5662ea22775b8d9929436499`.
- Production contains 37 Maria-owned non-test materials, 110 related assets and
  24 related enrichments; owner/material/asset/enrichment orphan checks are zero.
- All 59 copied objects passed a second production-only checksum read.
- Production k3s readiness passed, no failed or pending pods were present, and
  all 15 ArgoCD applications were `Synced/Healthy`.
- `online.honey.school`, `online.honeyschool.ru` and `key.honeyschool.ru`
  returned HTTP 200; API readiness returned 200 and anonymous `/api/me`
  returned the expected 401.

Owner-operated acceptance remains: sign in as Maria and visually open one
updated image material, one new HTML game and one video-based material before
deleting the old VPS.
