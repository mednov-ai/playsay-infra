# AX41 prod seed and honey.school edge evidence — 2026-07-20

This evidence is maintained with the matching `release/1.001.00` and
`codex/migrate-ax41-dev-prod` infrastructure revisions.

Verified infrastructure state:

- the independent prod k3s cluster runs healthy manual-sync Argo CD applications for CloudNativePG, `app-postgres`, Keycloak and MinIO;
- prod runtime secrets were generated independently in the prod cluster; external OpenAI/email/payment credentials are intentionally absent until separate prod credentials are supplied;
- the encrypted off-Git immutable-ID allowlist contains exactly Maria plus her six reviewed students, 22 material IDs, 51 asset/object keys and 11 enrichment IDs, with the single `hello` material rejected;
- offline Keycloak export was filtered before import, dev SMTP/client secrets and old/local redirect URLs were removed, and prod contains exactly seven human users plus two expected confidential-client service accounts;
- prod PostgreSQL contains 7 `app_user`, 22 `lesson_material`, 51 `material_asset`, 11 `material_html_game_enrichment`, zero `hello` materials and zero copied lesson/chat/submission history; schema/changelog data and 24 system email templates were recreated separately;
- exactly 51 allowlisted MinIO objects were streamed from dev to prod through authenticated S3 operations without storing plaintext object files on the workstation;
- the source MinIO credential had accidental trailing newlines; both dev consumers were updated to the normalized credential and MinIO, API Gateway and Media Service rolled out successfully before the selective object copy;
- nginx edge configuration is managed by Ansible and proxies only the four exact requested hostnames to the two VM NodePorts;
- a single Let's Encrypt certificate covers `online.honey.school`, `key.honey.school`, `dev.online.honey.school` and `dev.key.honey.school`, expires `2026-10-18` and has automatic renewal configured;
- `dev.online.honey.school` and both dev/prod Keycloak discovery endpoints return HTTP 200 with valid TLS; prod discovery advertises issuer `https://key.honey.school/keycloak/realms/playsay`;
- `online.honey.school` intentionally returns 502 until the release web/API workloads are promoted; it must not be accepted as cut over before T5/T9 pass.
- Helm application charts support an optional OCI digest and prod values pin every completed `release/1.001.00` candidate by digest; mutable tags are retained only as human-readable build evidence.
- prod LiveKit values use independent keys, the AX41 public address and the prod API webhook; the reviewed firewall change adds only the prod TURN/TCP/UDP DNAT ranges and remains subject to an external forced-relay smoke gate.

Remaining gates are completion of the API, collaboration, email and keyboard
frontend release jobs, immutable prod runtime rollout, login/material/object
checksum smoke, WebSocket/LiveKit verification and final traffic acceptance.
