# honey.school production cutover and final VPS backup — 2026-07-21

This record contains no credentials or personal identifiers.

## Release and production promotion

- Platform release branch: `release/1.001.01` at `942a02086098c8ccf0839f1dfe2818d5bdc869d8`.
- Infrastructure release branch: `release/1.001.01` at `984b285`.
- Jenkins web build `playsay-web-app-develop/2` completed `SUCCESS` in about 299 seconds and published digest `sha256:98570f29db6b0aa91f97da95e2d944a3c901a680ecae07deb2e86a4458a612ca`.
- Jenkins keyboard build `playsay-keyboard-app-develop/3` completed `SUCCESS` in about 208 seconds and published digest `sha256:fee1c6757b51f1d250e4c09d02491b0f35c3916632c185e29f6a4a2b85d79433`.
- The matching infra release branch pins those two digests. Production was manually promoted by changing the root ArgoCD application to `release/1.001.01` and explicitly syncing the five changed child applications; Jenkins never received production credentials or performed the promotion.
- All 15 production ArgoCD applications reached `Synced/Healthy`. No pod was unready and the production guest had about 31 GiB memory available with no swap use after rollout.

## Domains, TLS and authentication

- All eight names resolve to `65.109.55.110`: `online`, `dev.online`, `key`, `dev.key`, `ops`, `dev.ops`, `jenkins` and `hooks` under `honey.school`.
- The Let's Encrypt certificate contains all eight SANs and expires on 2026-10-19.
- `online.honey.school`, `key.honey.school`, `dev.online.honey.school` and `dev.key.honey.school` return HTTP 200.
- Production and dev discovery return issuer `https://ops.honey.school/keycloak/realms/playsay` and `https://dev.ops.honey.school/keycloak/realms/playsay` respectively.
- Headless browser checks from both production frontends reached the production Keycloak authorization endpoint on `ops.honey.school`; callbacks were `online.honey.school/auth/callback` and `key.honey.school/auth/callback`.
- Production readiness returned 200 and anonymous `/api/me` returned the expected 401.
- Public Jenkins access is denied with 403. Management UI routes remain WireGuard-only. The transitional `key.*/keycloak/` compatibility proxy remains until owner-operated authenticated acceptance is complete.

## GitHub webhook cutover

- `mednov-ai/playsay-platform` hook `632315512` now targets only `https://hooks.honey.school/generic-webhook-trigger/invoke` with its invocation token kept out of evidence and Git.
- `mednov-ai/playsay-infra` hook `636710711` now targets only `https://hooks.honey.school/argocd/api/webhook` and uses the dev ArgoCD HMAC secret stored in `argocd/argocd-secret`.
- GitHub ping deliveries returned HTTP 200 for both hooks. The prior `ops.play-and-say.ru:18443` payload URLs are no longer configured in GitHub.

## Production data integrity

- Post-rollout SQL verification returned exactly `7/22/51/11` for users/materials/assets/enrichments and `hello=0`.
- Earlier selective-seed evidence verifies all 51 copied MinIO objects byte-for-byte and confirms no copied lesson/chat/submission history or orphaned references.
- Maria and reviewed-student password login plus rendered-material acceptance remain owner-operated gates; credentials were preserved and never printed or reset.

## Final source-VPS safety bundle

- Bundle ID: `playsay-final-vps-v2-20260721T083819Z`.
- Source revisions recorded in the manifest: platform `942a02086098c8ccf0839f1dfe2818d5bdc869d8`, infra `ed9fe74e2900113f2fa4762568f57b30896a8a47`.
- Encrypted bundle SHA-256: `f63e1ee460635e1207395ead44e61109011c0f9c3a4ad884094308dd1a308faa`.
- Encrypted data-key SHA-256: `6d95a699c6a3e681ceb331d18ed0e68e77d199435eee5d1b1023a06ef27b816a`.
- Backup public-key SHA-256: `d0f3fee5ad8382ae2882d03dc0dea709147cae95e8449ab55faca602df3f5162`.
- The four bundle files are copied off the VPS under the operator's protected backup directory, outside Git; the RSA private key is stored separately and never reached the VPS.
- Transport checksums, RSA/AES decryption, all internal payload checksums, PostgreSQL 17 source catalogs, gzip/tar structure and the MinIO archive passed verification. Plaintext verification data was removed automatically.
- The exporter now validates dumps through short-lived writable-volume files inside the database pods because repeated `kubectl exec -i` validation of the keyboard dump could hang. Validation files are unlinked on success and by the exit trap.

## Remaining gates

- Owner-operated Maria login, one reviewed-student login and visual rendering of the transferred materials.
- Move database migrations into scoped Jobs inside dev and remove the temporary no-op capacity compatibility stages.
- Prove real MacBook and phone WireGuard handshakes before closing public SSH.
- Stop the old Jenkins only after a stabilization window. Delete the old VPS only after explicit owner approval; Amnezia is intentionally not migrated.
- Configure permanent off-host backups and migrate local OpenTofu states to a versioned and locked remote backend.
