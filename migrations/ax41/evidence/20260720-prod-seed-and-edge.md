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
- byte-for-byte SHA-256 verification passed for all 51 selected objects; MinIO ETags changed during the authenticated copy and are therefore not used as the content-integrity proof;
- the source MinIO credential had accidental trailing newlines; both dev consumers were updated to the normalized credential and MinIO, API Gateway and Media Service rolled out successfully before the selective object copy;
- nginx edge configuration is managed by Ansible and proxies only the four exact requested hostnames to the two VM NodePorts;
- a single Let's Encrypt certificate covers `online.honey.school`, `key.honey.school`, `dev.online.honey.school` and `dev.key.honey.school`, expires `2026-10-18` and has automatic renewal configured;
- `dev.online.honey.school` and both dev/prod Keycloak discovery endpoints return HTTP 200 with valid TLS; prod discovery advertises issuer `https://key.honey.school/keycloak/realms/playsay`;
- `online.honey.school` intentionally returns 502 until the release web/API workloads are promoted; it must not be accepted as cut over before T5/T9 pass.
- Helm application charts support an optional OCI digest and prod values pin every completed `release/1.001.00` candidate by digest; mutable tags are retained only as human-readable build evidence.
- prod LiveKit values use independent keys, the AX41 public address and the prod API webhook; prod coturn has an independent shared secret and the AX41 firewall/libvirt hook forwards only TURN `3478`, TURN relay UDP `49160-49200`, LiveKit TCP `7881` and direct UDP `50000-50020` to `10.60.0.20`;
- external TCP checks pass for `3478` and `7881`; an authenticated forced UDP relay from the retiring VPS passed 6/6 packets with zero loss, about 26 ms average RTT and sub-millisecond jitter;
- repeated prod SQL verification reports `7/22/51/11`, `hello=0`, zero lesson/chat history and zero orphaned material-owner, asset-material or enrichment-material references.

Remaining gates are completion of the API, collaboration, email and keyboard
frontend release jobs, immutable prod runtime rollout, login/material/object
checksum smoke, WebSocket/LiveKit verification and final traffic acceptance.
