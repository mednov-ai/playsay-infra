# Honey School Dev Runbook

## Sprint 0 Status

Sprint 0 is complete. This runbook now describes the working dev baseline for Sprint 2.

## Active AX41 Dev/Prod Topology

The active topology uses a third `playsay-ci` VM and restores the original domain ownership: `key.honey.school`/`dev.key.honey.school` serve the keyboard trainer, while Keycloak is published at `ops.honey.school/keycloak` and `dev.ops.honey.school/keycloak`. The shared Jenkins controller is rebuilt from Git in `playsay-ci`, is VPN-only at `jenkins.honey.school`, and receives public GitHub events only through restricted routes on `hooks.honey.school`. Jenkins may deploy dev through scoped remote RBAC and must not receive prod kubeconfig. The current status and remaining tasks are in [`../../specs/ax41-ci-migration.md`](../../specs/ax41-ci-migration.md); this supersedes the older instruction to install Jenkins inside `playsay-dev`.

AX41 at `65.109.55.110` serves `honey.school` production from `release/01.005.02`: the Ubuntu 24.04 physical host, healthy mdadm RAID1/ext4, KVM/QEMU/libvirt, OpenTofu, firewall, WireGuard and VPN-only Cockpit baseline are active. The NAT-backed `playsay-prod` (`10.60.0.20`, 8 vCPU/38 GiB), `playsay-dev` (`10.60.0.30`, 2 vCPU/10 GiB) and `playsay-ci` (`10.60.0.40`, 4 vCPU/8 GiB) guests are active and protected by separate OpenTofu states. The 14 declared guest vCPUs moderately overcommit the host's 12 logical CPUs, while fixed guest memory remains 56 GiB and leaves about 6 GiB for the host. Prod/dev run independent k3s, ArgoCD and Sealed Secrets controllers. CI runs only k3s, Sealed Secrets and the Git/JCasC-defined Jenkins controller; it has no product workloads, ArgoCD, Keycloak or MinIO. Production has 19 ArgoCD applications; all are `Synced/Healthy` at the accepted numeric branch. Web, keyboard, API, worksheet import, collaboration signaling, LiveKit signaling, forced TURN, transactional Mailjet email and production monitoring reach AX41. Canonical Keycloak is `ops.*/keycloak`; the explicit `key.*/keycloak` compatibility path remains only until owner-operated login/material acceptance. Both GitHub webhooks use `hooks.honey.school`. Payment remains disabled until independent production credentials are supplied. Release evidence: `migrations/ax41/evidence/20260830-release-01.005.02-reconciliation.md`; prior capacity evidence remains `migrations/ax41/evidence/20260727-release-1.001.08-capacity.md`.

The full architecture, historical decisions and rollback contract are defined in [hetzner-ax41-dev-prod-plan.md](hetzner-ax41-dev-prod-plan.md), while the current executable checklist is [`../../specs/ax41-ci-migration.md`](../../specs/ax41-ci-migration.md). Mark a task complete only after recording its exact Git revision and non-secret evidence location.

The old VPS has only the short paid overlap remaining. Final source bundle `playsay-final-vps-v2-20260721T083819Z` has been copied off the VPS and fully decrypt/checksum/archive verified. Keep the VPS and old Jenkins available only as rollback through owner acceptance; delete neither without explicit owner approval. The old hosts `146.103.126.15` and `89.124.113.223` are never a current dev target: agents must not connect to, diagnose, restart, build on or deploy to them unless the owner explicitly requests a named legacy rollback action in the current chat. Amnezia is not migrated and ends with the VPS. AX41 administration uses its independent WireGuard management VPN.

The old VPS and AX41 are independent authentication and deployment contours. AX41 dev uses only `dev.*.honey.school` with issuer `https://dev.ops.honey.school/keycloak/realms/playsay`; production uses direct `*.honey.school` origins plus the Russian `online.honeyschool.ru` and `key.honeyschool.ru` proxy aliases, all with the single issuer `https://ops.honey.school/keycloak/realms/playsay`. The two `.ru` aliases belong to the same production `playsay-web` client and are present in its redirect URIs, web origins and post-logout redirects. The old hosts `online.play-and-say.ru` and `key.play-and-say.ru` remain exclusively in the protected `legacy/play-and-say-vps` branches and use `https://ops.play-and-say.ru:18443/keycloak/realms/playsay`. Never add cross-contour redirect URIs, web origins, logout redirects, issuers, JWKS, or ArgoCD target revisions. Legacy Jenkins is manual-only and can build only the legacy branch. The root `play-and-say.ru` site is outside both application-auth changes.

As a temporary migration handoff applied on 2026-08-18, both HTTP and HTTPS requests for `online.play-and-say.ru` return `302` to `https://online.honeyschool.ru$request_uri`; the HTTP ACME challenge path remains local so the legacy certificate can renew. The VDSina nginx source is `/etc/nginx/conf.d/playsay-k8s-dev.conf`, and the pre-change rollback copy is `/etc/nginx/conf.d/playsay-k8s-dev.conf.before-online-redirect-20260817T211632Z`. To roll back, restore that exact file, run `nginx -t`, and reload nginx. Remove the bridge instead of making it permanent after the owner accepts the domain transition and authorizes retirement of the legacy VDSina edge. Do not add the old origin to current Keycloak, CORS or WebSocket allowlists.

Legacy Jenkins was reconciled on 2026-08-05 after an agent followed stale local guidance and manually retried current `develop` on the old controller. Erroneous `playsay-api-gateway-develop` build `#87` was aborted; protected infra branch `legacy/play-and-say-vps` at `33d7e9a3a6533be1431a3ba624b10e1d8b3af04` was reapplied with `scripts/configure-jenkins-jobs.sh`. The only enabled jobs are the 13 `playsay-legacy-vps-*` jobs, each hard-pinned to `*/legacy/play-and-say-vps` with an empty trigger set. Every job without that prefix, including `playsay-game-adapter-service-develop`, must remain disabled. Modern retries and Jenkins configuration belong only to the AX41 `playsay-ci` guest; never pass `develop`, feature or release parameters to VDSina Jenkins.

Current API lesson/chat WebSockets are fail-closed through `PLAYSAY_WEBSOCKET_ALLOWED_ORIGIN_PATTERNS`. The api-gateway Helm values must render exactly `https://dev.online.honey.school` for dev and `https://online.honey.school,https://online.honeyschool.ru,https://honeyschool.ru` for production; local chart defaults contain only localhost/127.0.0.1 wildcard ports. Do not add `www.honeyschool.ru`, wildcard domains or `online.play-and-say.ru` to the current chart. This policy change belongs only to AX41/Selectel Honey School contours and must not trigger an old-VPS apply, legacy Jenkins build or legacy branch edit.

Lesson participant links use two fail-closed api-gateway origins: `PLAYSAY_PUBLIC_APP_URL` is `https://online.honey.school` in production, while `PLAYSAY_PUBLIC_APP_RF_URL` is `https://online.honeyschool.ru`; both values are `https://dev.online.honey.school` in dev. Authorized link reads return one 96-bit compact alias and server-built `/l#<alias>` URLs, with `.ru` as the production copy default and `.school` as the explicit alternative. Compact and legacy start validate the exact request origin before capability lookup, persist it on the bounded browser attempt, and reuse it for the Keycloak callback and continuation. Do not replace either setting with a client-supplied URL or add a legacy application origin.

The compact-link rollout adds nullable `lesson_access_link.alias_hash` and `lesson_entry_attempt.request_origin` columns before the new gateway image. This keeps the previous revision able to write during rollout. The new application fills alias hashes for new links and lazily for an existing active link on the next authorized get/rotate; it never stores the raw alias or requires a blanket link rotation. Run the normal state-based Liquibase convergence/backup/apply gate before syncing the gateway, then verify the Keycloak theme and both callbacks before enabling teacher issuance. Rollback disables issuance and restores the previous browser/application images through GitOps; the additive columns remain.

The replacement Jenkins controller is active on dedicated guest `playsay-ci`; it was rebuilt from Git/JCasC without the old controller PVC. Affected-target collaboration delivery and release web/keyboard builds reached GHCR, Git and dev ArgoCD successfully. Its scoped kubeconfig can read rollout state and refresh named dev ArgoCD applications but cannot read dev secrets or access prod. GitHub no longer points at the old controller. Never expose the replacement UI publicly; use the management VPN at `jenkins.honey.school`. Only the exact generic-trigger and dev-ArgoCD webhook endpoints on `hooks.honey.school` are public. Database migrations still require redesign as in-dev Jobs before the temporary no-op capacity compatibility paths are removed.

Authoritative restore capture `playsay-safety-v3-20260720T220404Z` was used to rebuild dev and is documented in `migrations/ax41/evidence/20260720-safety-v3.md`. The newer final source cutoff is `playsay-final-vps-v2-20260721T083819Z`: its encrypted files are outside Git under `/Users/evgeniymednov/Backups/PlayAndSay/ax41-final-vps-20260721`, while the RSA private key is stored separately under `/Users/evgeniymednov/Backups/PlayAndSay/keys`. Transport/payload checksums, local RSA/AES decryption, PostgreSQL 17 source catalogs and both archives passed. Never commit or colocate the private key with an off-host copy of the bundle. Evidence: `migrations/ax41/evidence/20260721-honey-cutover-and-final-backup.md`.

### Worksheet import enablement

`worksheet-import-service` is internal and ClusterIP-only. The chart defaults and a newly provisioned environment remain disabled-safe, but production `release/01.005.00` has both service and gateway flags enabled with `analysis.provider=stub`. Production owns a separate `worksheet_import_app` login and retained `worksheet_import` database, environment-local runtime/migration and service-token secrets, and the private `playsay-worksheet-staging` bucket with a restricted identity and no anonymous policy. Before enabling another environment, provision those resources and run the service Liquibase migration through the approved bounded migration Job. Never reuse gateway database credentials or MinIO root credentials.

For dev, provision without printing secret values:

```bash
./scripts/sync-worksheet-import-db-secret.sh
./scripts/provision-worksheet-import-secrets.sh
```

The database helper keeps the CloudNativePG password source in `playsay-data/playsay-postgres-worksheet-import` and produces the runtime/migration shape as `playsay-worksheet-import-db` in `playsay-dev` and `jenkins`. The staging helper uses the existing MinIO root Secret only inside a short-lived provisioning pod, creates a dedicated restricted user and bucket policy, and copies only `playsay-worksheet-import-storage` into the application namespace. Inspect Secret metadata and bucket policy, never their values, before enabling the chart.

Enable and verify in this order: database/role and bucket policy, worksheet service migration, worksheet service flag/rollout, internal health and authorized preview checks, then the gateway flag. Production was enabled only after synthetic JPEG/PDF review and idempotent materialization passed in dev and again inside production. Roll back by disabling the gateway first and then the service; do not delete staging objects, the database, or material source attachments during rollback. TTL cleanup must continue until abandoned sessions expire. Restore a logical backup only after a separately approved incompatible-schema or data-recovery decision.

Safe diagnostics are session status counts, page/source counts, job lease age, raster/analysis durations, retry/failure class, blocker counts and cleanup age. Do not print or query source bytes, OCR text, prompts, answers, correct options, flashcard backs, object keys, access credentials or learner responses. A growing oldest-lease age indicates a stuck worker; a growing oldest-staging age indicates cleanup failure. Provider failure is not an availability incident while manual continuation succeeds.

The accepted dev real-provider profile uses `gpt-5.6-sol`, reasoning effort `low`, and a bounded `PT120S` timeout per page or packet request. This leaves headroom for structured vision output while remaining below the five-minute worker lease; keep production on the disabled stub baseline until its own reviewed enablement.

## Production 100-Lesson Capacity Profile

The committed desired state supports a capacity gate for 100 simultaneous individual lessons (200 bidirectional 720p/30fps participants, 30% TURN), but it is not certified until the maintenance-window test in `docs/capacity-100-lessons.md` passes. Single-node prod has no HA; LiveKit/coturn rollout disconnects active media.

The production source-of-truth ranges are LiveKit UDP `50000:50511`, coturn relay UDP `49152:49999`, TURN `3478` TCP/UDP and LiveKit fallback `7881` TCP. Dev has a disjoint contour on the same public AX41 address: LiveKit UDP `51000:51049`, coturn relay UDP `50600:50999`, TURN `3479` TCP/UDP and LiveKit fallback `7882` TCP. They must match `ansible/group_vars/ax41_hosts.yaml`, `ansible/group_vars/ax41_guests.yaml`, the dev overrides in the ignored inventory copied from `hosts.yaml.example`, AX41 UFW/DNAT/libvirt hook and the corresponding LiveKit values file. The host reserves `3478-3479,7881-7882,49152-51049`; each guest reserves only its own contour. Both realtime guests apply 16 MiB UDP buffer maxima and backlog `10000`; the host applies conntrack `524288`. Prod/dev/CI libvirt CPU shares are `2048/512/512`. AX41 DNAT is reconciled by `playsay-livekit-nat.service`, not appended by UFW: the oneshot removes historical/current duplicates before installing exactly one rule per required port. After every firewall apply, verify `iptables-save -t nat` contains one copy of every prod and dev DNAT rule and none of the former `49160:49200` or `50000:50020` ranges.

`playsay-livekit-nat.service` is coupled to `libvirtd.service` and must reconcile both DNAT and `LIBVIRT_FWI` after every libvirt restart. The reconciler waits until the required rules pass two consecutive checks above the blanket `virbr60` reject boundary. Diagnose a lesson stuck at `Connecting`/`Disconnected` with `sudo /usr/local/sbin/playsay-validate-livekit-firewall`, `sudo systemctl status playsay-livekit-nat.service` and an external TCP probe of `65.109.55.110:3478` and `:7881`; pod/HTTP health alone does not validate ICE. The supported recovery is `sudo systemctl restart playsay-livekit-nat.service`, followed by the validator and external probes. Do not restart k3s, LiveKit or coturn for this firewall-ordering symptom. On 2026-08-24 this procedure recovered production after the 2026-08-20 unattended libvirt package restart had rebuilt `LIBVIRT_FWI` with the custom realtime rules below its reject rule.

Before rollout:

```bash
cd /Users/evgeniymednov/Documents/Projects/Play\&Say/playsay-infra
scripts/validate-100-lesson-capacity.sh
cd ansible
ansible-playbook --syntax-check playbooks/ax41-host.yaml
ansible-playbook --syntax-check playbooks/ax41-guests.yaml
```

Apply in this order during a window with zero active lessons:

1. Run AX41 host Ansible in check mode, review widened firewall/DNAT, sysctl and CPU-share changes, then apply.
2. Run AX41 guests Ansible in check mode, then apply only after confirming coturn restart is acceptable.
3. Promote/sync the release containing LiveKit, collaboration, JVM resource and prod monitoring changes.
4. Verify LiveKit config/ranges, pod requests/limits, coturn listeners, sysctl values, monitoring targets and alerts.
5. Execute and archive the capacity gate. Do not label the target supported merely because manifests render.

Do not narrow UDP ranges while ICE/TURN allocations exist. If sustained LiveKit CPU or NIC exceeds the acceptance limit, stop the gate and plan a dedicated 10 Gbit/s media node rather than raising AX41 limits.

AX41 host automation is run from the `playsay-infra/ansible` directory so its configured role path is applied:

```bash
ansible-playbook \
  -i inventories/hetzner-ax41/hosts.yaml \
  playbooks/ax41-host.yaml
```

On 2026-07-20 Ubuntu was updated to kernel `6.8.0-136-generic`; the corrected reboot gate restored RAID, SSH, libvirt, WireGuard, UFW and VPN-only Cockpit automatically. Cockpit uses the `playsay-cockpit-vpn.service` late starter so its address-bound socket starts only after `wg0`; do not directly add an `After=wg-quick@wg0` dependency to `cockpit.socket`, because socket units are ordered before `sockets.target` and that creates a boot ordering cycle. The final complete Ansible run reported `changed=0`. RAID/SMART, firewall, reboot and VPN evidence is recorded at `migrations/ax41/evidence/20260720-ax41-host-vpn.md`.

The MacBook and phone WireGuard profiles are stored outside Git at `/Users/evgeniymednov/Backups/PlayAndSay/wireguard/macbook.conf` and `phone.conf`. Import each profile into a WireGuard-compatible client and activate it; gray/private client IP addresses are expected because `PersistentKeepalive=25` lets both clients initiate the tunnel to public endpoint `65.109.55.110:51820`. After activation, open `https://10.250.0.1:9090`, sign in as `playsay`, and retrieve its generated password from the macOS Keychain item `PlayAndSay AX41 Cockpit`. The Cockpit certificate is initially self-signed. Confirm a server-side handshake for both peers before disabling public SSH. Do not publish port 9090 in DNS or the public firewall.

### WireGuard split DNS

AX41 runs the dedicated hardened `playsay-wireguard-dns.service` process from the existing `dnsmasq-base` package only on the management address `10.250.0.1:53`; it does not replace the host resolver or libvirt's per-network dnsmasq processes. UFW already trusts authenticated input on `wg0`, while no DNS socket is allowed on a public or wildcard address. The exact private records `ops.honey.school`, `dev.ops.honey.school` and `jenkins.honey.school` resolve to `10.250.0.1` so their normal HTTPS URLs traverse WireGuard. Public application names and `hooks.honey.school` are intentionally excluded. Every other query is forwarded to the declared public resolvers, so the VPN can be the client's only DNS server without changing public product resolution.

Validate and apply the server before changing any client profile:

```bash
./scripts/validate-wireguard-split-dns.sh
cd ansible
ansible-playbook \
  -i inventories/hetzner-ax41/hosts.yaml \
  playbooks/ax41-host.yaml \
  --check --diff --tags wireguard-dns
ansible-playbook \
  -i inventories/hetzner-ax41/hosts.yaml \
  playbooks/ax41-host.yaml \
  --tags wireguard-dns
dig +short @10.250.0.1 ops.honey.school A
dig +short @10.250.0.1 dev.ops.honey.school A
dig +short @10.250.0.1 jenkins.honey.school A
dig +short @10.250.0.1 honey.school A
```

The first three queries must return only `10.250.0.1`; the public query must return a different non-empty address. Verify `ss -lntup 'sport = :53'` on AX41 contains only `10.250.0.1:53` for DNS. Then, and only then, change `DNS = 1.1.1.1` to `DNS = 10.250.0.1` in each protected profile under `/Users/evgeniymednov/Backups/PlayAndSay/wireguard/` and replace the imported tunnel in the WireGuard client without printing or copying its private key.

On a split-tunnel Mac, WireGuard registers its DNS server as a supplemental all-domain resolver alongside the primary network resolver. That can race for names which also exist publicly. Keep the profile DNS entry for tunnel portability, and install the VPN-aware domain-specific macOS resolver while the tunnel is active:

```bash
./scripts/configure-macos-wireguard-split-dns.sh
```

The helper validates the server before invoking `sudo`, then installs the root-owned `school.honey.wireguard-split-dns` LaunchDaemon and its immutable helper under `/usr/local/libexec`. Every five seconds the daemon checks that `10.250.0.1` routes through the MacBook's `10.250.0.2` WireGuard interface. While active, it creates `/etc/resolver/honey.school` with `10.250.0.1` as its only nameserver, so public DNS cannot win a resolver race; dnsmasq answers the three private records and forwards public names. When the tunnel is inactive, it removes that resolver and flushes `mDNSResponder`, restoring the normal public resolver without a manual step. With the tunnel active, `scutil --dns` must show a `honey.school` resolver containing only `10.250.0.1`. Then open the normal URLs:

- `https://jenkins.honey.school/login`;
- `https://ops.honey.school/argocd/` and `https://dev.ops.honey.school/argocd/`;
- `https://ops.honey.school/victoria-metrics/vmui/` and `https://dev.ops.honey.school/victoria-metrics/vmui/`.

Verify fail-closed behavior from both paths: with WireGuard active, the private records must resolve to the management address and the ops pages must open; after turning the tunnel off, the daemon must remove `/etc/resolver/honey.school`, the public Keycloak discovery URL must still resolve and respond normally, and the VPN-only panels must not be reachable through the management address. For Mac rollback, run `./scripts/configure-macos-wireguard-split-dns.sh uninstall`; then restore the client profile DNS to `1.1.1.1`, replace the imported tunnel, and revert/apply the Ansible change.

Branch routing is strict. `playsay-platform-dispatch-webhook` is the only job that owns the Generic Webhook Trigger token; it validates each push payload and forwards it to exactly one internal dispatcher. `playsay-platform-dispatch-develop` accepts only `develop` and aborts its older dispatcher when a newer develop push arrives. `playsay-platform-dispatch-release` accepts only a protected fixed-width branch named `release/NN.NNN.NN`, for example `release/01.002.00`, and serializes release candidates independently of develop. Both internal dispatchers share the global four-agent CI cap. `codex/*`, `feature/*` and `hotfix/*` publish to dev only through direct manual starts of the required module jobs with explicit branch/commit parameters; they have no webhook dispatcher. Tag/delete events are ignored and free-form `release/*` names fail before routing.

Release numbering is product-oriented, not SemVer patch-oriented. `NN` is the major product generation and changes only for a comprehensive product/platform reset. `NNN` is the normal release counter; every ordinary release increments it and resets the fix counter, so the successor of historical `release/1.001.09` is `release/01.002.00`. The final `NN` is only for fixes within the same ordinary release: `release/01.002.00` becomes `release/01.002.01`. A major bump resets the other counters to `001.00`, for example `release/01.042.07` becomes `release/02.001.00`. Calculate the branch instead of editing digits manually:

```bash
cd ../playsay-platform
node scripts/ci/release-version.mjs release/1.001.09 release
node scripts/ci/release-version.mjs release/01.002.00 fix
node scripts/ci/release-version.mjs release/01.042.07 major
```

The commands return `release/01.002.00`, `release/01.002.01`, and `release/02.001.00` respectively. Newly created branches must use exactly two, three and two digits. Existing one-digit-major branches remain valid only as historical production baselines and rollback targets; do not rename or rebuild them.

Affected-target routing is fail-closed and does not use an automatic “build all” fallback. Internal module source and its module Jenkinsfile trigger only that module; OpenAPI contracts add their explicit frontend consumers; shared Kotlin/Gradle affects the eight Kotlin backends; shared frontend workspace files affect web and keyboard. Dispatcher/common CI files run `ci-contracts`, smoke files run `smoke-syntax`, and neither validation builds a product image. Docs run nothing. An unmapped path or invalid Git range stops before downstream jobs and must be fixed in the routing table or retried with an explicit `FORCE_TARGETS`.

For the first push of a numeric release, a zero GitHub `before` is replaced with the platform HEAD of the production branch named in infra `develop` at `argocd-apps/prod/current-release.txt`; the detector compares repository snapshots and does not require the release histories to be ancestors. Failure to resolve that baseline is fatal unless an operator supplies `FORCE_TARGETS`.

Before release module jobs, Jenkins prepares the matching `playsay-infra` release branch once. A new branch starts from current infra `develop`, overlays only the running production `image`/`build` metadata from `current-release.txt`, rewrites every prod ArgoCD `targetRevision`, and writes `argocd-apps/prod/release-candidate.yaml` with `status: building`. An existing incomplete candidate carries its affected targets into the retry. Module jobs then record only their Kaniko-produced immutable `sha256` digests in affected `values-prod.yaml`; immediately before each GitOps update they verify that their source SHA is still the branch HEAD.

Every numeric platform release must contain the exact dev-accepted platform commit. The dispatcher records it as `ACCEPTED_DEV_COMMIT` (defaulting to current `origin/develop`) and fails before any release build unless that full SHA is an ancestor of the release HEAD. The same SHA is persisted as `acceptedDevCommit` in the candidate manifest and rechecked by the finalizer. This prevents a release branch cut from an older production branch from silently omitting fixes already accepted on dev.

After every affected module succeeds, the release finalizer verifies the accepted dev ancestry, source HEAD, affected `build.commit` and digests, unchanged image/build metadata for unaffected charts, every prod `targetRevision`, and rendered `repository@sha256` references. A clean finalizer agent registers only the allowlisted dependency repositories declared by production charts (currently Bitnami for Keycloak) before `helm dependency build`; any unknown remote repository fails closed and must be reviewed before it is added. Only then does the finalizer change the manifest to `status: ready`; any failure leaves `building`. Jenkins has no production kubeconfig and cannot sync the prod cluster. An operator may promote only a reviewed numeric infra branch whose ready manifest still matches the platform branch HEAD, then performs the database migration approval, switches/syncs prod ArgoCD, runs production smoke, and only after success updates `argocd-apps/prod/current-release.txt` on `develop`. Never deploy prod directly from `main`, `develop`, a free-form release name or `hotfix/*`; publish a hotfix through a new numeric release branch.

`playsay-infra` is the desired-state source, not a requirement for one managed server to control another. AX41, its guests and the Selectel RF edge do not receive SSH authority over each other. The Selectel Ansible playbook is run agentlessly over SSH from a trusted control node; currently that node is the maintainer workstation with the ignored inventory/private-key path. Jenkins, `playsay-dev` and `playsay-prod` do not hold the Selectel private key. A future dedicated operations runner is allowed only as a separately approved control plane with equivalent release-branch and credential boundaries.

The approved initial prod seed is selective: Maria Mednova, the six students attached to her at cutoff, 22 Maria-owned materials excluding the test material `hello`, 51 referenced assets/MinIO objects and 11 HTML-game enrichments. Execute imports only from a reviewed protected manifest of immutable Keycloak subjects, application UUIDs, material UUIDs and object checksums; never select by names during the write step. Do not copy other dev users or dev lesson/assignment/submission/chat history. The source remains authoritative until the final cutoff and the detailed plan's count, login, referential-integrity and object-restore gates pass.

Migration is Git-first. Do not cold-copy k3s server state, Jenkins controller state or local-path PVC directories to the AX41. Recreate dev/prod application infrastructure and the separate CI/Jenkins guest from recorded Git commits, then restore only documented application state through the committed export/import scripts. Dev receives a full encrypted PostgreSQL/Keycloak/MinIO bundle; prod receives only the filtered seed above. Raw dumps, Keycloak exports, plaintext secrets, private keys, OpenTofu state and MinIO objects stay outside Git in the encrypted off-host repository. Git contains their manifest schema, expected non-personal counts, bundle checksum and verification code.

Object Storage is not a prerequisite for the accelerated first `honey.school` cutover. Until the S3 backend is provisioned, run OpenTofu only on AX41 as `playsay`, never from Jenkins or a second session, with separate `0700` local states in `/var/lib/playsay-opentofu-state/{platform,dev,prod,ci}`. Capture an encrypted off-host copy before and after every apply. Do not copy plaintext state to the workstation or Git. After the first production stabilization window, migrate each state with `tofu init -migrate-state`, verify remote versioning/locking, then remove local plaintext state only after a tested pull/restore.

The AX41 edge is generated by the `edge-proxy` Ansible role. It owns the eight exact application/ops hosts `online`, `key`, `dev.online`, `dev.key`, `ops`, `dev.ops`, `jenkins` and `hooks` below `honey.school`, plus the exact root `honey.school` static landing; it must not claim mail. The root landing lives at `/var/www/honey-school`, contains no external scripts/fonts, links only to the product SPA at `online.honey.school` and keyboard trainer at `key.honey.school`, and uses its own `/etc/letsencrypt/live/honey.school` certificate because three production application names terminate on the separate RF ingress. During Mailjet account activation only, the role also publishes the empty validation file `/var/www/honey-school/c13ef19e66138a6862298ea788218111.txt`; remove both its Ansible task and deployed file after Mailjet marks `honey.school` Active and support confirms activation. Never expand the shared eight-SAN certificate merely to add the root. `key.*` routes to keyboard NodePort `32087`; until frontend release images use the new issuer, only the explicit `/keycloak/` path remains as a temporary compatibility proxy and must be removed after acceptance. `ops.*/keycloak/` is the canonical public OIDC route, while ops UIs on those hosts and all of `jenkins.honey.school` are limited to the WireGuard subnet. `hooks.honey.school` allows only the exact Jenkins and dev-ArgoCD POST endpoints with request/rate limits. Prod routes `/collab/ws` directly to collaboration NodePort `32086` and strips `/livekit/` before proxying signaling to prod VM port `7880`; the generic online route continues to web NodePort `32083`. Keep explicit realtime/auth/webhook locations before generic locations. Certificates and the renewal deployment hook must cover every owned hostname.

The AX41 edge is TLS 1.2-only for the root landing and all eight managed application/ops `honey.school` hostnames. On 2026-07-21, `TLSv1.3` was found enabled in the generated nginx vhosts while the same Russian-network accessibility symptom previously seen on MTS, t2 and MGTS was reported again: Keycloak did not load without VPN. The Ansible source of truth now sets `edge_tls_protocols: TLSv1.2` and enforces it both in the nginx HTTP context and in every generated TLS vhost. The HTTP-context setting is required because TLS version negotiation happens before SNI selects a named vhost. Do not re-enable TLS 1.3 before a dedicated acceptance pass from those networks. Validate every public hostname after an edge apply: `openssl s_client -tls1_2` must negotiate TLS 1.2, while `openssl s_client -tls1_3` must fail with a protocol-version alert. This policy includes the canonical public OIDC routes at `ops.honey.school/keycloak` and `dev.ops.honey.school/keycloak`.

The same RF-access incident showed a fresh Chrome/incognito client receiving HTML but leaving the large application JS/CSS transfers pending over both HTTP/2 and HTTP/1.1. Live TCP state showed repeated full-size segment loss, a collapsed congestion window and 15–30 second retransmission backoff. AX41 TCP PLPMTUD (`net.ipv4.tcp_mtu_probing=2`, `net.ipv4.tcp_base_mss=1024`) did not resolve the user's external no-VPN test, so direct Hetzner ingress is not an accepted production browser/auth path for affected Russian consumer networks.

The accepted replacement for the temporary old-VPS workaround is a dedicated Selectel Russian ingress at `94.102.89.213`, managed by `ansible/playbooks/rf-edge.yaml`. It is an Ubuntu 24.04 VM with 1 vCPU, 2 GiB RAM and a 25 GiB system disk. Host nginx, Certbot and UFW are the only required edge services; the firewall permits only SSH and public HTTP/HTTPS. The nginx HTTP context and every generated TLS vhost remain TLS 1.2-only. Client traffic is proxied over certificate-verified TLS 1.2 to the AX41 address `65.109.55.110`.

The live stage activated on 2026-07-25 owns `honeyschool.ru`, `www.honeyschool.ru` and the public Keycloak ingress at `ops.honey.school`. The REG.RU A records for `honeyschool.ru` and `www` point to Selectel. The root now serves an independent Russian-only static landing from `/var/www/honeyschool.ru`, managed by the `rf-edge-proxy` role, with two actions for `online.honeyschool.ru` and `key.honeyschool.ru`; it no longer proxies the AX41 `honey.school` landing. Its independent Let's Encrypt certificate is stored at `/etc/letsencrypt/live/honeyschool.ru` and expires on 2026-10-23.

The Dynadot `ops.honey.school` record is an exact A record for `94.102.89.213`. Selectel exposes only the `playsay` realm and Keycloak theme resources: `/keycloak/realms/playsay`, `/keycloak/realms/playsay/` and `/keycloak/resources/`. The root, `/keycloak/admin/` and other realms, including `master`, return 404. The canonical issuer remains `https://ops.honey.school/keycloak/realms/playsay`; clients and tokens must not add or accept a second issuer. The independent certificate is stored at `/etc/letsencrypt/live/ops.honey.school`, expires on 2026-10-23 and renews through the shared HTTP ACME webroot. `certbot renew --dry-run` succeeds for both live certificates, and the deploy hook validates and reloads nginx after renewal.

The direct production origins `online.honey.school` and `key.honey.school` remain on AX41 and must not be changed when the Russian aliases are activated. On 2026-07-25 the exact REG.RU A records `online.honeyschool.ru -> 94.102.89.213` and `key.honeyschool.ru -> 94.102.89.213` became authoritative, and both Selectel proxy routes were activated over HTTPS. Each preserves the corresponding `.school` Host/SNI upstream, verifies AX41 TLS and rewrites absolute application/websocket URLs back to the `.ru` alias. Public full-transfer smoke returned the complete web JS (`1,157,070` bytes), web CSS (`226,388` bytes), keyboard JS (`356,669` bytes) and keyboard CSS (`64,663` bytes). HTTP redirects to HTTPS, TLS 1.2 succeeds and TLS 1.3 is rejected for both aliases.

The independent certificates are stored at `/etc/letsencrypt/live/online.honeyschool.ru` and `/etc/letsencrypt/live/key.honeyschool.ru`; both expire on 2026-10-23. Targeted renewal dry-runs succeed, the Certbot timer and nginx deployment hook are active, and a second Ansible apply returns `changed=0`. The frontends derive login and logout callbacks from `window.location.origin`, and `scripts/configure-keycloak-prod-rf-aliases.sh` idempotently adds both aliases to the existing production client without changing its issuer. PKCE authorization smoke for both `.ru` callbacks returns the Keycloak login page. `dev.*`, `jenkins.honey.school` and `hooks.honey.school` remain directly on AX41.

Final acceptance still requires complete login and application loading from a Russian Chrome/incognito connection without VPN. During initial DNS propagation, Dynadot anycast nodes intermittently alternated the previous `ops.honey.school -> honey.school` CNAME and the new exact A record `ops.honey.school -> 94.102.89.213`, even under the same SOA serial. Before declaring the RF login path accepted, repeat authoritative and public resolver queries until they consistently return the Selectel A record; do not introduce a second issuer as a workaround.

Reconcile only the Russian ingress role without touching Docker, k3s, Amnezia or the existing `play-and-say.ru` vhost. Run it from a clean worktree of the exact pushed numeric release branch. The wrapper rejects `develop`, topic branches, detached/unpushed revisions and production apply without an explicit matching approval variable:

```bash
cd /path/to/playsay-infra-release-worktree

PLAYSAY_RF_EDGE_INVENTORY=/absolute/path/to/ignored/rf-edge/hosts.yaml \
  scripts/apply-rf-edge-release.sh --check

PLAYSAY_RF_EDGE_APPROVED_RELEASE=release/1.001.05 \
PLAYSAY_RF_EDGE_INVENTORY=/absolute/path/to/ignored/rf-edge/hosts.yaml \
  scripts/apply-rf-edge-release.sh --apply
```

The default operation is not implicit: the operator must choose `--check` or `--apply`. Always review the complete check-mode diff first. The release branch must contain the Selectel role, landing and routes even though their execution happens from the control node; this keeps the live edge reproducible without creating an AX41-to-Selectel management dependency.

Do not copy the AX41 private certificate key to Selectel. `ops.honey.school` already uses its independent Selectel ACME certificate and unattended HTTP renewal. The Russian aliases use their own Selectel certificates and do not replace or join the AX41 `.school` certificate. Keep the canonical production issuer `https://ops.honey.school/keycloak/realms/playsay`; adding an application alias must not change the issuer string.

Production frontend release `release/1.001.04` permanently removes the render-blocking Google Fonts request: web bundles Manrope, while keyboard bundles Manrope and Roboto Flex. The promoted immutable digests are web `sha256:8a8eaf71c7fbca52553e39ce32572532213201b94fe6462afcf991af0ba9f71b` and keyboard `sha256:598b52ba9327142903dcfd44c49c801c2f076895f4d607805cc9c50f7d0734ca`. A cache-disabled Chrome reload observed only local `.woff2` resources over TLS 1.2 and no request to `fonts.googleapis.com` or `fonts.gstatic.com`; the temporary AX41 HTML substitutions were therefore removed. Keep the local-font test coverage and do not reintroduce render-blocking third-party font delivery.

Production release `release/1.001.06` promotes platform commit `991dae044e5354f4a08144c756353e1ae2ce79e2` after the complete 11-module Jenkins dispatcher succeeded and the RF issuer hotfix rebuilt only the two affected frontends. It contains the JPG annotation-scroll fix, live exercise-answer synchronization, the homework detail/opening fix and explicit canonical issuer selection for both `.school` and `.ru` browser origins. The main runtime digests are API `sha256:923b8b771173d9b2649017b74d402e8e7b52315cdc6b52254e751439dc653c5f`, web `sha256:a05f074164da9af083621cfdb6aa6092f6d86756bcade2ecd89e138096633380`, keyboard `sha256:0b388568bbd581b5f638ecf2927fdc8f0380886b11059b67f8e0b868d52bf0b6`, collaboration `sha256:0b7fa7d6a60f02eec3484aef7fc7c081b54e6233c33c4cc8744650787b9a53bc` and vocabulary `sha256:a0078708600da555dc52768ea8b896822c6861af46e72eb2f41db9ec09b70db1`; every promoted workload renders `repository@sha256`. A pre-release logical backup under `/var/backups/playsay/release-1.001.06-20260726T090005Z` passed archive-list and checksum validation. All 15 ArgoCD applications reached `Synced/Healthy`. Direct `online.honey.school` and the Selectel alias `online.honeyschool.ru` returned the identical complete JS bundle and API `UP`; browser smoke on `online` and `key` for both direct/RF domains observed only the canonical `https://ops.honey.school` authorization endpoint, no legacy issuer, no `redirect_uri` error and no page errors. The Selectel edge also rewrites the legacy issuer string as rollback protection for an older cached frontend without changing the canonical issuer. RF TLS 1.2 succeeds and TLS 1.3 is rejected with protocol-version alert. Roll back by returning the production root to `release/1.001.04`; do not rebuild images.

Production release `release/1.001.07` promotes platform branch HEAD `1c068b10c8c435a8ae20f9f9621d70a865f9cc9c`; its product images were built from the last behavior-changing commit `a171a7eda31f9faf8252cc5081a8435f3a12012e`, while the later commits only harden CI routing and release finalization. The original complete 11-module dispatcher succeeded and produced immutable production digests. Release dispatchers 3 and 4 subsequently lost their dynamic Kubernetes agents (`ClosedChannelException`/agent removal) before completing the candidate gate, so the operator ran the same committed `validate-ci-contracts.sh`, `prepare-release-candidate.sh` and `finalize-release-candidate.sh` scripts locally against the unchanged protected branch SHA; all 29 CI contract tests and all Helm render/digest invariants passed, and infra candidate `84ac3295ab47cec4f3aaf429bbd25e0c843caf18` reached `status: ready`. The promoted runtime digests are API `sha256:6feb06d55d3dca9b5324475c9eb0ad25a01c4c9a6767a3f7260d6821858af76e`, web `sha256:b5ed74c790d33bb501185275672e027667c3fde4a0eda89e90092c25c75f49f7`, keyboard frontend `sha256:7eedcb455b1fcbd5eafc0c19ada34141d7819dccb0eb5e939a4c840626fb5c18`, keyboard backend `sha256:251600a2e9b2607daf18385e8ede7f97b73ba89eca18e5252d587b8e8ff803b5`, collaboration `sha256:cb3848db09141107446eb563f1244f1e8c68d63046203526e25679d47389c2f0`, media `sha256:26bdc82b5bbc3a6813595938ad29e470a24098ce5325f854ba85d57e504147ec`, registration `sha256:b72b368101e2b5967dae8c656489e29082c1f579f3bf3c0688a34d63254f834a`, vocabulary `sha256:28eb75fca7630e653e8844b52cb700cc61d9305c833a8b5f74b03ea2c6b1fd6a` and AI tutor `sha256:0b0137ba630ca92789f036ee0b8631ac444e641ee8b53269885c7d5ce8226e6d`. There were no Liquibase or SQL changes. Pre-release logical backup `/var/backups/playsay/release-1.001.07-20260726T203004Z` passed archive-list and checksum validation. All 15 ArgoCD applications reached `Synced/Healthy` at the candidate revision, all running workload images exactly matched the candidate digests, and no pod remained unready. Direct and RF application/API endpoints returned HTTP 200 and API `UP`; the RF bundle differed from the direct bundle only by the approved legacy-issuer rewrite. Headless Chromium loaded `online` and `key` on both `.school` and `.ru` without page errors and every sign-in flow reached only `https://ops.honey.school/keycloak/realms/playsay` with the origin-specific callback. Roll back by returning the production root to `release/1.001.06`; do not rebuild images.

Production release `release/1.001.08` promotes platform commit `27776832d320eaf38546347ab913b90f1020935a` for the 100-lesson desired-state profile. Jenkins release dispatcher 5 successfully built web `sha256:b942772e6051753db7ba1a30bbcc5f96af2908b4dc4ffd3a8b1475f6cde884aa` and collaboration `sha256:be50ff7dd5927ae775a57f8d141ea758ecf10532279319dd806d29dc02d8282d`, then lost its finalizer agent; the committed 29-test CI contract and fail-closed finalizer were run locally and candidate `ecdec5cfa58d8740253fb2ae3cab8bcef57b3b00` reached `ready` after removing generated null metadata that had masked chart defaults. There were no Liquibase or SQL changes. Backup `/var/backups/playsay/release-1.001.08-20260727T144520Z` passed checksums and `pg_restore -l` for application, keyboard and Keycloak databases. AX41 and prod guest use the widened UDP/TURN ranges and sysctl profile; idempotent DNAT leaves exactly one rule per required port. All 16 ArgoCD applications, including new production monitoring, reached `Synced/Healthy`; no pod remained unready, runtime web/collaboration digests matched the candidate and every VictoriaMetrics application/LiveKit/node/cAdvisor/blackbox target reported `up=1`. Direct and Selectel RF web/API endpoints returned HTTP 200/`UP`; TLS 1.2 succeeded and TLS 1.3 was rejected on the RF alias. Headless Chromium loaded all four online/key direct/RF origins without page or request errors, and every sign-in flow reached the canonical `ops.honey.school` issuer with the correct origin-specific callback. This deployment does not certify 100 simultaneous lessons: the external two-generator browser capacity gate in `docs/capacity-100-lessons.md` remains required. Roll back application GitOps to `release/1.001.07`; keep widened network ranges until metrics show zero active ICE/TURN allocations.

Production release `release/01.004.01` enables `email-service` with the primary Mailjet API key and the verified `honey.school` sender domain. The first candidate `release/01.004.00` exposed a fail-closed Helm defect: Mailjet pods still referenced mandatory SMTP keys. Fix release `01.004.01` scopes secret references to the selected provider and keeps its credentials mandatory. Jenkins release dispatchers 11 and 12 marked both candidates ready without rebuilding unchanged platform images; the accepted platform commit is `fdc133188e98f6549d71a3a1d5b9bc711eee2cbb`. Backup `/var/backups/playsay/release-01.004.00-20260817T201447Z` passed checksums and archive-list validation for application, keyboard and Keycloak databases. All 18 ArgoCD applications reached `Synced/Healthy` at infra commit `6086d0d43a3c8b8648dc04aef3bd97762be67214`; the email pod is ready with zero restarts. All seven Mailjet Event API callbacks are `alive`, version 2, and the authenticated public webhook smoke returned HTTP 200. Roll back GitOps to `release/01.003.00`; no database restore is required because the release contains no schema change.

Production hotfix `release/01.004.13` enables reusable lesson links with roster-aware email confirmation, teacher-controlled Lobby admission, kick/readmit, one-time Keycloak assertions and optional 30-day remembered entry without mutating user passwords. Jenkins dispatcher 38 accepted platform commit `9812e78400c2b8747537f7fe97e43bfffaaaef29`, built the numeric branch at `b15c57a619dddd0e7172b7c9b7aea682f7d0e6f0`, and marked candidate `d7678a7ce818f75dc35fba54f58ee966d8c5ff25` ready. The operator applied the four additive/cascade Liquibase changesets before rollout, deployed with issuance disabled, configured the conditional Keycloak flow, and enabled issuance only in infra commit `fdd82a93c8cc236374a16b29fbb076a386a66693`. Backup `/var/backups/playsay/release-01.004.13-20260826T175446Z` passed SHA-256 and archive-list validation with 377 application, 84 keyboard and 536 Keycloak entries. All 19 ArgoCD applications reached `Synced/Healthy`; direct and RF origins returned HTTP 200/API `UP`, the assertion was one-time, the remembered cookie was persistent for 30 days, and password credential metadata remained unchanged. Evidence: `migrations/ax41/evidence/20260826-release-01.004.13.md`. Rollback first disables lesson issuance, restores the ordinary browser flow binding, and then returns the production root to `release/01.004.12`; use the verified archives only if a separate incompatible schema or Keycloak recovery decision requires restoration.

Production release `release/01.005.00` reconciles all installed numeric release history into `develop` and enables worksheet import through staged GitOps commits. Jenkins dispatcher 39 accepted platform branch head `b15c57a619dddd0e7172b7c9b7aea682f7d0e6f0`; production uses the immutable worksheet image `sha256:c5e2b5df6d12e7d9c0f8443aa55af4663a3309d10e31ff53d834fbecd7ed2966`. The rollout created the retained `worksheet_import` database and restricted staging bucket, ran one bounded Liquibase changeset, enabled the internal service with the stub provider, passed local synthetic JPEG/PDF review/materialization, and only then enabled the public gateway. Pre-change and post-enablement logical backups passed checksum and archive-list validation, all 19 ArgoCD applications remained `Synced/Healthy`, and direct/RF API, OIDC, browser, keyboard and realtime checks passed. Evidence: `migrations/ax41/evidence/20260828-release-01.005.00.md`. Rollback disables the worksheet gateway first, then its service, and returns the production root to `release/01.004.13`; retain the new database and staging data unless a separately approved restore is required.

For an edge-only reconciliation that does not run the host, virtualization, firewall, WireGuard or Cockpit roles:

```bash
cd playsay-infra/ansible
ansible-playbook \
  -i inventories/hetzner-ax41/hosts.yaml \
  playbooks/ax41-host.yaml \
  --tags edge-proxy
```

The active AX41 split is prod 8 vCPU/38 GiB, dev 2 vCPU/10 GiB and CI 4 vCPU/8 GiB, leaving approximately 6 GiB of the host's 62 GiB usable RAM for Ubuntu, KVM/libvirt, edge routing, VPN and filesystem cache. The 14 guest vCPUs share 12 host logical CPUs without pinning (`1.17×` overcommit); each CI build remains capped at one CPU and Jenkins admits at most four agents. On 2026-07-20 08:50-09:40 Europe/Moscow the old combined VPS used `0.87` compute cores on average (p95 `0.95`, max `0.98`) while `43.9%` average iowait, `0.53 GiB` available memory and active swap made headline CPU/load look much worse. Kubernetes working set was at most `5.95 GiB` in that lesson window and `6.24 GiB` across 2026-07-13 through 2026-07-20, including Jenkins. With Jenkins moved out, 10 GiB is the initial dev allocation. Change guest CPU/RAM only through reviewed OpenTofu. During a four-agent CI trial, reduce `MAX_PARALLEL_MODULE_JOBS` to `1` or `2` if CI reports an OOM kill, sustained swap growth, `MemAvailable` below 1 GiB, or if prod readiness/latency degrades. Do not enable memory ballooning; alert if host `MemAvailable` remains below 4 GiB for 15 minutes and do not increase a guest until sustained swap or memory pressure is ruled out.

OpenTofu remains the source of truth even though day-to-day operations are visual. Cockpit with the Machines/libvirt view is available only through the management VPN for host/VM status, graphs, storage, console and routine start/stop/reboot; Headlamp shows Kubernetes, and ArgoCD/Jenkins show delivery state. Do not create/delete VMs or change CPU, RAM, disks, networks or autostart in Cockpit: submit the change to Git, inspect the OpenTofu plan and apply it after review. Production apply is always a separate manual approval. If an emergency requires a direct Cockpit/`virsh` change, reconcile it into Git immediately and require a clean drift plan afterward.

## Vocabulary service

`vocabulary-service` разворачивается ArgoCD в `playsay-dev`, использует общий `playsay-app-db`, порт `8088` и secret `playsay-openai` только с чувствительным `api-key`. Модель и reasoning effort являются проверяемой Git-конфигурацией: dev/prod используют `gpt-5.6-sol` и `low` для словарных подсказок. Jenkins job `playsay-vocabulary-service-develop` выполняет идемпотентные `liquibase status/update` на каждом deployable build, собирает `playsay-vocabulary-service` и обновляет `helm-charts/vocabulary-service/values-dev.yaml`. Не добавляйте для vocabulary оптимизацию skip-by-changelog-diff: она может оставить новый namespace/database без таблиц, если первый webhook build не запускал migration. Web и keyboard nginx направляют `/api/vocabulary/**` на ClusterIP `vocabulary-service`; этот location обязан передавать `Upgrade`/`Connection` и увеличенные read/send timeout для authenticated `/api/vocabulary/ws`. Отсутствие OpenAI key не блокирует ручное сохранение карточек. Web UI автоматически запрашивает до трёх уверенных вариантов после ввода слова и позволяет перегенерировать их с пользовательским уточнением и исключением уже показанных переводов. Classroom preview получает до пяти слов через `/api/vocabulary/overview`, подписывается на владельца словаря через `vocabulary.subscribe` и после каждого reconnect повторяет REST recovery; teacher subscription должна fail-closed, если actor не управляет уроком/учеником.

После rollout выполните authenticated browser smoke двумя сессиями teacher/student: откройте один classroom, в обеих сессиях раскройте `Словарик → Последние слова`, добавьте слово сначала teacher, затем student и подтвердите появление сверху без reload. Закройте student WebSocket в DevTools, добавьте ещё слово teacher, разрешите reconnect и подтвердите REST-восстановление. Отдельно проверьте, что посторонний teacher получает `403` от `/api/vocabulary/overview` и `error` на `vocabulary.subscribe`; токены и содержимое реального словаря в evidence не сохраняйте.

Dev pod `vocabulary-service` использует проверенный production memory profile: `25m / 384Mi` requests и `500m / 512Mi` limits; JVM явно ограничена `-Xms128m -Xmx256m`. RollingUpdate сохраняет `maxSurge=0`/`maxUnavailable=1`, чтобы single-node dev не запускал две JVM словаря одновременно. Health probes используют `timeoutSeconds=5`, а liveness допускает шесть последовательных сбоев. После rollout проверьте `kubectl -n playsay-dev get pod -l app.kubernetes.io/name=vocabulary-service`, отсутствие роста `restartCount`/`OOMKilled` в `describe pod` и стабильный working set: новый профиль устраняет прежний зазор всего в несколько десятков MiB до лимита `384Mi`, не разрешая JVM занять весь pod limit.

## Sprint 0 Goal

Create a reproducible dev environment:

- Ubuntu 24.04 VPS
- k3s
- Sealed Secrets
- ArgoCD
- Headlamp Kubernetes UI
- Jenkins
- api-gateway backend and React SPA deployed by ArgoCD

In coexist mode on the current VPS, `ingress-nginx` and `cert-manager` are not installed by default. The existing host nginx remains the public entry point for the site, ops UI, and product SPA, and proxies k3s services to local Kubernetes NodePorts.

## Human-Owned Prerequisites

1. Create or choose a VDSina VPS manually:
   - Ubuntu 24.04
   - Amsterdam
   - 2 vCPU / 4 GB RAM / 80 GB NVMe for Sprint 0
   - current dev shape after the 2026-05-24 upgrade: 4 vCPU / 8 GB RAM / 160 GB NVMe / 32 TB traffic
   - key-based `root` SSH access
2. Create GitHub organization or user namespace.
3. Create repositories:
   - `playsay-platform`
   - `playsay-infra`
4. Point DNS records to the VPS:
   - `ops.play-and-say.ru`
   - `online.play-and-say.ru`
   - `key.play-and-say.ru`
5. Create GitHub credentials for Jenkins (see below).

## One-Command Bootstrap

Run from the local `playsay-infra` directory:

```bash
./scripts/bootstrap-dev.sh \
  --ip <server-ip> \
  --domain dev.example.com \
  --email admin@example.com
```

The script:

1. Uses normal SSH config/agent, or a specific key passed by `--ssh-key`.
2. Verifies key-based access to `root@<server-ip>`.
3. Writes `ansible/inventories/dev/hosts.yaml`.
4. Runs Ansible to configure baseline Ubuntu packages, swap, k3s, and node exporter.
5. Copies the infrastructure scripts to `/tmp/playsay-infra-bootstrap` on the VPS.
6. Installs Sealed Secrets, ArgoCD, Headlamp, and Jenkins directly on the VPS using `/etc/rancher/k3s/k3s.yaml`.

By default the script runs in `coexist` mode:

- does not change SSH hardening;
- does not manage UFW/firewall rules;
- does not install Docker;
- does not install ingress-nginx or cert-manager;
- does not bind Kubernetes services to ports 80/443 directly;
- restricts NodePort services to `127.0.0.0/8` during k3s install;
- installs `playsay-public-port-guard.service` to block public access to k3s API/kubelet/flannel technical ports on the public interface;
- binds node exporter to `127.0.0.1:9100`;
- writes only one host nginx file: `/etc/nginx/conf.d/playsay-k8s-dev.conf`.

Use separate subdomains such as `argocd.dev.example.com` and `headlamp.dev.example.com`. Do not pass the existing production site hostname as `--domain`, otherwise nginx server names may overlap.

For ArgoCD to sync the api-gateway application, `playsay-infra` must be pushed to the GitHub URL referenced in `argocd-apps/dev/root-app.yaml`.

For a server that already has Amnezia VPN and a public nginx site, keep the default `coexist` mode:

```bash
./scripts/bootstrap-dev.sh \
  --ip 89.124.113.223 \
  --domain play-and-say.ru \
  --ops-host ops.play-and-say.ru \
  --ops-port 18443 \
  --email admin@example.com
```

This creates nginx server blocks for infrastructure UI and the product SPA:

- `https://ops.play-and-say.ru:18443/headlamp/`
- `https://ops.play-and-say.ru:18443/argocd/`
- `https://ops.play-and-say.ru:18443/jenkins/`
- `https://ops.play-and-say.ru:18443/keycloak/` (Sprint 1 auth)
- `https://ops.play-and-say.ru:18443/victoria-metrics/vmui/` (dev monitoring)
- `https://online.play-and-say.ru`
- `https://key.play-and-say.ru`
- `wss://online.play-and-say.ru/collab/ws` (Sprint 5 collaboration websocket)

The existing `play-and-say.ru` site server block is not overwritten.
The auxiliary `profit-kuban.play-and-say.ru` static vhost is managed separately in `/etc/nginx/conf.d/profit-kuban.conf`; it is not generated by `bootstrap-dev.sh`.

Current dev TLS policy, since 2026-06-03: keep host nginx restricted to TLS 1.2 only for the public site, product SPA, keyboard trainer, auxiliary static vhosts, and ops route. TLS/SNI handshake failures were reported from Russian consumer networks MTS, t2, and MGTS; after disabling TLS 1.3, access recovered from the affected networks. The change was made manually in `/etc/nginx/nginx.conf` and `/etc/letsencrypt/options-ssl-nginx.conf`; backups are `/etc/nginx/nginx.conf.bak.tls12-test-20260603164526` and `/etc/letsencrypt/options-ssl-nginx.conf.bak.tls12-test-20260603164526`. Current validation expects `openssl s_client -tls1_2` to succeed and `openssl s_client -tls1_3` to fail with `protocol version alert`. Do not re-enable TLS 1.3 on dev without a dedicated retest from MTS, t2, and MGTS. Rollback command if TLS 1.3 must be restored for a controlled experiment:

```bash
ssh root@89.124.113.223 '
set -e
cp /etc/nginx/nginx.conf.bak.tls12-test-20260603164526 /etc/nginx/nginx.conf
cp /etc/letsencrypt/options-ssl-nginx.conf.bak.tls12-test-20260603164526 /etc/letsencrypt/options-ssl-nginx.conf
nginx -t
systemctl reload nginx
'
```

TLS mode defaults to `auto`: if `/etc/letsencrypt/live/ops.play-and-say.ru/` exists, nginx uses that certificate; otherwise the script creates a self-signed certificate under `/etc/nginx/playsay-ops/`. Browsers will warn on self-signed certificates, but traffic is encrypted. After DNS is ready, replace it with a Let's Encrypt certificate and rerun the script:

```bash
mkdir -p /var/www/letsencrypt/.well-known/acme-challenge
cat >/etc/nginx/conf.d/playsay-ops-acme.conf <<'EOF'
server {
    listen 80;
    listen [::]:80;
    server_name ops.play-and-say.ru;

    location ^~ /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
        default_type "text/plain";
        try_files $uri =404;
    }

    location / {
        return 301 https://$host:18443$request_uri;
    }
}
EOF
nginx -t && systemctl reload nginx

certbot certonly \
  --webroot \
  -w /var/www/letsencrypt \
  -d ops.play-and-say.ru \
  --non-interactive \
  --agree-tos \
  --email admin@play-and-say.ru

mkdir -p /etc/letsencrypt/renewal-hooks/deploy
cat >/etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
nginx -t
systemctl reload nginx
EOF
chmod 0755 /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh

./scripts/bootstrap-dev.sh \
  --ip 89.124.113.223 \
  --domain play-and-say.ru \
  --ops-host ops.play-and-say.ru \
  --ops-port 18443 \
  --ops-tls-mode existing \
  --email admin@example.com
```

For `online.play-and-say.ru`, issue a matching Let's Encrypt certificate after the web-app upstream is available:

```bash
mkdir -p /var/www/letsencrypt/.well-known/acme-challenge
certbot certonly \
  --webroot \
  -w /var/www/letsencrypt \
  -d online.play-and-say.ru \
  --non-interactive \
  --agree-tos \
  --email admin@play-and-say.ru

./scripts/bootstrap-dev.sh \
  --ip 89.124.113.223 \
  --domain play-and-say.ru \
  --ops-host ops.play-and-say.ru \
  --ops-port 18443 \
  --ops-tls-mode existing \
  --online-host online.play-and-say.ru \
  --online-tls-mode existing \
  --email admin@example.com
```

For `key.play-and-say.ru`, issue a matching Let's Encrypt certificate after `keyboard-app` has a healthy upstream:

```bash
mkdir -p /var/www/letsencrypt/.well-known/acme-challenge
certbot certonly \
  --webroot \
  -w /var/www/letsencrypt \
  -d key.play-and-say.ru \
  --non-interactive \
  --agree-tos \
  --email admin@play-and-say.ru

./scripts/bootstrap-dev.sh \
  --ip 89.124.113.223 \
  --domain play-and-say.ru \
  --ops-host ops.play-and-say.ru \
  --ops-port 18443 \
  --ops-tls-mode existing \
  --online-host online.play-and-say.ru \
  --online-tls-mode existing \
  --key-host key.play-and-say.ru \
  --key-tls-mode existing \
  --email admin@example.com
```

If you know the Amnezia VPN CIDR or a fixed admin IP, restrict the ops UI:

```bash
./scripts/bootstrap-dev.sh \
  --ip 89.124.113.223 \
  --domain play-and-say.ru \
  --ops-host ops.play-and-say.ru \
  --ops-port 18443 \
  --ops-allow-cidrs 10.8.0.0/24,203.0.113.5/32 \
  --email admin@example.com
```

Current dev decision for Sprint 1: keep `ops.play-and-say.ru:18443` reachable from the network, but protected by Jenkins/ArgoCD/Headlamp logins. Later, after Keycloak is available, evaluate a shared SSO flow through the Play&Say Keycloak realm for a more convenient ops login.

If you want to avoid any nginx changes too:

```bash
./scripts/bootstrap-dev.sh \
  --ip 89.124.113.223 \
  --domain play-and-say.ru \
  --email admin@example.com \
  --no-host-nginx
```

## Public Site and Online App Hostnames

Current DNS/nginx split:

- `play-and-say.ru` stays the public marketing/site host.
- `online.play-and-say.ru` serves the React product SPA from k3s service `web-app`.
- `online.play-and-say.ru/collab/ws` proxies directly to the `collaboration-service` NodePort for Yjs websocket rooms.
- `key.play-and-say.ru` serves the anonymous keyboard trainer with authenticated saved progress from k3s service `keyboard-app`.
- `profit-kuban.play-and-say.ru` serves the one-off static Profit-kuban snapshot from `/var/www/profit-kuban/current` through host nginx only.
- `ops.play-and-say.ru:18443` is reserved for dev infrastructure UI.
- `ops.play-and-say.ru:18443/keycloak/` serves the Sprint 1 Keycloak dev instance.

The login redirect is not only an nginx setting. `online.play-and-say.ru` and `key.play-and-say.ru` must both be present in the Keycloak `playsay-web` client allowed redirect URIs, web origins, and post-logout redirects. The future `play-and-say.ru` login button should start Keycloak auth and return users to `online.play-and-say.ru`.

## Auxiliary Static Site: Profit-kuban

`https://profit-kuban.play-and-say.ru` is an auxiliary static snapshot for ООО «ПРОФИТ». It is intentionally outside k3s, ArgoCD and Play&Say CI/CD, and must not replace or edit the root `play-and-say.ru` server block.

Runtime state on the VPS:

- document root symlink: `/var/www/profit-kuban/current`
- immutable releases: `/var/www/profit-kuban/releases/<timestamp>`
- nginx vhost: `/etc/nginx/conf.d/profit-kuban.conf`
- certificate: `/etc/letsencrypt/live/profit-kuban.play-and-say.ru/`

Redeploy the current local snapshot from the Mac:

```bash
RELEASE="$(date -u +%Y%m%dT%H%M%SZ)"
SSH_KEY="$HOME/.ssh/play_and_say_vps_ed25519"

ssh -i "$SSH_KEY" -o IdentitiesOnly=yes root@89.124.113.223 \
  "mkdir -p /var/www/profit-kuban/releases/$RELEASE"

rsync -az --delete \
  --exclude '.DS_Store' \
  --exclude '.server.pid' \
  --exclude '.server.log' \
  --exclude '.check/' \
  -e "ssh -i $SSH_KEY -o IdentitiesOnly=yes" \
  /Users/evgeniymednov/Documents/Projects/Profit-kuban/ \
  root@89.124.113.223:/var/www/profit-kuban/releases/$RELEASE/

ssh -i "$SSH_KEY" -o IdentitiesOnly=yes root@89.124.113.223 "
set -euo pipefail
chown -R root:www-data /var/www/profit-kuban/releases/$RELEASE
find /var/www/profit-kuban/releases/$RELEASE -type d -exec chmod 0755 {} +
find /var/www/profit-kuban/releases/$RELEASE -type f -exec chmod 0644 {} +
ln -sfn releases/$RELEASE /var/www/profit-kuban/current
nginx -t
systemctl reload nginx
"
```

If the certificate is missing, issue it with webroot challenge after the HTTP exact vhost exists:

```bash
mkdir -p /var/www/letsencrypt/.well-known/acme-challenge
certbot certonly \
  --webroot \
  -w /var/www/letsencrypt \
  -d profit-kuban.play-and-say.ru \
  --non-interactive \
  --agree-tos \
  --email admin@play-and-say.ru
```

Verify after each deploy:

```bash
curl -I http://profit-kuban.play-and-say.ru/
curl -I https://profit-kuban.play-and-say.ru/
curl -I https://profit-kuban.play-and-say.ru/styles.css
curl -I https://profit-kuban.play-and-say.ru/assets/site/logo-full.png
openssl s_client -connect profit-kuban.play-and-say.ru:443 -servername profit-kuban.play-and-say.ru -tls1_2 </dev/null
openssl s_client -connect profit-kuban.play-and-say.ru:443 -servername profit-kuban.play-and-say.ru -tls1_3 </dev/null
```

## Keyboard Trainer

`Play&Say Key` runs as a separate anonymous trainer with authenticated saved progress at `https://key.play-and-say.ru`.

Runtime objects:

- frontend ArgoCD app: `keyboard-app`
- backend ArgoCD app: `keyboard-service`
- frontend service: `keyboard-app.playsay-dev.svc.cluster.local`, dev NodePort `32087`
- backend service: `keyboard-service.playsay-dev.svc.cluster.local`
- backend database: `keyboard`
- backend role/user: `keyboard_app`
- runtime/migration secret: `playsay-keyboard-db`

Bootstrap and secret sync:

```bash
./scripts/sync-keyboard-db-secret.sh
kubectl -n playsay-data get secret playsay-postgres-keyboard
kubectl -n playsay-dev get secret playsay-keyboard-db
kubectl -n jenkins get secret playsay-keyboard-db
```

The source secret `playsay-postgres-keyboard` is used by CloudNativePG declarative role management for `keyboard_app`; the synced `playsay-keyboard-db` secret contains `jdbc-uri`, `username`, and `password` for runtime and Jenkins Liquibase. Do not print secret values.

Anonymous `Play&Say Key` practice now stores error analytics through public keyboard-service routes under `/api/anonymous/**`. The browser sends a local `playsay.key.anonymousDeviceId`; the service stores that device id plus an HMAC hash of IP/User-Agent features and never stores the raw IP as the profile key. For production-like environments, create a Kubernetes Secret such as `playsay-keyboard-anonymous` with key `fingerprint-secret` and set `anonymous.fingerprintSecret.existingSecret` / `anonymous.fingerprintSecret.key` in the keyboard-service Helm values. Do not print the secret value. Dev can run without that Secret using the application fallback, but that is not suitable for production-like privacy isolation.

Current anonymous public API hardening is limited to request validation and payload caps for map sizes/key lengths. Dedicated anti-DDoS/rate limiting for `/api/anonymous/**` remains technical debt before a wider public launch.

Keycloak client wiring is managed by:

```bash
./scripts/configure-keycloak-dev.sh
```

The `playsay-web` public client must allow `https://key.play-and-say.ru/*`, `http://localhost:5175/*`, `http://localhost:4175/*`, and the same `127.0.0.1` origins. The trainer uses Authorization Code + PKCE for saved progress and does not use local password/JWT auth. Anonymous practice uses bundled frontend chord sets and must not call protected `/api/*` endpoints without a token.

Keyboard deploys run through separate downstream Jenkins jobs. For normal pushes, `playsay-platform-dispatch-develop` handles `develop` and `playsay-platform-dispatch-release` handles numeric `release/*`; each triggers only the affected keyboard job. Manual runs can still use the jobs directly with `BRANCH_NAME` and optional `GITHUB_AFTER`:

- `playsay-keyboard-backend-develop`: tests `:keyboard-service` and builds/pushes `ghcr.io/mednov-ai/playsay-keyboard-service`; dev branches also apply dev Liquibase, update `values-dev.yaml`, and wait for dev rollout, while numeric release branches pin the digest in matching `values-prod.yaml`.
- `playsay-keyboard-frontend-develop`: runs `keyboard-app` lint/test/build and builds/pushes `ghcr.io/mednov-ai/playsay-keyboard-app`; dev branches update `values-dev.yaml`, wait for rollout, and browser-smoke dev, while numeric release branches pin the production digest without using dev runtime checks.

Check rollout:

```bash
kubectl -n argocd get application keyboard-service keyboard-app
kubectl -n playsay-dev get deploy,svc,pods -l app.kubernetes.io/name=keyboard-service
kubectl -n playsay-dev get deploy,svc,pods -l app.kubernetes.io/name=keyboard-app
curl -k -I --resolve key.play-and-say.ru:443:89.124.113.223 https://key.play-and-say.ru/
curl -k -I --resolve key.play-and-say.ru:443:89.124.113.223 https://key.play-and-say.ru/healthz
```

Expected unauthenticated browser behavior: the trainer screen is visible without a blocking Play overlay; inline Play/Space starts a centered blocking `3 -> 2 -> 1` countdown, typing is ignored during countdown, and completed guest sessions are submitted best-effort to `/api/anonymous/training/results` while the local session continues even if that request fails. The typing strip is a visually obvious two-line focus area with natural in-chord letter spacing and visible gaps only for real spaces; its visible capacity follows measured line width and must not overflow on a 13-inch MacBook-class viewport. If typing stops for more than 3 seconds during a running session, a centered pause/resume overlay appears and Space resumes the same session; Esc exits countdown or paused session focus back to the normal non-blocking trainer interface. After 2 anonymous completions the app softly asks for a display name and stores it in the anonymous profile; after 5 anonymous completions the app shows a soft registration prompt; the sign-in action sends the user through Keycloak and callback returns to `https://key.play-and-say.ru/auth/callback`. Laptop smoke should verify that a full 13-inch class browser viewport has no document-level vertical scroll and the virtual keyboard is centered near edge-to-edge.

## Object Storage

Dev material assets use S3-compatible object storage. The ArgoCD app is `minio`, deployed to namespace `storage` from `helm-charts/minio`.

Current dev shape:

- service: `minio.storage.svc.cluster.local:9000`;
- bucket used by `api-gateway`: `playsay-material-assets`;
- credentials secret: `playsay-object-storage`, copied into namespaces `storage` and `playsay-dev`;
- MinIO is not exposed through host nginx or a public NodePort.

Create or refresh the object-storage secret without printing values:

```bash
./scripts/sync-object-storage-secret.sh
```

The script creates `playsay-object-storage` in namespace `storage` if missing, then copies it to `playsay-dev`. For staging/prod or managed S3-compatible storage, keep the backend contract and change only Helm values/secret values:

- `PLAYSAY_STORAGE_PROVIDER=s3`
- `PLAYSAY_S3_ENDPOINT`
- `PLAYSAY_S3_REGION`
- `PLAYSAY_S3_BUCKET`
- `PLAYSAY_S3_ACCESS_KEY`
- `PLAYSAY_S3_SECRET_KEY`
- `PLAYSAY_S3_PATH_STYLE_ACCESS`
- `PLAYSAY_S3_CREATE_BUCKET`

`api-gateway` streams private material assets through `/api/materials/{materialId}/assets/{assetId}/content`; browsers never need direct MinIO access. YouTube relay thumbnails are stored by `media-service` into the same bucket using the same `playsay-object-storage` secret, while `api-gateway` creates/reuses the `material_asset` row. Legacy `data:image` material assets are intentionally not supported after the MinIO migration.

Check object storage state:

```bash
kubectl -n argocd get application minio
kubectl -n storage get pods,pvc,svc
kubectl -n playsay-dev get secret playsay-object-storage
```

## Payment Service

Sprint 8 adds a separate `payment-service` Spring Boot app in namespace `playsay-dev`.

Runtime wiring:

- ArgoCD app: `payment-service`
- Kubernetes service: `payment-service.playsay-dev.svc.cluster.local`
- api-gateway env:
  - `PLAYSAY_PAYMENT_SERVICE_BASE_URL`
  - `PLAYSAY_PAYMENT_SERVICE_TOKEN`
- payment-service env:
  - `PLAYSAY_PAYMENT_SERVICE_TOKEN`
  - `PLAYSAY_PAYMENT_PROVIDER`
  - `PLAYSAY_PAYMENT_PUBLIC_BASE_URL`
  - `PLAYSAY_YOOKASSA_API_URL`
  - `PLAYSAY_YOOKASSA_SHOP_ID`
  - `PLAYSAY_YOOKASSA_SECRET_KEY`

The base Helm chart keeps `paymentService.provider: disabled` so a new environment can roll out before YooKassa credentials are created. Dev `values-dev.yaml` uses `paymentService.provider: yookassa`; the `playsay-payment` secret in `playsay-dev` must therefore contain `service-token`, `yookassa-shop-id`, and `yookassa-secret-key` before syncing `payment-service`.

For an internal-only disabled-provider smoke, create only the shared service token without printing values:

```bash
kubectl -n playsay-dev create secret generic playsay-payment \
  --from-literal=service-token="$(openssl rand -base64 32)" \
  --dry-run=client -o yaml | kubectl apply -f -
```

To enable or rotate sandbox payments, create or update the same `playsay-payment` secret with YooKassa test credentials:

```bash
kubectl -n playsay-dev create secret generic playsay-payment \
  --from-literal=service-token="$(openssl rand -base64 32)" \
  --from-literal=yookassa-shop-id="<test-shop-id>" \
  --from-literal=yookassa-secret-key="<test-secret-key>" \
  --dry-run=client -o yaml | kubectl apply -f -
```

Then set `helm-charts/payment-service/values-dev.yaml`:

```yaml
paymentService:
  provider: yookassa
```

and deploy through the normal Jenkins -> GHCR -> playsay-infra -> ArgoCD path. YooKassa does not have universal public test credentials; use the test shop credentials issued in the YooKassa merchant cabinet. Do not commit or print the secret values.

The YooKassa merchant cabinet notification URL for dev is:

```text
https://online.play-and-say.ru/api/payment-webhooks/yookassa
```

Keep this URL in YooKassa test settings when rotating credentials; Play&Say does not create YooKassa webhooks automatically.

Because `api-gateway` and `payment-service` read `playsay-payment` keys as environment variables, Kubernetes does not update already-running pods after secret creation or rotation. After creating or rotating this secret, roll both deployments so they pick up the new values:

```bash
kubectl -n playsay-dev rollout restart deployment/api-gateway deployment/payment-service
kubectl -n playsay-dev rollout status deployment/api-gateway
kubectl -n playsay-dev rollout status deployment/payment-service
```

Check payment state:

```bash
kubectl -n argocd get application payment-service
kubectl -n playsay-dev get deploy,svc,pods -l app.kubernetes.io/name=payment-service
kubectl -n playsay-dev get secret playsay-payment
```

## Registration And Email Services

Custom email registration is split into two Spring Boot apps in namespace `playsay-dev`:

- `registration-service`: public registration state machine, pending token storage, managed-student invite storage/token exchange, Keycloak user activation, and password reset email-code state machine for active Keycloak users.
- `email-service`: transactional email DB-template rendering and Mailjet Send API v3.1 integration over HTTPS. SMTP remains a fallback provider option; Spring Mail SMTP healthcheck is disabled by default, so readiness follows the service process rather than provider network health.

The public registration facade is `api-gateway`; it must forward the resolved browser client address to `registration-service` so the service's per-IP rate limiter is not applied to one shared gateway/ingress IP. `registration-service` still falls back to the direct remote address for local/internal calls.

Runtime wiring:

- ArgoCD apps: `registration-service`, `email-service`
- Kubernetes services:
  - `registration-service.playsay-dev.svc.cluster.local`
  - `email-service.playsay-dev.svc.cluster.local`
- api-gateway env:
  - `PLAYSAY_REGISTRATION_SERVICE_BASE_URL`
  - `PLAYSAY_REGISTRATION_SERVICE_TOKEN`
  - `PLAYSAY_USER_DATA_SERVICE_TOKEN`
  - `PLAYSAY_AI_TUTOR_SERVICE_BASE_URL`
  - `PLAYSAY_VOCABULARY_SERVICE_BASE_URL`
  - `PLAYSAY_KEYBOARD_SERVICE_BASE_URL`
  - `PLAYSAY_EMAIL_SERVICE_BASE_URL`
  - `PLAYSAY_EMAIL_SERVICE_TOKEN`
  - `PLAYSAY_EMAIL_MAILJET_WEBHOOK_USERNAME`
  - `PLAYSAY_EMAIL_MAILJET_WEBHOOK_PASSWORD`
  - `PLAYSAY_PUBLIC_APP_URL`
  - `PLAYSAY_CHAT_EMAIL_INITIAL_DELAY` (default `PT2M`)
  - `PLAYSAY_CHAT_EMAIL_COOLDOWN` (default `PT10M`)
  - `PLAYSAY_CHAT_EMAIL_POLL_DELAY_MS` (default `30000`)
  - `PLAYSAY_CHAT_EMAIL_RETRY_DELAYS` (default `PT1M,PT5M,PT15M`)
- registration-service env:
  - `PLAYSAY_REGISTRATION_SERVICE_TOKEN`
  - `PLAYSAY_REGISTRATION_PUBLIC_BASE_URL`
  - `PLAYSAY_REGISTRATION_PASSWORD_RESET_CODE_TTL_MINUTES` (default `15`)
  - `PLAYSAY_REGISTRATION_PASSWORD_RESET_MAX_ATTEMPTS` (default `5`)
  - `PLAYSAY_KEYCLOAK_BASE_URL`
  - `PLAYSAY_KEYCLOAK_REALM`
  - `PLAYSAY_KEYCLOAK_STUDENT_TOKEN_CLIENT_ID` (default `playsay-web`)
  - `PLAYSAY_KEYCLOAK_ADMIN_CLIENT_ID`
  - `PLAYSAY_KEYCLOAK_ADMIN_CLIENT_SECRET`
  - `PLAYSAY_EMAIL_SERVICE_BASE_URL`
  - `PLAYSAY_EMAIL_SERVICE_TOKEN`
- email-service env:
  - `PLAYSAY_EMAIL_DELIVERY_PROVIDER`
  - `PLAYSAY_EMAIL_SERVICE_TOKEN`
  - `PLAYSAY_EMAIL_FROM_ADDRESS`
  - `PLAYSAY_EMAIL_FROM_NAME`
  - `PLAYSAY_EMAIL_SMTP_HOST`
  - `PLAYSAY_EMAIL_SMTP_PORT`
  - `PLAYSAY_EMAIL_SMTP_USERNAME`
  - `PLAYSAY_EMAIL_SMTP_PASSWORD`
  - `PLAYSAY_EMAIL_SMTP_AUTH`
  - `PLAYSAY_EMAIL_SMTP_STARTTLS`
  - `PLAYSAY_EMAIL_SMTP_HEALTH_ENABLED` (default `false`)
  - `PLAYSAY_EMAIL_UNISENDER_API_BASE_URL`
  - `PLAYSAY_EMAIL_UNISENDER_USER_ID`
  - `PLAYSAY_EMAIL_UNISENDER_API_KEY`
  - `PLAYSAY_EMAIL_UNISENDER_WEBHOOK_URL`
  - `PLAYSAY_EMAIL_MAILJET_API_BASE_URL`
  - `PLAYSAY_EMAIL_MAILJET_API_KEY`
  - `PLAYSAY_EMAIL_MAILJET_SECRET_KEY`
  - `PLAYSAY_EMAIL_MAILJET_ENVIRONMENT`
  - `PLAYSAY_EMAIL_MAILJET_WEBHOOK_URL`
  - `PLAYSAY_EMAIL_MAILJET_WEBHOOK_USERNAME`
  - `PLAYSAY_EMAIL_MAILJET_WEBHOOK_PASSWORD`
  - `PLAYSAY_EMAIL_REPLAY_ENCRYPTION_KEY` (base64-encoded 32-byte AES key; secret)
  - `PLAYSAY_EMAIL_DEFAULT_REPLAY_TTL` (default `PT72H`)
  - `PLAYSAY_EMAIL_PROVIDER_TRACKING_TTL` (default `PT72H`)
  - `PLAYSAY_EMAIL_PROVIDER_RECONCILE_WINDOW` (default `PT5M`)
  - `PLAYSAY_EMAIL_PROVIDER_RECONCILE_OVERLAP` (default `PT1M`)
  - `PLAYSAY_EMAIL_PROVIDER_RECONCILE_POLL_MS` (default `30000`; polls an active async dump, while completed reconciliation windows advance every five minutes)
  - `PLAYSAY_EMAIL_WEBHOOK_CHECK_MS` (default `3600000`)

Run or rerun Keycloak bootstrap after this change:

```bash
./scripts/configure-keycloak-dev.sh
```

It creates/updates the confidential Keycloak client `playsay-registration-service`, assigns its service account the required `realm-management` roles for user lookup/update/delete and role reads, enables direct access grants on the public `playsay-web` client for server-side managed-student invite exchange, and writes `keycloak-client-id`, `keycloak-client-secret` plus a stable randomly generated `service-token` into Kubernetes secret `playsay-registration` in namespace `playsay-dev`. Re-running the script preserves an existing service token. Secret values are not printed. The same `service-token` is mounted into `api-gateway`, `registration-service`, `ai-tutor-service`, `vocabulary-service` and `keyboard-service` for internal user-management/data-purge calls only; it must never be exposed to the SPA.

Production keeps the existing client and secret. Before accepting a release that enables public registration, reconcile and verify only its required service-account role mappings from the production guest:

```bash
./scripts/configure-keycloak-prod-registration.sh
```

The production script is idempotent, does not rotate credentials or create users, and fails unless exactly one existing registration client and `realm-management` client are present. It grants only `view-users`, `manage-users`, and `view-realm`, then reads the mappings back before reporting success.

Mailjet uses one primary login with isolated API keys and sending domains:

- production primary API key: sender `Honey School <no-reply@honey.school>` and callback `https://online.honey.school/api/webhooks/mailjet`;
- dev subaccount `Honey School Dev`: sender `Honey School <no-reply@dev.honey.school>` and callback `https://dev.online.honey.school/api/webhooks/mailjet`.

Validate each sending domain under its own API key. Production uses the existing root verification/SPF/DKIM records. Dev must publish the exact Mailjet-generated verification TXT plus SPF/DKIM below `dev.honey.school`; never replace the production `mailjet._domainkey.honey.school` value with a dev key. The public webhook uses HTTPS Basic Auth and the gateway exchanges it for the existing internal email-service token. Generate URL-safe webhook credentials and keep all values outside Git and command output.

Create or patch `playsay-email` in each environment before syncing `email-service`, `registration-service` and `api-gateway`. Preserve the existing service token and replay encryption key. The following names are placeholders only; inject their values through a no-echo shell or the operator's secret workflow:

```bash
read -r -p "Mailjet API key: " MAILJET_API_KEY
read -r -s -p "Mailjet secret key: " MAILJET_SECRET_KEY
printf '\n'
read -r -s -p "Mailjet webhook password: " MAILJET_WEBHOOK_PASSWORD
printf '\n'

kubectl -n playsay-dev patch secret playsay-email --type merge --patch-file /dev/stdin <<EOF
{"stringData":{"from-address":"no-reply@dev.honey.school","mailjet-api-key":"$MAILJET_API_KEY","mailjet-secret-key":"$MAILJET_SECRET_KEY","mailjet-webhook-username":"playsay-mailjet-dev","mailjet-webhook-password":"$MAILJET_WEBHOOK_PASSWORD"}}
EOF

unset MAILJET_API_KEY MAILJET_SECRET_KEY MAILJET_WEBHOOK_PASSWORD
```

For production, repeat the same patch against namespace `playsay-prod`, use `from-address=no-reply@honey.school` and webhook username `playsay-mailjet-prod`, and read credentials from the primary Mailjet API key rather than the dev subaccount. Never copy the dev key into prod or the primary key into dev.

For an existing dev secret, add the replay key only if it is absent; do not rotate it while unexpired replay snapshots may still be resent:

```bash
if ! kubectl -n playsay-dev get secret playsay-email -o jsonpath='{.data.replay-encryption-key}' | grep -q .; then
  REPLAY_SECRET_VALUE="$(openssl rand -base64 32)"
  REPLAY_SECRET_DATA="$(printf '%s' "$REPLAY_SECRET_VALUE" | base64 | tr -d '\n')"
  kubectl -n playsay-dev patch secret playsay-email --type merge -p "{\"data\":{\"replay-encryption-key\":\"$REPLAY_SECRET_DATA\"}}"
fi
```

The environment Helm values set `PLAYSAY_EMAIL_DELIVERY_PROVIDER=mailjet-api`, the environment label and exact callback URL. `email-service` sends one rendered message through `/v3.1/send`, stores Mailjet `MessageID`, tags it with delivery/attempt/environment metadata, registers grouped Event API version 2 callbacks hourly and reconciles unfinished messages through `/v3/REST/message/{MessageID}`. `sent` means destination SMTP acceptance and maps to `DELIVERED`; `open`, `click`, hard/soft bounce, blocked, spam and unsubscribe remain factual provider statuses. `SOFT_BOUNCED` is non-terminal; `BLOCKED` is terminal and cannot be resent automatically. Historical `UNISENDER_API` rows remain readable during and after the switch. Remove the old Unisender secret only after the production canary and a 24-hour observation window.

The Helm deployment mounts credentials only for the selected delivery provider. A Mailjet environment must not require placeholder SMTP or Unisender keys, and the selected provider's credential references remain mandatory so a missing key fails before application startup.

After rollout, sign in as `ADMIN` and open workspace section **Письма**. Confirm that a non-admin profile has no such section and receives `403` from `/api/admin/email-deliveries`. The admin log must show local status separately from provider status, auto-refresh about every 30 seconds, show attempt history without email body/provider credentials, and enable resend only for an eligible failed/expired record. Verify webhook and reconciliation without printing payloads or credentials:

```bash
KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n playsay-dev logs deploy/email-service --since=20m | grep -E 'reconciliation|webhook|delivery'
KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n playsay-dev get pods -l app.kubernetes.io/name=email-service
```

Email texts are not hardcoded in code. `email-service` Liquibase creates and seeds app PostgreSQL table `email_templates` with active FreeMarker templates:

- `registration-confirmation` in `ru`, `en`, `de`, `fr`
- `password-reset-code` in `ru`, `en`, `de`, `fr`
- `lesson-reminder-30m` in `ru`, `en`, `de`, `fr`
- `lesson-rescheduled` in `ru`, `en`, `de`, `fr`
- `chat-unread-digest` in `ru`, `en`, `de`, `fr`

Template rows contain `subject_template`, `text_template`, `html_template`, `version`, `enabled`, timestamps. Runtime rendering falls back to `ru` only if a localized row is missing. Edit rows carefully in DB or add a new Liquibase changeset; keep required model variables (`confirmationUrl`, `code`, `expiresMinutes`) intact.

Do not commit or print email provider credentials. After creating or rotating `playsay-registration` or `playsay-email`, restart the affected deployments so env vars are refreshed:

```bash
kubectl -n playsay-dev rollout restart deployment/api-gateway deployment/registration-service deployment/email-service deployment/ai-tutor-service deployment/vocabulary-service deployment/keyboard-service
kubectl -n playsay-dev rollout status deployment/registration-service
kubectl -n playsay-dev rollout status deployment/email-service
```

Check registration/email state:

```bash
kubectl -n argocd get application registration-service email-service
kubectl -n playsay-dev get deploy,svc,pods -l app.kubernetes.io/name=registration-service
kubectl -n playsay-dev get deploy,svc,pods -l app.kubernetes.io/name=email-service
kubectl -n playsay-dev get secret playsay-registration playsay-email
```

Registration rate limits use a 1-hour window; dev currently allows 20 attempts per normalized email and 30 attempts per resolved client address. If `/api/registration/start` returns `429`, first check whether it is a real per-email/per-client limit or a proxy-address issue:

```bash
kubectl -n playsay-dev logs deploy/api-gateway --since=30m | grep 'registration-service request failed'
kubectl -n playsay-dev logs deploy/registration-service --since=30m | grep -E '429|Too Many Requests|Rate'
```

A healthy gateway forwards `X-Forwarded-For` to `registration-service`; a shared gateway/ingress IP must not be the only address used for public registration rate limits. A rollout restart clears the in-memory limiter, but treat it as a temporary dev relief only. If an earlier email-provider outage created a disabled Keycloak user without a pending registration row, retrying `/register` for that email should create a fresh pending token and send a new confirmation email instead of silently returning `CHECK_EMAIL`.

Public registration acceptance is a disposable-account flow, not an HTTP-page smoke. It uses the external Playwright installation and a random temporary mailbox, prints only a run id, origin and coarse stages, verifies `start → email → confirm → repeat confirm safely → first OIDC password sign-in with STUDENT → PASSWORD_RESET_REQUEST → PASSWORD_RESET_EMAIL → PASSWORD_RESET_CONFIRM → PASSWORD_RESET_SIGN_IN`, proves the old password is rejected and the new password signs in, removes the synthetic identity through the registration-service-owned internal lifecycle, and deletes the mailbox. Cleanup failure fails acceptance. Never reuse a learner/owner address, print the confirmation/reset link or code, retain the mailbox body, or put email/password/token/subject in evidence.

Run dev acceptance from the trusted operator workspace after the web and registration-service ArgoCD applications are `Synced/Healthy`:

```bash
cd playsay-platform
node scripts/smoke/registration-e2e-smoke.mjs
```

The smoke defaults to `https://dev.online.honey.school`, canonical dev issuer, `playsay-dev`, and the current AX41 SSH route. Before a release, also verify a desktop plus phone viewport, all four locale resource structures, keyboard submit/focus, field `aria-invalid`/`aria-describedby`, the Keycloak forgot link with valid and invalid login input, non-color password statuses, exactly one start request, current return-host allow/deny tests, registration-service tests and the web production build.

After a separate production authorization and GitOps promotion, run the same disposable journey once from each supported production online origin. The cleanup route changes only to the production guest/namespace; secret values remain inside the remote shell:

```bash
PLAY_SAY_REGISTRATION_SMOKE_WEB_BASE_URL=https://online.honey.school \
PLAY_SAY_REGISTRATION_SMOKE_AUTH_ISSUER=https://ops.honey.school/keycloak/realms/playsay \
PLAY_SAY_REGISTRATION_SMOKE_SSH_HOST=playsay@10.60.0.20 \
PLAY_SAY_REGISTRATION_SMOKE_NAMESPACE=playsay-prod \
node scripts/smoke/registration-e2e-smoke.mjs

PLAY_SAY_REGISTRATION_SMOKE_WEB_BASE_URL=https://online.honeyschool.ru \
PLAY_SAY_REGISTRATION_SMOKE_AUTH_ISSUER=https://ops.honey.school/keycloak/realms/playsay \
PLAY_SAY_REGISTRATION_SMOKE_SSH_HOST=playsay@10.60.0.20 \
PLAY_SAY_REGISTRATION_SMOKE_NAMESPACE=playsay-prod \
node scripts/smoke/registration-e2e-smoke.mjs
```

Use only coarse stages when diagnosing a failure: `CLIENT_VALIDATION_BLOCKED`, `REQUEST_ROUTING`, `REGISTRATION_SERVICE`, `KEYCLOAK_MUTATION`, `EMAIL_DELIVERY`, `CONFIRMATION`, `OIDC_SIGN_IN`, `PASSWORD_RESET_REQUEST`, `PASSWORD_RESET_EMAIL`, `PASSWORD_RESET_CONFIRM`, `PASSWORD_RESET_SIGN_IN`. The Keycloak forgot link must derive only an exact allowlisted application origin from the current OIDC `redirect_uri`, preserve `.ru`/`.school` continuity, and transfer only a complete valid email. Password-reset service diagnostics are restricted to `event=password_reset_request outcome=CODE_SENT|COOLDOWN|ACCOUNT_NOT_ACTIVE|EMAIL_DELIVERY_FAILED`; the failure event may include only the exception class. A bounded read-only check is:

```bash
kubectl -n playsay-dev logs deploy/registration-service --since=30m | grep 'event=password_reset_request outcome='
```

Correlate only the run timestamp with gateway/registration/email/Keycloak health and Mailjet delivery status; never add email, username, subject, reset code/hash, password, URL, provider identifier/body, secret or exception message to the event. A `CLIENT_VALIDATION_BLOCKED` result means no start request was sent. A successful page load or healthy pod does not satisfy registration acceptance.

For a password-recovery hotfix, accept the exact `develop` source on dev first, merge both platform and infra changes, and create the next unused fixed-width numeric release. The candidate includes the reviewed Keycloak theme desired state and rebuilds only affected platform modules. After the normal pre-release backup and manual migration gate, promote only the `ready` numeric infra branch through ArgoCD. If the hotfix regresses only form validation/presentation or login-link continuity, return the production web/Keycloak desired state to the previous numeric release through GitOps. If password-reset state, email dispatch or Keycloak mutation regresses, roll back registration-service as well. Re-run the retained valid/invalid link/form tests and disposable reset smoke after rollback; never restore protected legacy origins as a shortcut.

Managed-student invite smoke:

1. Sign in as `teacher-demo`, create a managed student from the schedule participant picker, create a lesson with that student, then use the lesson copy-links action.
2. Open the returned `/join#ABC123` style link in a clean browser context. The fragment is a 6-character manual-entry invite code and must not be sent as a `?token=` query parameter; the SPA must read and clear it, call `/api/student-invites/consume`, store the returned Keycloak token set, and redirect to `/lessons/{lessonId}/classroom` without showing the Keycloak login form.
3. Reopen the same invite link in another clean context; it must fail as already consumed or invalid.

### Schedule reschedule and classroom/email smoke

Run this after `api-gateway`, `email-service`, and `web-app` have all rolled out. Use the existing `teacher-demo` and `student-demo` browser profiles; do not repair lesson state with SQL.

1. As `teacher-demo`, create or open a lesson more than 10 minutes in the future. The card and header must say it is planned, must not show a live/join action, and the preparation page must show the exact access-opening time while still allowing material preparation.
2. Open `/lessons/{lessonId}/classroom` directly. The SPA must return to the schedule with a localized explanation; the API `/start` must return localized `409` for the owning teacher, while an unrelated user still sees `404`.
3. From the lesson card menu choose the localized “change date and time” action. Confirm the dialog shows the assigned students and, for a recurring lesson, says only the selected occurrence changes. Save an actually different future time.
4. Confirm the card changes immediately, the other occurrences remain unchanged, and the open classroom (if one was deliberately prepared inside the window before a second transfer) closes with the reschedule explanation.
5. Confirm one `LESSON_RESCHEDULED` queue row per assigned student and rebuilt `LESSON_START_30M` rows. A student without email must become `SKIPPED`; a provider failure must become `FAILED` without reverting the lesson time. A second transfer before dispatch must cancel the older unsent reschedule row.
6. Confirm the received `lesson-rescheduled` message is in the recipient locale and contains the lesson title, old and new local times, teacher, and lesson link. Check `email-service` logs for the delivery outcome without printing provider credentials.
7. Enter a lesson during `start - 10m .. end + 10m` in Chromium and WebKit as teacher and student. After pre-join, both participants must remain connected; outside the window neither role receives a LiveKit token.

Read-only queue verification on the VPS (replace the UUID, do not paste credentials):

```bash
KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n playsay-data exec playsay-postgres-1 -c postgres -- \
  psql -d playsay -c "select reminder_type, recipient_role, status, due_at, previous_scheduled_start, previous_scheduled_end, scheduled_start_snapshot, scheduled_end_snapshot from lesson_email_reminder where lesson_id = '<lesson-uuid>' order by created_at;"
KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n playsay-dev logs deploy/email-service --since=15m | grep -E 'lesson-rescheduled|delivery|provider'
```

For the known lesson `19.07.2026 10:00–10:45 Europe/Moscow`, saving the same time through this dialog is the supported repair for an erroneous early `IN_PROGRESS`: expect `SCHEDULED`, cleared actual timestamps, and rebuilt start reminders, but no `LESSON_RESCHEDULED` email because the time did not actually change. Verify email delivery with an actual reschedule of a disposable smoke lesson instead.

### Chat delivery and offline email smoke

Deploy in the order `email-service` (template migration), `api-gateway` (chat migration/queue), then `web-app`. The current presence contract assumes one `api-gateway` replica; do not scale it horizontally until chat presence is moved to a shared broker.

Browser chat notifications are an explicit opt-in Web Push path layered before the unchanged email digest fallback. The chart keeps `chatPush.enabled=false` by default. Dev may enable it only after the P-256 private key and a `mailto:` or HTTPS subject exist as keys `private-key` and `subject` in the environment-local `playsay-chat-push` Secret; only the matching public key belongs in `values-dev.yaml`. Never print, commit, reuse across environments, or expose the private key through capability responses. A VAPID key rotation requires replacing the Secret and public value together, rolling out `api-gateway`, and asking users to disable and enable notifications again because existing browser subscriptions are bound to the old application-server key.

1. Open the same teacher/student dialog in two authenticated browser profiles. A new outgoing message must move from one grey check after REST save to two grey checks after delivery and two orange checks after the recipient opens the dialog.
2. Close every Play&Say tab for the recipient, send several short messages within two minutes, and confirm only one `chat_email_digest` row remains `PENDING` with all message links.
3. Confirm one localized `chat-unread-digest` email arrives after the two-minute grace period. It must show the message count and sender name, contain no message body, and open `/?chat=<conversationId>` or `/?chat=open`.
4. Send more messages after the first email. No second email may be sent before `sent_at + 10 minutes`; without new messages there must be no repeat at all.
5. Repeat with the recipient returning online or reading before `due_at`: the digest becomes `SKIPPED`. A recipient without email is also `SKIPPED`; provider errors retry with the configured 1/5/15-minute backoff and eventually become `FAILED` without losing chat messages.
6. With notifications disabled in chat, confirm the browser does not request permission. Enable them from the chat bell and confirm the authenticated `GET /api/chat/push/capability` returns only `enabled` and the public key, followed by one active subscription for that account. Permission denial must leave chat and email usable and show the localized denied state.
7. Hide or close the recipient tab and send one message. Expect one generic localized Honey School notification containing no sender, student, lesson, or message text. Clicking it must focus or open the same-origin `/?chat=<conversationId>` deep link. With a visible client, expect no system notification; the unread badge must still update without reload.
8. Read the dialog before the push worker claims the delivery and confirm the row becomes `SKIPPED`. A successful push changes neither `delivered_at` nor read ticks and does not cancel the email digest. Repeated delivery for the same message/subscription must not create a second notification.

Read-only capability and sanitized monitoring checks:

```bash
curl -fsS -H "Authorization: Bearer $ACCESS_TOKEN" https://dev.online.honey.school/api/chat/push/capability | jq '{enabled, publicKeyPresent: (.publicKey | length > 0)}'
curl -fsS https://dev.online.honey.school/api/actuator/prometheus | grep -E '^playsay_chat_push_(deliveries|outcomes)'
KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n playsay-data exec playsay-postgres-1 -c postgres -- \
  psql -d playsay -c "select status, count(*) from chat_push_delivery group by status order by status;"
```

Metrics are deliberately limited to delivery status/outcome. Do not add endpoint, subscription keys, user id, conversation id, message id, or content labels. Rising `invalid` outcomes mean browser endpoints returned permanent `404/410`; the worker deactivates those subscriptions and the user must opt in again. `retrying` indicates bounded provider/network retry, while `failed` means the configured retries were exhausted.

For push-first rollback, set `chatPush.enabled=false` in the affected environment values and deliver that GitOps commit before removing or rotating the environment Secret. Chat, receipts, unread reconciliation, and the email digest must continue normally while push is disabled. Do not delete delivery rows as part of rollback.

Read-only queue verification on the VPS:

```bash
KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n playsay-data exec playsay-postgres-1 -c postgres -- \
  psql -d playsay -c "select recipient_user_id, status, attempts, due_at, sent_at, created_at from chat_email_digest order by created_at desc limit 20;"
KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n playsay-dev logs deploy/api-gateway --since=20m | grep -E 'chat digest email failed'
KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n playsay-dev logs deploy/email-service --since=20m | grep -E 'chat-unread-digest|delivery|provider'
```

## YouTube RF Relay

The product has a risk-flagged YouTube relay path for authorized Play&Say material video blocks. It is disabled by default and must stay disabled unless the business explicitly accepts the current risk profile.

Runtime controls in the `api-gateway` chart:

- `PLAYSAY_YOUTUBE_RF_RELAY_ENABLED`: must be `"true"` to allow relay decisions. Default is `"false"`.
- `PLAYSAY_YOUTUBE_RF_RELAY_GEO_COUNTRY_HEADER`: trusted reverse-proxy header used as IP geolocation country, for example `X-PlaySay-Geo-Country`.
- `PLAYSAY_YOUTUBE_RF_RELAY_REQUIRE_GEO_COUNTRY`: must stay `"true"` outside temporary dev testing. When `"false"`, the backend skips the trusted IP country header requirement but still requires an authenticated `countryCode=RU` app profile and all material/video policy checks.
- `PLAYSAY_MEDIA_SERVICE_BASE_URL`: internal ClusterIP URL, default `http://media-service.playsay-dev.svc.cluster.local`.
- `PLAYSAY_MEDIA_SERVICE_TOKEN`: shared secret used only for gateway -> media-service internal endpoints; created by `scripts/sync-media-secret.sh` as Kubernetes secret `playsay-media`.

Runtime controls in the `media-service` chart:

- `PLAYSAY_MEDIA_SERVICE_TOKEN`: same shared secret; required for `/internal/youtube/*`.
- `PLAYSAY_MEDIA_SERVICE_SESSION_TTL_SECONDS`: short-lived playback session TTL, default `900`.
- `PLAYSAY_MEDIA_SERVICE_MAX_UPSTREAM_RANGE_BYTES`: maximum upstream Range window for relay stream requests, default `1048576`.
- `PLAYSAY_MEDIA_SERVICE_MAX_THUMBNAIL_BYTES`: thumbnail download cap, default `5242880`.
- `PLAYSAY_MEDIA_SERVICE_YTDLP_PATH`: executable used by `media-service` for YouTube metadata, format selection, thumbnail source URL, and upstream media URLs; default `/usr/local/bin/yt-dlp`.
- `PLAYSAY_MEDIA_SERVICE_YTDLP_PLUGIN_DIRECTORY`: yt-dlp plugin search root; the pinned standalone binary requires `/usr/local/lib`, which contains `yt-dlp-plugins/yt_dlp_plugins`.
- `PLAYSAY_MEDIA_SERVICE_YTDLP_JS_RUNTIME`: JS challenge runtime; the pinned image uses `deno:/usr/local/bin/deno`.
- `PLAYSAY_YOUTUBE_POT_ENABLED`: dev-only switch for automatic YouTube PO Token support; default `false`.
- `PLAYSAY_YOUTUBE_POT_PROVIDER_BASE_URL`: loopback-only bgutil sidecar endpoint, default `http://127.0.0.1:4416`.
- `PLAYSAY_YOUTUBE_POT_ALLOWED_VIDEO_IDS`: comma-separated spike allowlist; keep empty outside the controlled dev experiment.
- `PLAYSAY_YOUTUBE_POT_PLAYER_CLIENTS`: yt-dlp player client list for allowlisted videos; spike default `mweb`.
- `PLAYSAY_YOUTUBE_POT_SLEEP_REQUESTS_SECONDS`: bounded delay between yt-dlp YouTube requests; spike default `1`.
- `PLAYSAY_MEDIA_SERVICE_FFMPEG_PATH`: pinned static ffmpeg used to merge separate MP4/M4A streams; default `/usr/local/bin/ffmpeg`.
- `PLAYSAY_YOUTUBE_CACHE_ENABLED`: independent cache feature flag, default `false`; it must have the same value in `api-gateway` and `media-service`.
- `PLAYSAY_MEDIA_SERVICE_CACHE_DOWNLOAD_TIMEOUT_SECONDS`: full download/merge timeout, default `600`.
- `PLAYSAY_MEDIA_SERVICE_CACHE_MAX_VIDEO_BYTES`: final MP4 cap, default `262144000` (250 MiB).
- `PLAYSAY_MEDIA_SERVICE_CACHE_TEMP_DIRECTORY`: disk-backed working directory, mounted as a size-limited `emptyDir`, default `/tmp/playsay-media-cache` with `1Gi` limit.

Relay eligibility is strict: the authenticated app profile must have `countryCode=RU`, the trusted IP country header must be `RU`, the user must already have normal Play&Say access to the material, the block must be a YouTube `videoEmbed`, and effective video metadata must show duration `<= 420` seconds and English language. If stored `videoMeta` is missing or incomplete, `api-gateway` may call the internal `media-service` metadata endpoint by parsed YouTube `videoId`; `media-service` uses `yt-dlp` without an external API key. Complete on-demand metadata is saved into the existing cache record. Missing metadata remains fail-closed only for RF relay and cache downloads. When RF relay is disabled, a valid YouTube ID returns the official privacy-enhanced embed even if duration or language is unavailable. Known policy violations, such as duration over seven minutes or a known non-English language, remain blocked.

When automatic metadata is unavailable, a teacher may enter the observed duration (`m:ss`, maximum `7:00`) and explicitly confirm English audio in the material editor. This stores `videoMeta.validationStatus=TEACHER_CONFIRMED`; changing the video URL or provider removes the confirmation. Existing material authorization remains the trust boundary for this write. No Google Cloud project or YouTube Data API key is required.

### Dev-only YouTube PO Token spike

The current pinned media image contains `yt-dlp 2026.07.04`, Deno `2.6.9`, bundled `yt_dlp_ejs`, and `bgutil-ytdlp-pot-provider 1.3.1`. The Helm chart can add the provider as a same-pod sidecar bound only to port `4416`; no Service or ingress exposes it. The media container calls it over `127.0.0.1`, and no account cookies or manually copied PO tokens are stored. The dev values enable the experiment only for the explicit test allowlist; every other video keeps the existing extractor path.

Verify the runtime before testing:

```bash
kubectl -n playsay-dev exec deploy/media-service -c media-service -- /usr/local/bin/yt-dlp -v --simulate 'https://www.youtube.com/watch?v=9r4D-D18f_g' 2>&1 \
  | grep -E 'yt-dlp version|Optional libraries|JS runtimes|Plugin directories|PO Token Providers'
kubectl -n playsay-dev get pod -l app.kubernetes.io/name=media-service \
  -o custom-columns=NAME:.metadata.name,READY:.status.containerStatuses[*].ready,RESTARTS:.status.containerStatuses[*].restartCount
```

Expected verbose signals for an allowlisted video are Deno under `JS runtimes`, the configured plugin directory, and a `bgutil:http` PO Token provider. Application logs may contain `potEnabled=true` and one of the bounded `failureKind` values (`EMBED_DISABLED`, `BOT_CHECK`, `PO_TOKEN_REQUIRED`, `RATE_LIMITED`, `FORMAT_UNAVAILABLE`, `PRIVATE_VIDEO`, `VIDEO_UNAVAILABLE`, `UNKNOWN`), but must not contain a token, visitor data, cookies, or extracted upstream URLs.

The spike matrix is `WX8HmogNyCY`, `8ChQVaEAKsk`, `BwHMMZQGFoM`, and `OsuWvoBWOnA`; `FkL8j0wIRf8` is diagnostic-only because YouTube may have removed it, and `9r4D-D18f_g` remains the non-kids control. Success requires metadata plus live relay and `MEDIUM` MinIO cache Range playback for at least three of the four matrix videos. Use temporary materials/references, archive them after evidence is captured, delete the test cache objects through the authenticated internal DELETE endpoint, and confirm two non-overlapping requests return `206` with correct `Content-Range`.

Dev acceptance on 2026-07-20 met the threshold: `WX8HmogNyCY`, `8ChQVaEAKsk`, and `OsuWvoBWOnA` passed English metadata, relay Range playback, and cached Range playback; `BwHMMZQGFoM` was transport-successful but correctly rejected by the product language policy because YouTube reports `id`. The teacher material UI also played `OsuWvoBWOnA` through the Play&Say video element even though normal owner embed is disabled (`paused=false`, `readyState=4`, timeline advanced, 720p). The first concurrent relay/cache attempt OOM-killed the main container at `896Mi`; dev therefore reserves `1280Mi` for the main container and caps JVM RAM percentages at `20/35`, leaving headroom for `yt-dlp` and `ffmpeg`. Treat a new OOM/restart during the same concurrency test as a regression.

Rollback is to set `youtubePot.enabled=false` in `values-dev.yaml` and sync ArgoCD; this removes the sidecar and makes all yt-dlp calls ignore the provider arguments. Do not delete unrelated cache objects, stop Docker/k3s/Amnezia, or change the public-site nginx configuration.

The `api-gateway` owns material authorization, policy decisions, `material_asset` rows, durable YouTube cache jobs, and material-to-cache references. The `media-service` owns `yt-dlp`, pinned static `ffmpeg`, in-memory playback sessions, quality selection, thumbnail/video bytes upload to MinIO/S3, and Range/chunked streaming. Gateway reserves/reuses a `VIDEO_THUMBNAIL` asset with provider `YOUTUBE` and metadata `{ blockId, videoId, sourceThumbnailUrl }`; if thumbnail storage fails, playback must continue and only a safe warning should be logged. Public video bytes do not pass back through gateway: playback responses return `relayUrl=/api/media/video-playback-sessions/{sessionId}/stream`, and the web-app nginx maps that path to `media-service`.

When the backend returns `BLOCKED` or `NEEDS_REVIEW` for an authorized material playback request, the web-app must show a local Play&Say unavailable state with the backend `mode/reason` instead of silently falling back to a YouTube iframe. This is intentional for RF relay testing: missing metadata, duration/language policy failures, or server decision errors must be visible without requiring the student's browser to resolve YouTube domains.

The RF relay frontend uses a custom Play&Say HTML5 player. `VIDEO_PLAYBACK_LOADING` is a neutral pending state, not an unavailable error. Before the learner presses Play, the relay `<video>` must keep `preload="none"` and must not attach the stream `src`; before that point there should be no `media-service stream response` log lines. The stream `src` must be attached imperatively from the user click handler, not rendered by React as a normal `src` prop, so the browser does not interrupt the first `play()` with a second load. After Play, the first click sets `src`, seeks to the clip start, calls `play`, retries a transient interrupted first `play()` while metadata is preparing, then normal browser Range requests may be large and may buffer client-side. The playback source is fixed when the short-lived session is created: an active relay session is never switched to a newly ready cache object.

The media stream service also bounds upstream range windows to reduce full-file upstream requests. Browser requests like `Range: bytes=0-` are forwarded upstream as a finite range capped by `PLAYSAY_MEDIA_SERVICE_MAX_UPSTREAM_RANGE_BYTES` (default `1048576` bytes), oversized explicit ranges are capped to the same window, and missing Range headers synthesize an initial bounded range. In `media-service stream response` logs compare `rangeHeader`, `upstreamRangeHeader`, and `rangeLimited=true|false`; a healthy first request should normally show `status=206`, `rangeLimited=true`, and a finite `contentRange`.

`api-gateway` logs playback decisions with material/block/session/video IDs, but must not log raw YouTube query values such as `si` or any extracted media URL. `media-service` logs metadata/session/stream/cache diagnostics with video ID, state, selected quality/height, byte size, attempt, and duration, but must not log upstream media URLs. The stream endpoint is `GET` permit-all because native HTML5 video requests cannot attach the SPA bearer token; the unguessable playback session id is the short-lived capability token, and unknown/expired sessions return `404`. Arbitrary upstream URLs remain forbidden. The only permitted video-byte cache is the controlled private object described below.

### YouTube MinIO cache

Saving a new or changed non-archived material reconciles every YouTube `videoEmbed` block in the same database transaction. References are unique by material/block and point to one shared `videoId + MEDIUM` cache row, so two materials never create two objects. Saving the material is not coupled to download success. Archiving removes its references. On startup, an idempotent reconciliation scans existing active materials once.

The single-thread gateway worker polls every 5 seconds and uses a 15-minute lease. Jobs move through `PENDING`, `IN_PROGRESS`, `READY`, `RETRY`, or `REJECTED`. An expired lease is claimable after a worker restart. Transient failures retry after 1, 5, and 30 minutes, then every 6 hours while at least one reference remains. The worker rejects metadata outside the existing English and `<=420s` policy before download. An oversized final file is also rejected; unavailable or transient download/storage failures never block material save or playback.

`media-service` implements idempotent `POST /internal/youtube/video-cache` and `DELETE /internal/youtube/video-cache/{videoId}?quality=MEDIUM` under the existing `X-PlaySay-Media-Service-Token`. It downloads the best compatible MP4 up to 720p without upscale; split video/audio streams are merged with the pinned static ffmpeg in the image. The final object is `youtube-cache/v1/{videoId}/medium.mp4`. Download uses the 1 GiB `emptyDir`, has a 10-minute timeout and 250 MiB final-file limit, then uploads from the file path so the JVM never retains the full movie.

For a new `MEDIUM` playback session, `media-service` validates the object with HEAD before selecting `MINIO_CACHE`; `LOW` and `HIGH` always use `YOUTUBE_RELAY`. The same short-lived public stream URL serves both sources. MinIO remains private, Range GET is bounded, and a missing/invalid cache automatically falls back to a freshly resolved relay stream. Playback responses expose `deliverySource=MINIO_CACHE|YOUTUBE_RELAY` and the gateway cache state. Objects with no references are retained for 30 days, then the daily cleanup calls media-service DELETE; a deletion error keeps the database row for the next attempt.

Monitor these Prometheus metrics: `playsay_youtube_cache_lookups_total`, `playsay_youtube_cache_streams_total`, `playsay_youtube_cache_downloads_total`, `playsay_youtube_cache_download_duration_seconds`, `playsay_youtube_cache_jobs_total`, `playsay_youtube_cache_job_duration_seconds`, and `playsay_youtube_cache_bytes`. Both backend images include the Prometheus Micrometer registry and expose `/actuator/prometheus`; the gateway security policy permits this scrape endpoint without a bearer token. `monitoring-lite` vmagent scrapes the cluster-internal `api-gateway` and `media-service` services every 30 seconds. Because active references have no TTL, alert on MinIO capacity and the total-ready-bytes gauge; the current dev MinIO PVC must not be treated as unlimited.

Safe rollout order:

1. Deploy the `api-gateway` migration/API with `video.youtube.cache.enabled="false"`; verify the new tables and gateway readiness.
2. Deploy the `media-service` image with yt-dlp, `/usr/local/bin/ffmpeg`, S3 access, and the 1 GiB temp volume, still with cache disabled.
3. Set `video.youtube.cache.enabled="true"` in the api-gateway dev values and `mediaService.youtubeCacheEnabled="true"` in media-service dev values, push `playsay-infra/develop`, and wait for both ArgoCD applications to become `Synced/Healthy`.
4. Save a policy-eligible YouTube block, confirm one cache row reaches `READY`, verify the MinIO key and a `MEDIUM` playback response with `deliverySource=MINIO_CACHE`, then request two ranges and expect `206` with correct `Content-Range`. Confirm `LOW`/`HIGH` return `YOUTUBE_RELAY`.
5. Check the corresponding Jenkins module builds and the final image tags recorded by ArgoCD before calling the rollout complete.

Fast cache rollback is non-destructive: set both cache flags to `"false"`, push `playsay-infra/develop`, and wait for the gateway and media-service rollouts. New sessions immediately use the existing tunnel; `READY` objects and rows remain available for a later re-enable. Do not delete MinIO objects during feature rollback. If the media-service image itself must be rolled back, disable the gateway flag first so no long internal download calls are started against the older service.

Useful RF relay log checks:

```bash
kubectl -n playsay-dev logs deploy/api-gateway --since=30m | grep 'YouTube RF relay playback decision'
kubectl -n playsay-dev logs deploy/api-gateway --since=30m | grep 'YouTube RF relay thumbnail'
kubectl -n playsay-dev logs deploy/media-service --since=30m | grep 'media-service yt-dlp'
kubectl -n playsay-dev logs deploy/media-service --since=30m | grep 'media-service stream response'
```

For a `YOUTUBE_METADATA_MISSING` report, expect fields like `urlKind=SHORT`, parsed `videoId=<id>`, and `videoMetaPresent=false` or `durationPresent=false` / `languagePresent=false`. A successful extractor lookup logs `media-service yt-dlp resolved metadata` and a gateway decision with `metadataSource=MEDIA_SERVICE_ON_DEMAND`. If extraction fails, the teacher may confirm metadata manually. With relay disabled, missing metadata produces `mode=EMBED`, `reason=RF_RELAY_DISABLED_METADATA_OPTIONAL`, and no playback session or media-service stream line.

Video relay streaming needs buffering disabled on both proxy layers. The web-app container nginx has a specific `/api/media/video-playback-sessions/` location before generic `/api/`, rewrites `/api/media/...` to `media-service`, and disables `proxy_buffering` / `proxy_request_buffering`. Host nginx must include the same specific `/api/media/video-playback-sessions/` location under `online.play-and-say.ru` with buffering off and long `proxy_read_timeout` / `proxy_send_timeout` values. After changing the host nginx generator on an existing VPS, re-render or manually verify `/etc/nginx/conf.d/playsay-k8s-dev.conf`, then run `nginx -t` and reload nginx without stopping Docker, k3s, or Amnezia.

The temporary dev RF relay spike is disabled after the 2026-08-18 YouTube bot-check incident: `video.youtube.rfRelay.enabled: "false"` and `video.youtube.rfRelay.requireGeoCountry: "true"`. Dev therefore uses the official embed; missing metadata does not block that mode. Re-enable relay only in a separate reviewed experiment after a new extractor path passes metadata, session, Range playback and cache acceptance without cookies or account credentials.

Do not trust a client-supplied geolocation header directly. Host nginx or another trusted edge proxy must strip any inbound `X-PlaySay-Geo-Country` header from the public request and set its own value before proxying to `web-app`/`api-gateway`. Outside the temporary dev test bypass above, keep `PLAYSAY_YOUTUBE_RF_RELAY_ENABLED=false` until that edge geolocation is configured and verified.

Fast rollback: set `helm-charts/api-gateway/values-dev.yaml` `video.youtube.rfRelay.enabled` back to `"false"`, commit to `playsay-infra`, push `develop`, and let ArgoCD roll out the disabled value. The relay stream endpoint accepts only short-lived playback session IDs; it must never be changed to accept arbitrary YouTube URLs. Logs must not include extracted upstream media URLs or secret values.

## Lightweight Monitoring

Dev monitoring uses a lightweight VictoriaMetrics GitOps app instead of full `kube-prometheus-stack`. The current dev is the AX41 guest `playsay-dev` (`10.60.0.30`, 2 vCPU/10 GiB); Jenkins runs separately on `playsay-ci` (`10.60.0.40`) and is not part of the dev workload baseline. The ArgoCD app is `monitoring-lite`, deployed to namespace `monitoring` from `helm-charts/monitoring-lite`.

Components:

- `victoria-metrics`: single-node time series storage, retention `3d`, PVC `5Gi`;
- `vmagent`: Prometheus-compatible scraper and remote writer to VictoriaMetrics;
- `kube-state-metrics`: pod/deployment/restart/readiness metadata;
- `blackbox-exporter`: HTTP probes for public Play&Say endpoints;
- `vmalert`: evaluates alert rules against VictoriaMetrics;
- `alertmanager`: routes alerts to Telegram if Telegram secret exists.

The Ansible-managed guest `prometheus-node-exporter` remains bound to `127.0.0.1:9100` on `playsay-dev`. Do not deploy a second node-exporter DaemonSet in the dev guest. `vmagent` runs with `hostNetwork: true` and scrapes the existing guest exporter through localhost. Its own HTTP listener is bound to `127.0.0.1` inside guest networking and is not exposed publicly.

LiveKit metrics are enabled in the `livekit` chart with `prometheus_port: 6789`; vmagent scrapes `livekit.livekit.svc.cluster.local:6789`.

Blackbox probes cover `online.play-and-say.ru`, `key.play-and-say.ru`, ArgoCD, VictoriaMetrics UI, and Jenkins login. The Jenkins probe must target `https://ops.play-and-say.ru:18443/jenkins/login`, not `/jenkins/`, because unauthenticated `/jenkins/` is expected to return `403 Forbidden` on a healthy controller.

Expected extra steady-state footprint is roughly `300-600Mi` RAM, depending on series count and scrape load. If memory pressure appears during Jenkins builds or group video tests, first reduce `monitoring-lite` retention/scrape targets before increasing VPS size.

Telegram alerts are optional at boot. Alertmanager starts with a null receiver when the secret is missing, so ArgoCD remains healthy. During the 2026-06-27 resource incident this meant active alerts were visible in Alertmanager/VMUI but were not delivered externally. To enable Telegram notifications, create the secret manually without printing values:

```bash
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
read -rsp "Telegram bot token: " TELEGRAM_BOT_TOKEN; echo
read -rp "Telegram chat id: " TELEGRAM_CHAT_ID
kubectl -n monitoring create secret generic playsay-telegram-alerts \
  --from-literal=bot-token="$TELEGRAM_BOT_TOKEN" \
  --from-literal=chat-id="$TELEGRAM_CHAT_ID" \
  --dry-run=client -o yaml | kubectl apply -f -
unset TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID
kubectl -n monitoring rollout restart deployment/monitoring-lite-alertmanager
kubectl -n monitoring get secret playsay-telegram-alerts
kubectl -n monitoring rollout status deployment/monitoring-lite-alertmanager
```

Check monitoring state:

```bash
kubectl -n argocd get application monitoring-lite
kubectl -n monitoring get pods
kubectl -n monitoring top pods
```

Access VictoriaMetrics UI through the ops host:

```bash
curl -k -I https://ops.play-and-say.ru:18443/victoria-metrics/vmui/
```

Then open `https://ops.play-and-say.ru:18443/victoria-metrics/vmui/`.

The short `/vmui/` path redirects to `/victoria-metrics/vmui/`. The upstream is the localhost-only NodePort `127.0.0.1:32085`, backed by service `monitoring-lite-victoria-metrics`; direct public NodePort access must stay blocked by the k3s/host nginx coexist setup. Host nginx denies VictoriaMetrics admin/service endpoints under `/victoria-metrics/api/v1/admin`, `/debug`, `/flags`, and `/metrics`. Before staging/prod, protect VMUI with VPN/allowlist or shared ops auth.

Local port-forward remains useful if host nginx is being repaired:

```bash
kubectl -n monitoring port-forward svc/monitoring-lite-victoria-metrics 8428:8428
```

Then open `http://127.0.0.1:8428/victoria-metrics/vmui/`.

Useful smoke queries in VMUI:

```text
up
node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes
probe_success
kube_pod_container_status_restarts_total
```

### Cross-network classroom performance gate

The 2026-07-19 13:30–13:45 Europe/Moscow incident was not CPU or NIC saturation: host CPU stayed below 23% and traffic below 1 MiB/s, but available memory fell to `0.51–0.63 GiB`, swap and major page faults were active, and IO pressure reached about 7%. In the same two-party LiveKit room, RTT reached about `695 ms`, jitter `85 ms`, packet loss `4.6%`, NACK bursts hundreds per second, and logs contained multi-second clock-skew/DTLS reconnects. Treat browser main-thread pressure, collaboration WebSocket volume, host memory pressure, and the independent LiveKit media path as separate signals.

After changes to classroom realtime, LiveKit, TURN, or host capacity, repeat a 30-minute teacher/student run from different networks with camera/microphone, continuous drawing, and at least three shared HTML-game open/close cycles. Capture VictoriaMetrics and LiveKit metrics for that exact interval and accept the current 8 GiB node only when:

- drawing and game actions do not reset and do not cause visible media freezes longer than one second;
- there are no DTLS reconnects or multi-second media clock-skew entries;
- LiveKit RTT p95 is below `300 ms`, packet loss below `2%`, jitter p95 below `50 ms`, and NACK rate is not sustained above `50/s`;
- `node_memory_MemAvailable_bytes` remains at least `1 GiB`, with no sustained swap-in/out or major page faults;
- a 1000-point stroke produces incremental, linear Yjs traffic below `250 KiB`, and unchanged HTML-game DOM is not republished.

First fix application/TURN behavior and rerun this gate on the existing 8 GiB VPS. If memory or media criteria still fail while CPU and network throughput remain below saturation, upgrade the dev VPS to 16 GiB and repeat the same interval. Do not stop Docker, Amnezia, nginx, k3s, the public root site, or unrelated workloads during measurement or upgrade preparation.

## Post-Install Verification

Check the public site still works:

```bash
curl -I https://play-and-say.ru
```

Expected: `HTTP/1.1 200 OK`.

Check cluster health:

```bash
ssh root@89.124.113.223 "kubectl get nodes -o wide && kubectl get pods -A"
```

Expected:

- node status is `Ready`;
- ArgoCD pods are `Running`;
- Headlamp pod is `Running`;
- Jenkins pod is `2/2 Running`;
- Sealed Secrets pod is `Running`;
- kube-system pods are `Running`.

Check ops UI before DNS exists by forcing local resolution:

```bash
curl -k -I --resolve ops.play-and-say.ru:18443:89.124.113.223 https://ops.play-and-say.ru:18443/headlamp/
curl -k -I --resolve ops.play-and-say.ru:18443:89.124.113.223 https://ops.play-and-say.ru:18443/argocd/
curl -k -I --resolve ops.play-and-say.ru:18443:89.124.113.223 https://ops.play-and-say.ru:18443/jenkins/login
curl -k -I --resolve ops.play-and-say.ru:18443:89.124.113.223 https://ops.play-and-say.ru:18443/keycloak/
curl -k -I --resolve ops.play-and-say.ru:18443:89.124.113.223 https://ops.play-and-say.ru:18443/victoria-metrics/vmui/
curl -k -I --resolve online.play-and-say.ru:443:89.124.113.223 https://online.play-and-say.ru/
```

Expected:

- Headlamp: `200 OK`;
- ArgoCD: `200 OK`;
- Jenkins: `403 Forbidden` or login redirect, which means Jenkins is alive and requires authentication.
- Keycloak: `200 OK` or a redirect/login response, which means Keycloak is alive behind nginx.
- VictoriaMetrics VMUI: `200 OK`.
- Online SPA: `200 OK`.

Check existing services:

```bash
ssh root@89.124.113.223 "docker ps --format '{{.Names}} {{.Ports}}' && systemctl is-active nginx k3s docker && nginx -t"
```

Expected: Amnezia containers are present, nginx/k3s/docker are active, nginx syntax is successful.

Check public port hardening:

```bash
nc -vz -w 5 89.124.113.223 18443
nc -vz -w 5 89.124.113.223 6443
nc -vz -w 5 89.124.113.223 10250
nc -vz -w 5 89.124.113.223 9100
```

Expected: `18443` succeeds; `6443` and `10250` time out; `9100` is refused or timed out.

Known incomplete item after first bootstrap: ArgoCD root app stays `Unknown` until `https://github.com/mednov-ai/playsay-infra.git` exists, contains the pushed infra repository, and ArgoCD can read it.

## GitHub and Jenkins Credentials

Never paste GitHub tokens into chat, commits, shell history, or documentation. If a token is exposed, revoke it in GitHub immediately and create a new one.

Create these GitHub items before configuring Jenkins:

1. GitHub organization or account namespace: `mednov-ai`.
2. Repositories:
   - `playsay-platform`
   - `playsay-infra`
3. Push local folders to those repositories.
Create a GitHub token for Jenkins. The simplest MVP option is one fine-grained token with access to `playsay-platform` and `playsay-infra`:

- Repository contents: read/write
- Pull requests: read
- Metadata: read
- Webhooks: read/write if Jenkins should create webhooks automatically
- Packages: read/write for GHCR

In Jenkins, create credentials:

- `github-ghcr`: username/password credential. Username is your GitHub username or org bot user; password is the GitHub token with package write access.
- `github-infra-token`: username/password credential. Username is your GitHub username or org bot user; password is the GitHub token that can push commits and tags to `playsay-infra` and create tags in `playsay-platform`.

You may use one token for both credentials at MVP stage. Later, split them into narrower tokens.

Create credentials in Jenkins UI:

1. Open `https://ops.play-and-say.ru:18443/jenkins/`.
2. Go to `Manage Jenkins` -> `Credentials` -> `System` -> `Global credentials`.
3. Add `Username with password`.
4. For `ID`, enter `github-ghcr`; username is your GitHub username, password is the GitHub token.
5. Add the second `Username with password` credential with ID `github-infra-token`.

Do not store the token in `playsay-infra` or `playsay-platform`.

If you prefer CLI later, pass secrets only through a local untracked file such as `.env.local` or an interactive prompt.

## Shared External Activity Acceptance And Production Promotion

The web pipeline exports `VITE_EXTERNAL_ACTIVITY_ENABLED=true` for deployable dev builds and fixed-width numeric production releases. `scripts/ci/validate-ci-contracts.sh` verifies both branches of `Jenkinsfile.web-app`; a production release that omits the flag is not eligible for promotion. A deliberately disabled rollback build remains supported and must show the explicit unavailable state.

The required unpacked dev extension is version `0.1.7` or later. It allows `dev.online.honey.school`, `online.honey.school`, and `online.honeyschool.ru`, includes its package version in the version-1 `AWAITING_ACTION` acknowledgement, and temporarily uses the Chrome Debugger permission during an active activity to deliver trusted pointer, wheel, and keyboard input to canvas/iframe providers. Version 0.1.6 may capture and scroll but is not dev-acceptance eligible because provider actions can ignore its synthetic input; the web must show `EXTENSION_UPDATE_REQUIRED` before capture. Regenerate the ZIP and installation guide and confirm `0.1.7` on `chrome://extensions` before distribution. Every later shipped extension source, manifest behavior/permission, runtime bundle, or user-facing asset change requires another patch increment.

Before accepting a dev build, run the focused web/extension tests, localization integrity suite, production-mode build, and browser matrix on `https://dev.online.honey.school/` with one teacher and at least one student: student-first launch before teacher connection, outdated-extension rejection, successful acknowledgement/capture, real provider input, missing or disabled extension, closed provider tab, Retry with a new session, Return to lesson, and an immediate stop/relaunch. An authoritative teacher stop must clear an unowned student `REQUESTED` state even when its session id differs; an old host stop must not erase a replacement host session. A matching named video track from the trusted teacher must recover `ACTIVE` if a lifecycle packet is missed, and the student must show a localized connecting state until the track attaches. Participant pointer, keyboard and coalesced wheel input must use the collaboration fast lane without a shadow duplicate while the socket is available and fall back to LiveKit data when it is not. The student must return to ordinary material without a black video surface and follow the replacement session.

After dev acceptance and separate production-release authorization, create the next fixed-width numeric platform branch and let the release dispatcher produce the matching reviewed infra candidate. Confirm `argocd-apps/prod/release-candidate.yaml` is `ready`, the web-app digest is immutable, the candidate source commit is the reviewed platform HEAD, and the production web build contract passed. Jenkins must not receive a production kubeconfig and must not sync the cluster.

After separate promotion authorization and the normal backup/migration gate, promote only that ready GitOps candidate. Canary extension 0.1.7 on both `https://online.honeyschool.ru/` and `https://online.honey.school/`: verify versioned acknowledgement, capture, a responsive Wordwall action from teacher and unlocked student input, one actionable negative path, Retry with a new session, Return to lesson, and immediate relaunch without a black participant surface. Stop promotion acceptance if either origin fails.

Collect only extension version, web build identity, timestamps, lifecycle phase, and the stable codes `FEATURE_UNAVAILABLE`, `EXTENSION_NOT_DETECTED`, `EXTENSION_UPDATE_REQUIRED`, `TARGET_TAB_CLOSED`, `CAPTURE_PERMISSION_DENIED`, `CAPTURE_NOT_SUPPORTED`, `CAPTURE_START_FAILED`, or `EXTENSION_ERROR_UNKNOWN`. Never record provider page content, raw Chrome errors, target tab/stream ids, session nonce, participant input, cookies, credentials, or learner data.

Rollback is web-only: restore the previous web image or produce an explicitly disabled web build through the reviewed GitOps path, then verify the normal classroom on the affected origin. Do not roll back backend/data, change extension permissions, use direct `kubectl apply`, or modify the protected legacy contour. Extension 0.1.7 remains compatible with the disabled web release.

## Vocabulary Practice Internal Callbacks

Personal vocabulary practice uses retryable service-to-service callbacks; there is no distributed transaction between assignments, vocabulary, and Key.

- `api-gateway` calls `vocabulary-service` through `PLAYSAY_VOCABULARY_SERVICE_BASE_URL`.
- `vocabulary-service` reports assignment progress through `PLAYSAY_API_GATEWAY_SERVICE_BASE_URL`.
- `keyboard-service` reports session-specific spelling results through `PLAYSAY_VOCABULARY_SERVICE_BASE_URL`.
- All internal endpoints require the existing `X-PlaySay-Service-Token`; never expose or print it.
- Dev chart values use namespace-qualified `*.playsay-dev.svc.cluster.local` addresses and prod values use `*.playsay-prod.svc.cluster.local`. Do not route these callbacks through public nginx.
- Assignment preparation, assignment progress, and Key results are durable outbox operations. A temporary peer outage should leave retryable rows and must not create duplicate sessions or attempts after recovery.

The dev web build enables `VITE_VOCABULARY_PRACTICE_ENABLED`, `VITE_VOCABULARY_HOMEWORK_ENABLED`, `VITE_VOCABULARY_LIVE_ENABLED`, `VITE_VOCABULARY_KEY_ENABLED`, and the composer/rail cutover flag `VITE_PERSONAL_PRACTICE_V2_ENABLED`. The web pipeline also sets `VITE_KEYBOARD_ORIGIN=https://dev.key.honey.school` for dev and `VITE_KEYBOARD_ORIGIN=https://key.honey.school` for production; do not replace these with a source-code hardcode. Production keeps the V2 cutover disabled for the first compatible backend release. UI rollback changes only the cutover/build flags or restores the previous web image; do not roll back or delete the compatible Liquibase tables.

Adaptive vocabulary uses backend controls `PLAYSAY_VOCABULARY_COMPOSER_ENABLED`, `PLAYSAY_VOCABULARY_ADAPTIVE_POLICY_ENABLED`, `PLAYSAY_VOCABULARY_DELIVERY_POLICIES_ENABLED`, `PLAYSAY_VOCABULARY_KEY_NGRAMS_ENABLED`, `PLAYSAY_VOCABULARY_GENERATED_MEDIA_ENABLED`, and `PLAYSAY_VOCABULARY_LEXICAL_BACKFILL_ENABLED`, with matching dev web build flags and `VITE_VOCABULARY_TYPED_TARGETS_ENABLED` in Honey School Key. AX41 dev enables this complete set for acceptance; production defaults remain disabled. Rollback disables new launches and generation first, while additive tables, accepted evidence, approved assets, and immutable active snapshots remain readable.

Generated vocabulary images use the vocabulary-service-owned `vocabulary-media/` prefix and the dedicated `playsay-vocabulary-media` bucket. Dev uses MinIO at `http://minio.storage.svc.cluster.local:9000`, credentials from `playsay-object-storage`, and may create the missing dedicated bucket. The image generator uses `playsay-openai/api-key` through `PLAYSAY_VOCABULARY_MEDIA_API_KEY`; never copy either secret value into Helm, logs, evidence, or chat. Production must provision and review its bucket, Secret references, moderation role, and retention policy before enabling generation, and must keep automatic bucket creation disabled.

Operator-safe endpoints `GET /internal/vocabulary/diagnostics` and `POST /internal/vocabulary/reconcile` report or retry stale projections, assignment callbacks, stuck generation, and bounded missing-object checks. The corresponding Key endpoints are `GET /internal/keyboard/vocabulary/diagnostics` and `POST /internal/keyboard/vocabulary/reconcile`. They require `X-PlaySay-Service-Token`, fail closed when it is absent, and must be inspected only through counts, ages, and sanitized error codes—never answer, example, prompt, subject, object-key, or callback payload columns.

Roll out Personal Practice V2 in this order:

1. Deploy `vocabulary-service` migrations/backend and compatible `api-gateway`; verify practice-plan tables and internal callback health.
2. Deploy `web-app` with `VITE_PERSONAL_PRACTICE_V2_ENABLED=true` in dev, then `keyboard-app`/`keyboard-service`.
3. Verify preview `planId + revision` publication, one live run per lesson, presence-aware recipients, reconnect recovery, homework progress, and the exact Key session set.
4. If the UI must be rolled back, disable the V2 build flag or restore the previous web image. Keep plan/item-v2 columns in place so in-flight sessions remain readable.
5. For adaptive acceptance, verify one real first-use generation, teacher/admin candidate review, approval, learner delivery, regeneration without replacing the approved revision, and text-only behavior during generator or object-store failure.

After rollout, verify without printing payloads:

```bash
KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n playsay-dev get deploy \
  api-gateway vocabulary-service keyboard-service web-app
KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n playsay-dev rollout status deploy/vocabulary-service --timeout=5m
KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n playsay-dev rollout status deploy/keyboard-service --timeout=5m
KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n playsay-dev rollout status deploy/api-gateway --timeout=5m
KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n playsay-dev rollout status deploy/web-app --timeout=5m
```

If callbacks accumulate, inspect only row counts, retry timestamps, and sanitized error classes. Do not select vocabulary snapshot, answer, or outbox payload columns into terminal output.

## Jenkins Branch Builds and Build Labels

Jenkins platform jobs are configured by:

```bash
./scripts/configure-jenkins-jobs.sh
```

The bootstrap/add-ons script runs it automatically after Jenkins is installed. The configured jobs are:

- `playsay-platform-dispatch-webhook`: the only Generic Webhook Trigger receiver; validates `develop` or numeric release payloads and asynchronously invokes exactly one internal dispatcher;
- `playsay-platform-dispatch-develop`: internal develop dispatcher; a newer develop push aborts the older dispatcher;
- `playsay-platform-dispatch-release`: internal numeric release dispatcher; release candidates are serialized independently of develop;
- `playsay-platform-develop`: manual full dev rebuild compatibility job; it rejects release branches and the dispatcher does not call it;
- `playsay-api-gateway-develop`: tests/packages `api-gateway`, checks OpenAPI, builds/pushes the image, then routes its reference to dev or the matching production release;
- `playsay-ai-tutor-service-develop`: tests/packages `ai-tutor-service`, builds/pushes its image, then routes its reference to dev or the matching production release;
- `playsay-vocabulary-service-develop`: tests/packages `vocabulary-service`, builds/pushes its image, then routes its reference to dev or the matching production release;
- `playsay-game-adapter-service-develop`: tests/builds the public `@playsay/game-sync` package and stateless `game-adapter-service`, builds/pushes its image, then routes its reference to dev or the matching production release;
- `playsay-web-app-develop`: generates the API client, lints/tests/builds `web-app`, tests/packages `browser-extension` and archives `frontend/browser-extension/playsay-browser-extension.zip`, builds/pushes its image, then routes its reference to dev or the matching production release;
- `playsay-collaboration-service-develop`: tests/builds `collaboration-service`, builds/pushes its image, then routes its reference to dev or the matching production release;
- `playsay-media-service-develop`: tests/packages `media-service`, builds/pushes its image, then routes its reference to dev or the matching production release;
- `playsay-payment-service-develop`: tests/packages `payment-service`, builds/pushes its image, then routes its reference to dev or the matching production release;
- `playsay-registration-service-develop`: tests/packages `registration-service`, builds/pushes its image, then routes its reference to dev or the matching production release;
- `playsay-email-service-develop`: tests/packages `email-service`, builds/pushes its image, then routes its reference to dev or the matching production release;
- `playsay-keycloak-develop`: tests/packages the lesson Authenticator SPI, builds the pinned optimized custom Keycloak image, records its immutable digest, then routes its reference to dev or the matching production release;
- `playsay-keyboard-backend-develop`: downstream keyboard backend job;
- `playsay-keyboard-frontend-develop`: downstream keyboard frontend job.

Both dispatchers have `BRANCH_NAME`, `GITHUB_BEFORE`, `GITHUB_AFTER`, optional `FORCE_TARGETS=all|target1,target2`, and `MAX_PARALLEL_MODULE_JOBS` in the range `1..4` with default `4`. Their analysis stage uses a small temporary agent for affected-target detection and validation, then releases it before downstream work. Affected module jobs run in bounded batches of at most four; Kubernetes cloud `containerCap=4` and `instanceCap=4` enforce the same ceiling. Module jobs are manual/dispatcher-only and do not have GitHub webhook triggers. All module jobs checkout `GITHUB_AFTER` when it is provided, so they build the same source commit the dispatcher analyzed. Immediately before a deployable GitOps update, every module job runs `scripts/ci/assert-current-branch-head.sh`; if a newer push moved the branch, the stale build exits without changing infra. `playsay-platform-develop` stays available as a manual dev-only full rebuild safety valve with `AFFECTED_TARGETS=all`, but it is no longer part of automatic dispatch and rejects `release/*`.

Parallel module jobs may update different chart files on `playsay-infra/develop` at the same time. A rejected non-fast-forward GitOps push is expected in that race: `scripts/ci/update-environment-image.sh` must return to its stable workspace, remove the stale temporary clone, clone the latest infra branch again, reapply only the owned chart update, and retry up to five times. Do not interpret the first rejected push as a missing `develop` branch, and do not serialize the dispatcher merely to avoid this recoverable Git race.

Module jobs have a `BRANCH_NAME` parameter and module-specific build label prefixes:

- `api-gateway`: `api-dev-N` on `develop`;
- `web-app`: `web-dev-N`;
- `collaboration-service`: `collab-dev-N`;
- `game-adapter-service`: `game-adapter-dev-N`;
- `media-service`: `media-dev-N`;
- `payment-service`: `payment-dev-N`;
- `registration-service`: `registration-dev-N`;
- `email-service`: `email-dev-N`;
- `keyboard-service`: `key-backend-dev-N`;
- `keyboard-app`: `key-frontend-dev-N`.

Non-`develop` labels prefix the branch with the module name, for example `web-feature-task-1-N` or `api-rel-1.001.00-N`, sanitized for Docker/Git/Kubernetes label safety.

Deployable dev branches are `develop`, `codex/*`, `feature/*`, and `hotfix/*`. Strict numeric `release/<number>.<number>.<number>` branches publish images and matching `values-prod.yaml` digests only; they never update dev, run dev migrations, or use the dev kubeconfig for rollout. Other branches run build/test stages but skip image publishing, source tagging, and GitOps updates.

The shared Generic Webhook Trigger token belongs only to `playsay-platform-dispatch-webhook`. Its single filter accepts `refs/heads/develop` or numeric `refs/heads/release/<number>.<number>.<number>`, extracts `ref` into `BRANCH_NAME`, reads GitHub `before`/`after`, rejects `refs/tags/*`, and ignores branch deletion events where `after` is forty zeroes. The router asynchronously forwards all parameters to exactly one internal job; the internal develop/release dispatchers have no webhook triggers. This avoids one delivery being interpreted against two jobs or two parameter defaults. The selected dispatcher runs `scripts/ci/detect-affected-targets.mjs`, executes requested validation suites, starts only the needed downstream jobs in bounded batches of up to four, waits for all results, and fails if any validation or downstream job fails. A supersede interruption must escape the downstream build step immediately; it is never converted into a normal module failure and must not start another batch.

Affected-target policy:

- `frontend/keyboard-app/**` -> `playsay-keyboard-frontend-develop`;
- `backend/keyboard-service/**` -> `playsay-keyboard-backend-develop`;
- `frontend/web-app/**` -> `playsay-web-app-develop`;
- `frontend/game-adapter-service/**` -> `playsay-game-adapter-service-develop`;
- `frontend/game-sync-sdk/**` -> `playsay-game-adapter-service-develop` and `playsay-web-app-develop`;
- `frontend/browser-extension/**` -> `playsay-web-app-develop`;
- `backend/api-gateway/**` -> `playsay-api-gateway-develop`;
- `contracts/openapi.yaml` -> `playsay-api-gateway-develop` and `playsay-web-app-develop`;
- `backend/ai-tutor-service/**` -> `playsay-ai-tutor-service-develop`;
- `contracts/ai-tutor-openapi.yaml` -> `playsay-ai-tutor-service-develop` and `playsay-web-app-develop`;
- `backend/vocabulary-service/**` -> `playsay-vocabulary-service-develop`;
- `contracts/vocabulary-openapi.yaml` -> `playsay-vocabulary-service-develop`, `playsay-web-app-develop`, and `playsay-keyboard-frontend-develop`;
- `contracts/registration-openapi.yaml` -> `playsay-registration-service-develop` and `playsay-web-app-develop`;
- `backend/media-service/**` -> `playsay-media-service-develop`;
- `backend/payment-service/**` -> `playsay-payment-service-develop`;
- `backend/registration-service/**` -> `playsay-registration-service-develop`;
- `backend/email-service/**` -> `playsay-email-service-develop`;
- `backend/keycloak-lesson-authenticator/**` -> `playsay-keycloak-develop`;
- `collaboration-service/**` -> `playsay-collaboration-service-develop`;
- shared backend config/code -> all backend targets including `keyboard-service`;
- shared frontend config/lockfile -> `web-app`, `game-adapter-service`, and `keyboard-app`;
- the matching module `Jenkinsfile.*` -> only that module;
- dispatcher/common CI files -> `ci-contracts` validation without product image builds;
- smoke scripts -> `smoke-syntax` validation without product image builds;
- unknown source paths or invalid/unavailable Git ranges -> fail before downstream work and require an explicit routing rule or operator `FORCE_TARGETS`;
- docs-only Markdown/docs/spec changes -> no downstream jobs.

For the first push of a numeric release, GitHub sends a zero `before`. The detector resolves `argocd-apps/prod/current-release.txt` from infra `develop`, fetches the matching platform release branch, and compares its tree with the new release HEAD without requiring the two histories to be ancestors. If that production baseline cannot be resolved, the release stops unless an operator intentionally supplies `FORCE_TARGETS`.

Before release module jobs, Jenkins creates or resumes the matching infra release branch and writes `argocd-apps/prod/release-candidate.yaml` with `status: building`. A new branch starts from current infra `develop`, overlays running production `image`/`build` metadata from `current-release.txt`, and rewrites all prod ArgoCD `targetRevision` values to the new branch. Retries retain all previously affected targets. After every affected module succeeds, the finalizer verifies the platform branch HEAD, affected `build.commit` and immutable digests, unchanged image/build metadata for unaffected charts, every prod target revision, and `helm template` output before changing the manifest to `status: ready`. Jenkins never receives a prod kubeconfig, never changes `current-release.txt`, and never syncs production; promotion remains a separate reviewed operator action with the migration gate.

Trigger `codex/*`, `feature/*`, and `hotfix/*` branches manually through the required module jobs with explicit `BRANCH_NAME`, `GITHUB_BEFORE`, and `GITHUB_AFTER`; neither webhook dispatcher accepts topic branches. `MAX_PARALLEL_MODULE_JOBS` may be set from `1` through `4`; use `1` or `2` as the immediate rollback if four-agent resource gates fail. The global four-agent Kubernetes cloud cap still applies.

The build label is written to:

- Jenkins build display name;
- GHCR image tags for affected images: `playsay-api-gateway`, `playsay-web-app`, `playsay-collaboration-service`, `playsay-media-service`, `playsay-payment-service`, `playsay-registration-service`, `playsay-email-service`, `playsay-keyboard-service`, and `playsay-keyboard-app`;
- Git tags in `playsay-platform` and `playsay-infra`;
- Helm `values-dev.yaml` build metadata;
- Kubernetes pod labels and annotations under `playsay.io/*`.

Build labels are immutable commit identities. Before enabling a migrated/restored module job, find the historical maximum for its prefix (for example `web-dev-*`) in both `playsay-platform` Git tags and GHCR, then set that Jenkins job's `nextBuildNumber` strictly above the maximum. Do not retry a collision with the same number. `scripts/ci/tag-source-commit.sh` now resolves an existing annotated/lightweight tag and succeeds only when it points to the requested `GIT_COMMIT`; a different commit fails the build with `Source tag collision`.

Every Kaniko module build must leave a valid `image-digest.txt`. Both dev and numeric release GitOps updates validate `sha256:<64 hex>` and write `.image.digest` together with `.image.tag` and `.build.*`; the rendered Deployment must therefore use `repository@sha256`, while the tag is traceability metadata. After rollout, verify the values commit, ArgoCD revision, pod image ID and source commit agree:

```bash
git -C playsay-infra show origin/develop:helm-charts/web-app/values-dev.yaml | yq '.image, .build'
kubectl -n playsay-dev get deploy web-app -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
kubectl -n playsay-dev get pod -l app.kubernetes.io/name=web-app -o jsonpath='{.items[0].status.containerStatuses[0].imageID}{"\n"}'
```

Check what is deployed:

```bash
kubectl -n playsay-dev get pods --show-labels
kubectl -n playsay-dev get pod -l app.kubernetes.io/name=api-gateway -o jsonpath='{.items[0].metadata.annotations}'
```

Backend service image builds are intentionally runtime-only. Each backend module job runs only its own `:service:test` and `:service:bootJar`, then Kaniko builds the matching runtime Dockerfile by copying the already-built jar from that module's `build/libs`. Because these Kaniko builds use `backend/` as the Docker context, `backend/.dockerignore` must re-include every backend image's `build/libs/*.jar` path; otherwise an image can build and push without `/app/app.jar`. Only `playsay-media-service` adds the standalone `yt-dlp_linux` release asset to `/usr/local/bin/yt-dlp` and copies `/ffmpeg` from the pinned `mwader/static-ffmpeg:7.1.1` image into `/usr/local/bin/ffmpeg`; do not reintroduce `apt-get update`, Python installation, or a Gradle build stage unless the pipeline is redesigned.

Frontend image builds are intentionally runtime-only too. `playsay-web-app-develop` runs `npm --workspace web-app run generate/lint/test/build`, then Kaniko builds `frontend/web-app/Dockerfile` by copying the already-built `web-app/dist` into nginx. `playsay-keyboard-frontend-develop` does the same for `keyboard-app`. Do not add `npm install`, `npm ci`, or `npm run build` back into frontend Dockerfiles unless the pipeline is redesigned.

The `playsay-web-app-develop` Node container sets `NODE_OPTIONS=--max-old-space-size=1024` inside its `1536Mi` memory limit and requests `768Mi`. The Vite production bundle uses about `878Mi` Node heap plus `esbuild`/native overhead, so `1Gi` cgroup memory is insufficient. Keep this individual Node build capped at one CPU; global module parallelism is separately bounded to four agents on dedicated CI.

The `playsay-api-gateway-develop` Gradle container caps its daemon with `-Xmx384m -XX:MaxMetaspaceSize=256m` and uses a `2Gi` container limit. Its test stage passes `-PlowMemoryTests`, which keeps one test fork, uses a `512m` test heap and restarts the worker after every 8 classes so Spring/H2 context caches are released. Do not raise the container back to `3Gi` on the single-node VPS: an uncapped API test/package run can drive available host memory below 200Mi and cause cluster-wide swap thrash. Keep `--max-workers=1` and pass `-Pkotlin.compiler.execution.strategy=in-process`; the `-D` system-property form is not consumed by the Kotlin Gradle Plugin and starts a separate compiler daemon that can exhaust the dev node.

The `playsay-ai-tutor-service-develop` Gradle container follows the same bounded pattern: request `384Mi`, limit `1536Mi`, daemon `-Xmx384m / MaxMetaspaceSize=192m`, one `384m` test fork, `--max-workers=1`, and `-Pkotlin.compiler.execution.strategy=in-process`. Build `ai-tutor-dev-8` was aborted on 2026-07-13 after the former `3Gi`/`-D` configuration drove host load to about `15`, available memory below `500Mi`, and swap above `1.7Gi`. Keep each AI Tutor build single-worker and do not restore the unbounded compiler daemon; it may run beside other bounded module jobs only on dedicated CI.

Jenkins Kubernetes cloud permits at most four agent pods, enables orphan pod garbage collection with a 300-second timeout, and limits each injected `jnlp` container to `50m/128Mi` request and `300m/384Mi` limit. Module pods have `activeDeadlineSeconds=2400`, a 30-minute pipeline timeout, explicit resources for build/tools containers, and one-CPU Gradle/Node limits. Backend Gradle stages use `ActiveProcessorCount=1`, `--max-workers=1`, and the Kotlin compiler in-process. Gradle containers may share the `jenkins-agent-cache` PVC, but each Gradle-based pipeline must mount a job-specific subPath. Rollout waiting stays centralized in `scripts/ci/wait-for-argocd-rollout.sh` through the scoped `dev-kubeconfig` credential. Four-agent batches are expected to saturate the CI VM's four vCPUs; CPU saturation alone is not a rollback signal while host/prod health and CI memory remain healthy.

After Sprint 2 app PostgreSQL was added, Jenkins `dev-25` failed in `Backend tests` because Maven Central DNS resolution temporarily failed while the node was overloaded. During Sprint 4, Jenkins `dev-53` was `OOMKilled`. On 2026-06-27, parallel module builds caused OOMs and public outages. On 2026-07-16, even serialized API builds proved unsafe at the grown idle baseline: `api-dev-44` ran for 63 minutes, repeatedly lost its agent and ended with exit `137`; observed load1 reached `142.98`. The retry reached `MemAvailable=1.86%`, swap `1883Mi`, CPU about `100%`, I/O wait `57.97%`, and NodeNotReady.

AX41 Jenkins runs on the dedicated `playsay-ci` VM. The former shared-node capacity manager, watchdog, `capacity-guard` sidecars, state ConfigMap and Lease are removed and must not be recreated on dev, prod or CI. CI never scales product Deployments to obtain build capacity; the historical overload incidents above are retained only as the reason Jenkins was isolated.

Jenkins chart must keep `controller.overwritePlugins=true`. In chart `jenkins-5.9.22`, the rendered `apply_config.sh` can still contain interactive `yes n | cp -i ...` plugin copying; after a controller restart this can leave the init container in `CrashLoopBackOff` and Jenkins will serve `502` through host nginx because the service has no ready endpoints. `deploy-cluster-addons.sh` patches the Jenkins ConfigMap to use non-interactive `cp -f ...` after Helm upgrade and deletes `jenkins-0` only if it is already stuck in init `CrashLoopBackOff`. If `/jenkins/` returns `502` after a VPS reboot, check `kubectl -n jenkins get pod,endpoints` first; healthy Jenkins should be `2/2 Running`, have an endpoint, and return `403 Forbidden` or a login redirect through nginx.

Jenkins UI is configured through Helm and JCasC with root URL `https://jenkins.honey.school/`. It runs on dedicated `playsay-ci` and is exposed by AX41 edge nginx only to WireGuard `10.250.0.0/24`; public requests receive 403. The root-host proxy forwards `Host`, `X-Forwarded-Host`, `X-Forwarded-Port` and `X-Forwarded-Proto`; it must not set the old `/jenkins` prefix.

The `OpenAPI contract` check lives in `playsay-api-gateway-develop`. Test, `bootJar`, and `:api-gateway:exportOpenApi` run in one Gradle invocation; the following stage only verifies the committed file and archives it. Internal `backend/api-gateway/**` changes trigger API only. A commit that changes `contracts/openapi.yaml` triggers API plus web-app, so frontend generation follows actual contract changes instead of every gateway implementation edit.

The app DB migrate stages live in the module jobs. Jenkins itself does not mount DB Secrets. Through the scoped dev kubeconfig it creates a short-lived `playsay-migrate-*` Job and `playsay-migration-*` ConfigMap in `playsay-dev`; only that Job may read an approved dev DB Secret. Admission policy fixes Liquibase `5.0.3`, PostgreSQL JDBC `42.7.8`, command, volumes, security context and allowed Secret keys. The Job has no service-account token, is time-bounded, and is deleted with its ConfigMap after completion. Changelog-aware modules skip only when `GITHUB_BEFORE..GITHUB_AFTER` proves no change; vocabulary still runs idempotent migration for every deployable build. Keep service startup Liquibase disabled.

The JPA services `api-gateway`, `payment-service`, `registration-service`, and `email-service` keep `logging.level.org.hibernate.orm.connections.pooling=warn` so normal startup logs do not print Hibernate's database-info block with the secret-bearing JDBC URI. Do not lower this logger to `info` while `PLAYSAY_DB_JDBC_URL` contains credentials.

The dev `api-gateway`, `media-service`, `payment-service`, `registration-service`, and `email-service` charts give Spring Boot memory headroom while keeping CPU scheduling pressure low on the single-node dev VPS: `api-gateway` requests `50m / 384Mi`, `media-service` requests `50m / 256Mi`, `registration-service` uses the aggressive dev profile `25m / 96Mi` requests, `500m / 384Mi` limits, and `JAVA_TOOL_OPTIONS` with `InitialRAMPercentage=25` plus `MaxRAMPercentage=55`. Lower-priority `payment-service` and `email-service` are tighter: `25m / 64Mi` requests, `500m / 320Mi` limits, and `JAVA_TOOL_OPTIONS` with `InitialRAMPercentage=15`, `MaxRAMPercentage=45`, `MaxMetaspaceSize=128m`, `ReservedCodeCacheSize=32m`, and `ActiveProcessorCount=1`. If any low-priority service is `OOMKilled`, raise only that service to `128Mi` request and `512Mi` limit before deeper investigation. Dev `api-gateway` sets `SPRING_DATASOURCE_HIKARI_MAXIMUM_POOL_SIZE=8` so concurrent UI/WebSocket smoke traffic cannot exhaust a three-connection pool; the other dev JPA services plus `keyboard-service` remain at `3`. App PostgreSQL has `max_connections=50`; the observed baseline before this exception was 22 client/admin sessions, so the API increase still leaves at least 23 connections for Jenkins Liquibase migrations and ad-hoc diagnostics. Their dev strategy is `RollingUpdate` with `maxSurge=0/maxUnavailable=1`, accepting a short backend replacement window in dev to avoid a Jenkins `Wait for dev rollout` deadlock where the agent pod waits for a rollout that cannot schedule until the agent exits; re-check node memory/swap and PostgreSQL connection counts after Jenkins builds before raising the limits further. CloudNativePG keeps the same `50m/128Mi` requests and `500m/384Mi` limits, but its explicit liveness/readiness probes use 5-second timeouts and six failures at a 10-second period; `stopDelay=300` with `smartShutdownTimeout=60` prevents a transient Jenkins load spike from killing PostgreSQL after only three probe misses and prevents a failed smart shutdown from blocking recovery for the default 30 minutes.

The `Sprint 5 UI smoke` and `Sprint 6 Homework smoke` stages now live in `playsay-web-app-develop` after `web-app` rollout and the explicit runtime-capacity restore/readiness gate. They use `scripts/ci/run-ui-smoke.sh`, `mcr.microsoft.com/playwright:v1.56.1-noble`, install only the matching `playwright` Node package into `/tmp/playsay-ui-smoke`, reuse the browser binaries already in the image, and run `scripts/smoke/sprint5-ui-smoke.mjs` plus `scripts/smoke/sprint6-homework-smoke.mjs` against `https://online.play-and-say.ru`. Before workspace navigation both smoke suites dismiss the optional first-login passkey prompt through its stable `data-testid`, so the modal cannot intercept the workspace-switcher click. The classroom flow enters through `[data-testid='classroom-prejoin-join']`; when headless media checks remain incomplete, it accepts the explicit second-click warning before waiting for the live material surface, including after the classroom reload used by the reconnect check. The stages read only the required demo passwords from the `keycloak-dev-users` secret in the `jenkins` namespace and set `PLAY_SAY_SMOKE_FETCH_PASSWORDS=false`, so Jenkins never SSHes to the VPS or prints secret values. Keyboard frontend keeps its own browser smoke against `https://key.play-and-say.ru`.

The current critical-lesson smoke contract uses two isolated teacher/student browser contexts. Assignment and homework list changes must arrive without reload within 2 seconds; free-writing must preserve Latin/Cyrillic/paste/composition drafts across the 1-second autosave and reload. Shared material scroll, page and `image-focus` open/close/scroll must converge within 300 ms and 2% normalized offset without a feedback loop. Text must start top-left, remain visible over light/dark images, keep a manually dragged bottom edge after blur/reconnect, and merge simultaneous Y.Text edits. HTML-game form controls must work from either context. Screen-share manual verification must cover start, explicit stop, browser stop and double-click: no local `ScreenShare`/`ScreenShareAudio` publication may remain and the material workspace must return. Never choose the lesson tab in the browser picker.

The Sprint 6 homework/progress smoke creates a temporary published private material, creates standalone group homework for `student-demo` + `student-demo-2`, creates a single-student homework, verifies teacher UI due date/instructions and `0/N scored` without an initial `10/10`, verifies the single-student assignment has no group indicator, submits wrong answers as one student and correct answers as the other, verifies teacher group progress uses score/errors rather than status labels, resubmits improved answers, then creates homework from a completed lesson and confirms the completed live lesson is not joinable while the homework remains visible. The smoke pins demo profile `locale=en` before UI assertions and opens the compact workspace switcher through `data-testid="workspace-switcher-trigger"` before selecting a role-available `data-tab-id`; it does not depend on localized tab labels or assume that collapsed section cards are mounted. If `GET /api/assignments` returns `MATERIAL_NOT_FOUND`, check for active homework rows whose material was archived during prior smoke cleanup; current `api-gateway` must skip those rows in list endpoints so one stale assignment cannot break the teacher/student homework panels. Detail endpoints for such assignments may still return `404`.

Create the dev image pull secret after the first GHCR token is available:

```bash
read -r -p "GitHub username: " GITHUB_USERNAME
read -r -s -p "GitHub token: " GITHUB_TOKEN
echo
kubectl create namespace playsay-dev --dry-run=client -o yaml | kubectl apply -f -
kubectl -n playsay-dev create secret docker-registry ghcr-pull-secret \
  --docker-server=ghcr.io \
  --docker-username="$GITHUB_USERNAME" \
  --docker-password="$GITHUB_TOKEN" \
  --docker-email=dev@play-and-say.ru \
  --dry-run=client -o yaml | kubectl apply -f -
unset GITHUB_TOKEN
```


Current GitHub webhook for `playsay-platform` after the AX41 cutover:

- Payload URL: `https://hooks.honey.school/generic-webhook-trigger/invoke?token=<secret>`
- Content type: `application/json`
- Events: push
- GitHub hook id: `632315512`
- Status: `playsay-platform-dispatch-webhook` is the sole token-owning receiver and routes each accepted delivery to exactly one triggerless internal job, `playsay-platform-dispatch-develop` or `playsay-platform-dispatch-release`. Its filter is `^refs/heads/(develop|release/[0-9]+\.[0-9]+\.[0-9]+) (?!0{40}$)[0-9a-f]{40}$` over `$GITHUB_REF $GITHUB_AFTER`; deletion/tag/topic/free-form release events are rejected before routing.
- Secret: stored in Jenkins credential `github-webhook-token` and Kubernetes secret `playsay-jenkins-credentials:webhook-token`; the value is URL-encoded in GitHub and is never written to Git or evidence.
- Verification: GitHub ping delivery returned HTTP 200 on 2026-07-21.

Current GitHub webhook for `playsay-infra` -> ArgoCD refresh:

- Payload URL: `https://hooks.honey.school/argocd/api/webhook`
- Content type: `application/json`
- Events: push
- GitHub hook id: `636710711`
- Verification: GitHub ping delivery returned HTTP 200 on 2026-07-21.
- Secret: stored only in Kubernetes as `argocd/argocd-secret` key `webhook.github.secret`. Create or refresh it without printing the value:

```bash
./scripts/configure-argocd-webhook-secret.sh
```

When you are entering the GitHub webhook secret, read the value locally and do not paste it into chat, commits, shell history, or logs:

```bash
kubectl -n argocd get secret argocd-secret -o jsonpath='{.data.webhook\.github\.secret}' | base64 -d
```

Use the decoded value only in the GitHub webhook UI/API for `mednov-ai/playsay-infra`. This webhook wakes ArgoCD after Jenkins pushes a `values-dev.yaml` deploy commit, so module jobs normally use `ARGOCD_REFRESH_MODE=webhook`. Use `ARGOCD_REFRESH_MODE=annotate` only as a manual recovery path if the GitHub webhook is broken.

Jenkins URL:

```text
https://jenkins.honey.school/
```

Jenkins API checks require authentication. Connect to `playsay-ci` through the AX41 jump host, keep credentials in remote shell variables, and use the local NodePort so neither value is printed:

```bash
ssh -i /Users/evgeniymednov/.ssh/play_and_say_vps_ed25519 \
  -o IdentitiesOnly=yes \
  -o 'ProxyCommand=ssh -i /Users/evgeniymednov/.ssh/play_and_say_vps_ed25519 -o IdentitiesOnly=yes -W %h:%p root@65.109.55.110' \
  playsay@10.60.0.40 '
set -euo pipefail
JENKINS_URL="http://127.0.0.1:32082"
JENKINS_JOB_NAME="playsay-platform-dispatch-develop"
JENKINS_USER="$(sudo kubectl -n jenkins get secret jenkins -o jsonpath="{.data.jenkins-admin-user}" | base64 -d)"
JENKINS_PASSWORD="$(sudo kubectl -n jenkins get secret jenkins -o jsonpath="{.data.jenkins-admin-password}" | base64 -d)"
curl -g -fsS -u "$JENKINS_USER:$JENKINS_PASSWORD" \
  "$JENKINS_URL/job/$JENKINS_JOB_NAME/api/json?tree=builds[number,displayName,building,result,timestamp,url]{0,10}" |
  jq -r ".builds[] | \"#\\(.number) \\(.displayName) building=\\(.building) result=\\(.result)\""
unset JENKINS_USER JENKINS_PASSWORD
'
```

The current agent SSH route is the explicit key, AX41 jump host and `playsay@10.60.0.40` command above. Current dev Kubernetes diagnostics use the same jump host with destination `playsay@10.60.0.30`. The old `146.103.126.15` controller is rollback-only and no longer receives GitHub webhooks; `89.124.113.223` is retired. Do not connect to either old address without an explicit owner request naming the legacy contour. Unauthenticated Jenkins API calls return a login redirect or `Authentication required`; that only means auth is missing, not that the job is down. For POST requests such as job reconfiguration or manual `buildWithParameters`, also request a crumb from `/crumbIssuer/api/json` and send the returned cookie plus crumb header. When a dispatcher build has several downstream results and only one module failed, retry that module job directly with the original `BRANCH_NAME`, `GITHUB_BEFORE`, and `GITHUB_AFTER` instead of rebuilding successful modules. Keep Jenkins passwords, crumbs, GitHub tokens, and kubeconfigs out of logs and chat.

The dev `jenkins-remote-deployer` ArgoCD application owns the scoped CI service account, rollout/read-only ArgoCD RBAC, Liquibase runner, and migration admission policies from `kustomize/jenkins-remote-deployer`. Change those permissions only through reviewed `playsay-infra/develop` commits and wait for that application to become `Synced / Healthy`; do not apply the kustomization directly. `scripts/create-dev-ci-kubeconfig.sh` only reads the reconciled service-account token and writes the protected kubeconfig after the ArgoCD application and service account exist.

## Headlamp Kubernetes UI

Headlamp is installed at:

```text
https://ops.play-and-say.ru:18443/headlamp/
```

Get the dev-admin login token:

```bash
ssh root@<server-ip> \
  "kubectl -n headlamp get secret headlamp-admin-token -o jsonpath='{.data.token}' | base64 -d"
```

This token is cluster-admin for the dev cluster. Keep Headlamp dev-only and do not reuse this pattern for staging/prod without proper OIDC/RBAC.

## Keycloak Dev Instance

Sprint 1 installed Keycloak in minimal mode. It was first deployed before the VPS upgrade and is still intentionally single-replica/non-HA in dev:

- ArgoCD app: `keycloak`;
- namespace: `keycloak`;
- chart: local wrapper `helm-charts/keycloak`; it renders the official Keycloak StatefulSet directly and keeps only `bitnami/postgresql` `16.6.6` as a dependency;
- Keycloak version: `26.7.1`, pinned to the reviewed multi-architecture `quay.io/keycloak/keycloak` digest in both value files;
- URL: `https://dev.ops.honey.school/keycloak/` in dev and `https://ops.honey.school/keycloak/` in production;
- service: NodePort `32084` on localhost through host nginx;
- PostgreSQL: chart-managed standalone PostgreSQL with a `4Gi` PVC;
- images: the supported upstream Keycloak image comes from Quay; the existing PostgreSQL `17.4` image remains `docker.io/bitnamilegacy/postgresql` so this migration preserves the database StatefulSet, service, secret and PVC without combining a database-engine upgrade with the identity upgrade;
- login theme: `playsay`, stored in Git under `helm-charts/keycloak/themes/playsay` and mounted into Keycloak by the wrapper chart as a ConfigMap volume. Theme caches are disabled in dev. The theme serves the approved Honey School main/reverse SVG logos, favicon and local Quicksand 400/500/600 fonts from its ConfigMap; the technical theme id remains `playsay`. The page syncs color mode with the SPA: `playsay_theme=light|dark|system` in the authorize URL sets `data-playsay-theme` and `data-playsay-resolved-theme` on `<html>`, while direct login links and `system` follow `prefers-color-scheme`; language dropdown links preserve the current `playsay_theme` parameter. Login is user-initiated by method: the neutral Honey School page renders username/email, password and the primary password submit from the first paint, with Passkey as a visible secondary action. Page load, locale/theme changes and password errors perform no WebAuthn call. Only explicit Passkey activation starts `mediation=optional`, after which the browser may offer a local, security-key or intentional other-device QR flow. Cancellation clears the status without hiding either method; unexpected failure keeps password and Passkey retry usable; unsupported WebAuthn hides only the optional Passkey region. Conditional autofill stays disabled until the supported-browser matrix proves that it cannot surface modal, biometric/PIN, security-key or QR UI before selection. The page keeps warm Honey School background accents, one hero heading and a quiet localized return link to `https://honey.school/`. The custom WebAuthn registration page never asks for a credential label: it submits a localized default. Desktop starts registration immediately with a visible fallback button; iPhone/iPad Safari shows the button first so `navigator.credentials.create` runs inside a user gesture. All custom visible theme texts live in Keycloak message bundles for `ru`, `en`, `de`, and `fr`; frontend `ui_locales` and the Keycloak language dropdown must change both `<html lang>` and visible copy.
- future brand verification after a rollout: request `/brand/logo/honey-school-logo.svg`, `/brand/logo/honey-school-logo-reverse.svg`, `/brand/icons/favicon.svg`, `/brand/fonts/Quicksand-Regular.woff2`, and `/site.webmanifest` from each public SPA/root-site origin; verify `200`, the expected SVG/font/manifest MIME types, and no Google Fonts request. Open the Keycloak login URL in light and dark mode and verify the corresponding main/reverse logo, localized Honey School copy and favicon while confirming the issuer remains `/realms/playsay`.
- theme rollout: the wrapper StatefulSet computes `checksum/playsay-theme` from the theme ConfigMap. Changes below `helm-charts/keycloak/themes/playsay/login` therefore roll the Keycloak pod without a manual restart.
- secrets: `keycloak-admin` and `keycloak-postgresql`, created manually in the cluster and never committed to Git.
- initial realm: `playsay`;
- initial realm roles: `STUDENT`, `TEACHER`, `ADMIN`;
- initial clients: `playsay-web` and `playsay-api`.

Configure or repair the dev realm after Keycloak is healthy:

```bash
./scripts/configure-keycloak-dev.sh
```

Configure optional Passkeys after the upgraded pod is healthy. The script changes only the passwordless WebAuthn policy and required-action switch; it does not mutate clients, roles or users and is safe to run repeatedly:

```bash
./scripts/configure-keycloak-passkeys.sh
```

### Shared lesson-link authentication rollout

Shared lesson links are additive and remain disabled in both environment value files until the complete dependency chain has passed acceptance. The link token is deterministic `HMAC-SHA-256` over protocol version, exact environment issuer, lesson id, link revision and key version. Dev and production must use independently generated 256-bit secrets in their own `playsay-lesson-access` secret; never copy a secret between guests or store its decoded value in Git, shell history, logs, evidence, or chat. The secret contains `hmac-secret-base64` for API Gateway and a separately generated `provider-token` for the Keycloak provider-to-registration-service channel. Run `LESSON_ACCESS_NAMESPACE=<environment-namespace> ./scripts/provision-lesson-access-secret.sh` on the matching guest; the idempotent script creates missing environment-local values without printing them and preserves an existing secret on repeat runs. Then verify only the key names and secret resource version. Rotation increments `lessonAccess.hmacKeyVersion`; changing only the version invalidates new starts from prior link revisions without exposing or storing raw link tokens.

The Keycloak provider is built from `backend/keycloak-lesson-authenticator/Dockerfile`. It pins Keycloak `26.7.1` by upstream digest, installs the versioned SPI JAR and runs `kc.sh build`. Promote only a reviewed custom image digest; do not switch the chart to a mutable tag. Before the first custom-image rollout, copy the environment-local `ghcr-pull-secret` into that environment's `keycloak` namespace without decoding or printing its `.dockerconfigjson`; the Keycloak chart references only that same-named local pull secret. Never copy this credential between environments. After the custom image is healthy, configure the conditional browser flow idempotently from the matching guest. The script obtains the provider token from the environment-local Kubernetes secret and does not print it:

```bash
KEYCLOAK_URL=http://127.0.0.1:32084/keycloak \
KEYCLOAK_LESSON_PROVIDER_NAMESPACE=<environment-namespace> \
KEYCLOAK_LESSON_REDEEM_URL=http://registration-service.<environment-namespace>.svc.cluster.local/api/provider/lesson-auth/assertions/redeem \
KEYCLOAK_LESSON_ISSUER=https://<environment-auth-origin>/keycloak/realms/playsay \
./scripts/configure-keycloak-lesson-access.sh
```

The script copies the ordinary browser flow once, adds the lesson assertion authenticator as `ALTERNATIVE`, keeps password/passkey login unchanged when no assertion is present, and sets remembered SSO idle and maximum lifetimes to 30 days. Run it only after the provider and registration redemption endpoint are deployed. Verify an ordinary password login and explicit Passkey login immediately afterward.

Roll out in this order, keeping `lessonAccess.enabled=false`: database backups; additive Liquibase migrations; registration and email services; collaboration disconnect endpoint; API Gateway; custom Keycloak image; conditional flow configuration; web application. Run isolated acceptance for reusable links, exact roster matching, generic email responses, Lobby approve/deny, kick/re-admit, reconnect, 30-day remember choice, current/all-device revocation, changed roster/schedule, cross-environment rejection and unchanged password/passkey fingerprints. Enable issuance in dev only after those checks. Production requires separate owner authorization, new environment-local secrets and the same gates. Rollback first disables issuance, then returns application images and browser-flow binding to their previous reviewed revisions; do not restore the legacy credential-mutating invite consume path. Restore the database only when reverting an incompatible Keycloak schema migration according to the existing Keycloak backup procedure.

Dev uses RP ID `dev.ops.honey.school`. Production must be run on `playsay-prod` with its own kubeconfig and RP ID. Use the guest-local Keycloak NodePort because the public edge intentionally exposes realm/OIDC routes but hides the master/admin endpoints required by this script:

```bash
KEYCLOAK_URL=http://127.0.0.1:32084/keycloak \
KEYCLOAK_WEBAUTHN_RP_ID=ops.honey.school \
./scripts/configure-keycloak-passkeys.sh
```

The policy enables supported Keycloak Passkeys with `conditional` mediation, required user verification/discoverable credentials, ES256+RS256, attestation `none`, and an enabled but non-default `webauthn-register-passwordless` action. Password login and the custom Honey School email-code password reset remain available. The SPA starts first-key registration through `kc_action=webauthn-register-passwordless:skip_if_exists`, uses the plain action for additional keys, and manages safe credential metadata through owner-only application endpoints in the Honey School profile. The browser is never linked to the Keycloak Account Console.

Before either Keycloak rollout, create the normal environment backup and verify the Keycloak custom-format archive with both `sha256sum -c` and `pg_restore -l`. The server performs its own schema migration during first startup. If startup, login, or passkey acceptance fails after that migration, scale Keycloak to zero, restore the pre-upgrade Keycloak database, return GitOps to the previous revision, and then bring the old pod back; image rollback without DB restore is not an accepted rollback.

Before rollout run `./scripts/test-keycloak-passkey-theme.sh`; it rejects the label prompt, verifies the iPhone/iPad registration gesture branch, proves initialization performs zero authentication calls, and covers explicit activation, duplicate-click protection, cancellation, failure, password-switch abort and unsupported WebAuthn. Then run `helm dependency build helm-charts/keycloak`, `helm lint helm-charts/keycloak -f helm-charts/keycloak/values-dev.yaml`, and `helm template keycloak helm-charts/keycloak -f helm-charts/keycloak/values-dev.yaml`; do not commit the downloaded `charts/*.tgz`. After rollout verify the pod image/readiness, discovery document, realm WebAuthn fields through the Admin API, password login, the once-per-browser setup offer, first and additional AIA registration, in-app rename/delete, cancellation, password reset fallback, and that a redirect without a newly persisted credential is reported as failure. In desktop Chromium and mobile WebKit verify that initial load, locale/theme changes and a wrong-password reload show the complete password form and never open native WebAuthn UI. With no Honey School credential on the device, password entry must remain uninterrupted; with a virtual/local credential, only the explicit Passkey button may open and complete the chooser; cancellation must leave password and Passkey retry usable. On a phone-only credential profile, verify no QR appears before explicit Passkey activation and that intentionally selecting another device then opens the browser QR flow. On real iPhone Safari verify that **Add passkey → Keycloak continuation button → native Face ID/Touch ID/passcode sheet → profile with one extra key** still completes without a silent bounce, then sign out and verify repeat login starts only after the explicit Passkey action. Also accept one real Touch ID or Windows Hello registration/login. These real-device checks are a required production regression gate. This theme-only login change has no database migration; rollback returns the Keycloak application/root revision to the previous numeric release, waits for the theme checksum rollout, then repeats password and explicit-Passkey smoke without restoring the database.

The script is idempotent. It creates/updates:

- realm `playsay`;
- realm login theme `playsay`;
- realm i18n: `internationalizationEnabled=true`, supported locales `ru`, `en`, `de`, `fr`, and default locale `ru`;
- realm roles `STUDENT`, `TEACHER`, `ADMIN`;
- public web client `playsay-web` with Authorization Code + PKCE redirects for `https://dev.online.honey.school` and `https://dev.key.honey.school`, the localhost origins declared by `configure-keycloak-dev.sh`, and direct access grants enabled for server-side managed-student invite exchange by `registration-service`;
- backend client `playsay-api`;
- dev users `student-demo`, `student-demo-2`, `student-demo-3`, `student-demo-4`, `teacher-demo`, and `admin-demo`.

Demo passwords are generated once and stored in the Kubernetes secret `keycloak-dev-users` in the `keycloak` namespace. Re-running the script adds any missing password keys without rotating existing ones. `configure-keycloak-dev.sh` also syncs the three passwords required by Jenkins Sprint 5/Sprint 6 smoke into a same-named secret in the `jenkins` namespace through `scripts/sync-keycloak-dev-users-secret.sh`; run that sync script directly if the `jenkins` namespace is recreated. Do not commit or print those values in shared logs. Retrieve a password only when needed from `playsay-dev` through the AX41 jump host, replacing the jsonpath key with the needed user:

```bash
ssh -i /Users/evgeniymednov/.ssh/play_and_say_vps_ed25519 \
  -o IdentitiesOnly=yes \
  -o 'ProxyCommand=ssh -i /Users/evgeniymednov/.ssh/play_and_say_vps_ed25519 -o IdentitiesOnly=yes -W %h:%p root@65.109.55.110' \
  playsay@10.60.0.30 \
  "sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n keycloak get secret keycloak-dev-users -o jsonpath='{.data.student-demo-password}' | base64 -d"
```

Check status:

```bash
ssh -i /Users/evgeniymednov/.ssh/play_and_say_vps_ed25519 \
  -o IdentitiesOnly=yes \
  -o 'ProxyCommand=ssh -i /Users/evgeniymednov/.ssh/play_and_say_vps_ed25519 -o IdentitiesOnly=yes -W %h:%p root@65.109.55.110' \
  playsay@10.60.0.30 \
  "sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n argocd get app keycloak && sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n keycloak get pods,pvc,svc"
```

Get the admin password only when needed:

```bash
ssh -i /Users/evgeniymednov/.ssh/play_and_say_vps_ed25519 \
  -o IdentitiesOnly=yes \
  -o 'ProxyCommand=ssh -i /Users/evgeniymednov/.ssh/play_and_say_vps_ed25519 -o IdentitiesOnly=yes -W %h:%p root@65.109.55.110' \
  playsay@10.60.0.30 \
  "sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n keycloak get secret keycloak-admin -o jsonpath='{.data.admin-password}' | base64 -d"
```

Keep the dev instance single-replica, non-HA, and resource-limited even after the dev VPS upgrade.

After the first successful install on the original 2 vCPU / 4 GB VPS, observed usage was:

- Keycloak pod: about 470 Mi memory after startup;
- Keycloak PostgreSQL pod: about 40 Mi memory;
- node memory: about 2992 Mi / 76% by `kubectl top nodes`;
- host `MemAvailable`: about 768 Mi;
- swap: about 787 Mi used;
- disk `/`: about 18 Gi used out of 79 Gi.

This was tight but usable for Sprint 1 development. Re-check metrics after Jenkins builds and before teacher trials.

During Jenkins `dev-22` after adding UserProfile CRUD, the build completed successfully but the current VPS showed clear pressure: load average peaked around `6.6`, host `MemAvailable` dropped to about `411 Mi`, swap was about `809 Mi`, Kubernetes emitted a transient `NodeNotReady` event, and the external nginx path to `/jenkins` briefly returned `502` while Jenkins still answered through the local NodePort. Treat this as a warning signal, not yet a hard failure: no new app pods restarted and the rollout recovered cleanly.

## API Gateway Auth

`api-gateway` is a Spring Security OAuth2 Resource Server.

Public endpoints:

- `/hello`;
- `/actuator/health`;
- `/actuator/health/**`.
- `/livekit/webhook` is network-public to Spring Security but accepts only LiveKit-signed webhook payloads. It verifies the `Authorization: Bearer ...` JWT with the LiveKit API secret and the `sha256` raw body claim before recording attendance.

Protected endpoints:

- `/me` returns the current JWT profile: subject, username, email, name, and Keycloak realm roles.
- `GET /users/me/profile` returns the current app-level user profile.
- `PUT /users/me/profile` updates editable app-level fields: `displayName`, `locale`, `timezone`, and `learningGoal`.
- `DELETE /users/me/profile` resets editable app-level fields for the current user.
- `GET /admin/users` lists known app-level user profiles and requires the `ADMIN` role.
- `/admin/user-management/users|operations|students/*/teacher|delegations` provides the admin user-management facade.
- `/teacher/students|delegations` and `/teachers/directory` provide primary/delegated student management and the minimal active teacher directory.
- `GET/POST /schedule/lessons`, `GET/PUT/DELETE /schedule/lessons/{lessonId}` manage scheduled lessons.
- `POST /schedule/lessons/{lessonId}/room-token` returns a short-lived LiveKit join token for a teacher/admin or a student participant.

Sprint 2 moved UserProfile data out of the in-memory dev store into application PostgreSQL. Keycloak remains the source of identity and roles. `api-gateway` now stores the app-level profile fields in `app_user` and refreshes username, email, name, and roles from each JWT access.

### User management and delegation

No new deployment, ArgoCD application or Jenkins job is introduced. `api-gateway` owns `app_user.managed_by_teacher_user_id`, `teacher_delegation`, `teacher_delegation_student`, audit rows and background deletion operations. `registration-service` exclusively owns Keycloak Admin mutations. Deploy in this order: internal token wiring/endpoints, `api-gateway` Liquibase migration, `api-gateway`, then `web-app`.

Delegation periods are stored as instants converted from the primary teacher timezone (fallback `Europe/Moscow`); `ends_at` is exclusive at the next local day boundary. A substitute receives only student-scoped access. Schedule, classroom/collaboration, homework and AI Tutor enforce `PRIMARY_TEACHER`, `ACTIVE_DELEGATE`, `ADMIN` or `DENIED` server-side. A group lesson owned by the primary teacher can be started/completed by a substitute only when every participant is actively delegated.

Deletion is asynchronous and idempotent. `DELETE /api/admin/user-management/users/{subject}` returns `202` with an operation id; poll `/api/admin/user-management/operations/{operationId}` until `COMPLETED` or `FAILED`. Teacher deletion requires `replacementTeacherSubject` whenever dependent students/future lessons/active assignments/materials exist, and an `IN_PROGRESS` lesson blocks the request. The processor transfers ownership, revokes delegations, removes future student assignments, calls the three internal purge endpoints, deletes Keycloak invites/account through `registration-service`, and finally tombstones personal app-profile fields while historical rows remain anonymized.

Internal user-data purge endpoints are `DELETE /internal/user-data/{subject}` on `ai-tutor-service`, `vocabulary-service` and `keyboard-service`, all requiring `X-PlaySay-Service-Token`. They fail closed when the token is absent. `api-gateway` does not delete the Keycloak account until all three return `204`; a downstream failure leaves the operation `FAILED` for diagnosis/retry.

Operational checks:

```bash
kubectl -n playsay-dev get secret playsay-registration -o jsonpath='{.data.service-token}' | wc -c
kubectl -n playsay-dev get deploy api-gateway registration-service ai-tutor-service vocabulary-service keyboard-service
kubectl -n playsay-dev logs deploy/api-gateway --since=15m | grep -E 'User-data purge|USER_DELETE_FAILED'
```

Do not decode or print the token during normal verification. Role/self/last-admin protections are application checks; Keycloak console changes bypass the app audit and should remain break-glass operations only.

Dev runtime configuration is passed through the Helm chart:

```yaml
auth:
  issuerUri: https://dev.ops.honey.school/keycloak/realms/playsay
  jwkSetUri: http://keycloak.keycloak.svc.cluster.local/keycloak/realms/playsay/protocol/openid-connect/certs
ai:
  openai:
    enabled: true
    existingSecret: playsay-openai
    apiKeyKey: api-key
    model: gpt-5.6-sol
    baseUrl: https://api.openai.com/v1
database:
  existingSecret: playsay-app-db
  liquibaseEnabled: "false"
livekit:
  serverUrl: wss://dev.online.honey.school/livekit
  existingSecret: livekit-keys
  tokenTtlSeconds: "3600"
```

The issuer stays public because Keycloak puts that value into tokens. The JWKS URI is internal so `api-gateway` can validate signatures without routing through host nginx.

## OpenAI Material Drafts

Sprint 4 material authoring can run in two modes:

- `PLAYSAY_AI_PROVIDER=stub`: deterministic local draft generator, no external API call.
- `PLAYSAY_AI_PROVIDER=openai`: `api-gateway` calls the OpenAI Responses API and requests JSON Schema / Structured Outputs for the Play&Say material draft.

The model and reasoning efforts are ordinary environment-specific Git configuration. Both dev and prod use `gpt-5.6-sol`; full material drafts use `high`, while answer suggestions, HTML-game metadata and vocabulary suggestions use `low`. Backend startup rejects any effort outside `none|low|medium|high|xhigh|max`.

The Kubernetes secret `playsay-openai` contains only `api-key`. Dev and prod use separate OpenAI Platform projects and keys.

Create or update the environment's secret from an interactive terminal on the corresponding VM without printing the key. Set `TARGET_NAMESPACE=playsay-dev` on `playsay-dev` or `TARGET_NAMESPACE=playsay-prod` on `playsay-prod`:

```bash
set -euo pipefail

read -rsp "OpenAI API key: " PLAYSAY_OPENAI_API_KEY
echo

KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n "$TARGET_NAMESPACE" create secret generic playsay-openai \
  --from-literal=api-key="$PLAYSAY_OPENAI_API_KEY" \
  --dry-run=client -o yaml | KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl apply -f -

unset PLAYSAY_OPENAI_API_KEY

KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n "$TARGET_NAMESPACE" get secret playsay-openai
```

Expected verification output is `playsay-openai` with `DATA` equal to `1`. Do not decode or paste the secret value into chat, Git, logs, or docs. To verify only the key name without decoding its value:

```bash
KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n "$TARGET_NAMESPACE" \
  get secret playsay-openai -o go-template='{{range $key, $_ := .data}}{{printf "%s\n" $key}}{{end}}'
```

After deploying the chart, verify the non-secret configuration without printing credentials:

```bash
KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n "$TARGET_NAMESPACE" get deploy api-gateway \
  -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' | grep -E 'PLAYSAY_AI_PROVIDER|OPENAI_MODEL|OPENAI_.*REASONING_EFFORT'
KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n "$TARGET_NAMESPACE" get deploy vocabulary-service \
  -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' | grep -E 'PLAYSAY_VOCABULARY_OPENAI_(MODEL|REASONING_EFFORT)'
```

Expected values are provider `openai`, model `gpt-5.6-sol`, draft effort `high` and all three lightweight efforts `low`. Run authenticated smokes for material draft, answer suggestions, HTML-game metadata and vocabulary suggestions; record no prompt, user content or secret values.

## Web App Auth

`web-app` uses Keycloak Authorization Code + PKCE with the public client `playsay-web`.

Dev defaults:

```text
VITE_AUTH_ISSUER=https://dev.ops.honey.school/keycloak/realms/playsay
VITE_AUTH_CLIENT_ID=playsay-web
VITE_AUTH_REDIRECT_PATH=/auth/callback
```

The production container serves the SPA through nginx. Requests to generic `/api/*` are proxied inside the `playsay-dev` namespace to `http://api-gateway/*`, so the browser calls the backend through the same origin `https://online.play-and-say.ru`. The specific media stream route `/api/media/video-playback-sessions/*` is handled before generic `/api/*` and proxies to `http://media-service/*` with buffering disabled. The same origin also carries WebSocket classroom sync at `/api/ws/lessons`; both the host nginx `online.play-and-say.ru` location and the web-app container nginx must pass `Upgrade` and `Connection` headers for websocket paths. The frontend calls `/api/me`, `/api/users/me/profile`, schedule endpoints, the LiveKit room-token endpoint, `/api/ws/lessons`, and media stream URLs through this same-origin route.

Current Sprint 1 UI verification points:

- login through Keycloak returns to `https://online.play-and-say.ru`;
- the user panel shows the current Keycloak identity and Play&Say roles;
- the role workspace changes between student, teacher, and admin demo users;
- the admin demo user sees the admin-only known profile list;
- logout clears local `sessionStorage` auth state and redirects through Keycloak logout.

Final Sprint 1 closure checklist:

```bash
# ArgoCD apps should be Synced / Healthy on the latest dev revision.
kubectl -n argocd get applications.argoproj.io playsay-dev-root api-gateway web-app keycloak

# Product pods should be ready and labelled with the latest Jenkins build, for example dev-24.
kubectl -n playsay-dev get pods --show-labels

# Public entrypoints should answer.
curl -k -I https://online.play-and-say.ru/
curl -k -sS https://online.play-and-say.ru/api/hello
curl -k -I https://ops.play-and-say.ru:18443/keycloak/
```

Manual auth checks:

- `student-demo`, `student-demo-2`, `student-demo-3`, and `student-demo-4` can log in, see the student workspace, `/api/me` and `/api/users/me/profile` return `200`;
- `teacher-demo` can log in, sees the teacher workspace, `/api/admin/users` returns `403`;
- `admin-demo` can log in, sees the admin workspace, `/api/admin/users` returns `200`;
- logout returns through Keycloak and clears the local browser session.

## Collaboration Service

Sprint 5 adds a Yjs websocket service for live individual and group lesson documents.

GitOps resources:

- ArgoCD app: `argocd-apps/dev/apps/collaboration-service.yaml`;
- Helm chart: `helm-charts/collaboration-service`;
- namespace: `playsay-dev`;
- image: `ghcr.io/mednov-ai/playsay-collaboration-service`;
- secret: `playsay-collaboration` in namespace `playsay-dev`.

The same `playsay-collaboration` secret is mounted into `api-gateway` and `collaboration-service`. It contains:

- `token-secret`: HS256 signing secret for backend-issued room tokens;
- `service-token`: header token used by `collaboration-service` when it persists room snapshots back to api-gateway.

Create or refresh it without printing values:

```bash
./scripts/sync-collaboration-secret.sh
```

`deploy-cluster-addons.sh` runs the sync script automatically when it exists. Do not commit or print the secret values.

Host nginx config is generated with a `/collab/ws` location under `online.play-and-say.ru`:

- public websocket URL: `wss://online.play-and-say.ru/collab/ws`;
- local NodePort target: `127.0.0.1:32086`;
- Kubernetes service: `collaboration-service` in `playsay-dev`.

The frontend receives short-lived room tokens from api-gateway, then opens `/collab/ws?room=<yjsDocumentId>&token=<token>`. The websocket service validates that the room query exactly matches token claims before joining the Yjs room. Snapshot persistence uses `PUT /schedule/lessons/{lessonId}/collaboration-documents/{documentId}/snapshot` with header `X-PlaySay-Collaboration-Service-Token`.

SDK v1 HTML games may open a second connection to the same URL with subprotocol `playsay-game-v1`. It is a separate TCP/TLS queue and accepts only the bounded game protocol; normal sockets reject game frames and game sockets never receive Yjs sync or awareness. Configure it with `collaboration.gameRealtimeMode`, rendered as `GAME_REALTIME_MODE=off|shadow|primary`: production/default remains `off`; AX41 dev remains in `shadow`, where the browser dual-publishes with event-id deduplication. The final 2026-08-06 client-pipeline comparison (`playsay-platform` `dc6b59d`, web build `web-dev-180`) used three 40-action runs per mode. `shadow` median produced `8.5 ms` combined client p95, `4.9 ms` local optimistic p95, zero transient React commits and about 9% loaded end-to-end improvement; `primary` produced about `8.9 ms`, `4.9 ms`, zero commits and only about 4% loaded improvement. Both modes had zero integrity or visual failures, but neither met the `6 ms` client and 10% loaded gates, so `primary` was not accepted and AX41 dev was restored to `shadow`. `primary` uses the fast lane while open and the existing ephemeral path on negotiation failure or disconnect. Roll back without data changes by setting the dev value to `off`, committing only that values change and waiting for the collaboration ArgoCD application to become `Synced/Healthy`.

Monitor `playsay_collaboration_game_active_connections`, `playsay_collaboration_game_messages_total`, `playsay_collaboration_game_bytes_total`, `playsay_collaboration_game_relay_duration_seconds`, `playsay_collaboration_game_websocket_buffered_bytes`, the existing buffered-bytes/backpressure metrics, pod restarts and memory. The socket disables per-message compression, enables TCP no-delay plus keepalive, and the AX41 edge `/collab/ws` location must keep both `proxy_buffering off` and `proxy_request_buffering off`. The in-process relay p95 target is below `5 ms`; ordered game messages are not dropped at the soft backpressure limit and a hard-limit close uses `1013` so the browser falls back and resynchronizes from the checkpoint.

Run the deterministic transport benchmark separately from AI generation:

```bash
PLAY_SAY_GAME_COMPARE_CANDIDATE=fixed \
PLAY_SAY_GAME_COMPARE_SAMPLES=40 \
PLAYWRIGHT_PACKAGE_DIR=/Users/evgeniymednov/.codex/tools/playwright \
node scripts/smoke/game-adaptation-compare.mjs

PLAY_SAY_GAME_COMPARE_CANDIDATE=ai \
PLAY_SAY_GAME_COMPARE_SAMPLES=40 \
PLAYWRIGHT_PACKAGE_DIR=/Users/evgeniymednov/.codex/tools/playwright \
node scripts/smoke/game-adaptation-compare.mjs
```

The fixed run compares the same DOM/CSS and mechanics as `LEGACY_PREDICTIVE` and manually authored `SDK_V1`; the AI run independently proves `mechanics-v3`. Both use isolated teacher/student sessions, both directions, 40 button, keyboard and range actions, idle plus parallel collaboration load, and write JSON with commit/build/time/runtime, raw payload-free trace, p50/p95/p99, stage counts, client outbound/inbound segments, React render/listener counters, long tasks, event-loop delay and screenshot/DOM/computed-style fingerprints. Repeat the fixed run three times and use the median. Require 40/40 actions of every kind, zero missing/duplicate/reordered reducer applications, no visual or DOM/style change, combined client outbound+inbound p95 at most `6 ms`, local optimistic p95 at most `8 ms` (hard maximum `32 ms`), zero React commits per transient action, server relay p95 below `5 ms`, no idle regression and at least 10% loaded end-to-end p95 improvement. Reconnect must converge to one revision within 3 seconds.

To isolate the fast path from `shadow` dual-publish overhead, change only AX41 dev to `primary` through the normal `playsay-infra/develop` commit and ArgoCD sync, run the three isolated comparisons, and always restore `shadow` through the same GitOps path after the measurement. Do not use a manual deployment patch and do not leave dev in `primary` merely because functional checks pass. If the client `6 ms` gate passes but loaded end-to-end improves by less than 10%, record network/socket transit as the remaining constraint and prepare a separate geographically close relay/WebRTC plan; do not alter game rules, timers, reducer, DOM or CSS to compensate.

Playwright MCP is an additional semantic/visual smoke tool, not a latency clock. Install it outside the repositories with official `@playwright/mcp@0.0.79`, restart Codex, and use isolated teacher/student browser sessions for accessibility snapshots, visible controls, activity rail, different viewport sizes, screenshots and reconnect. Keep numeric latency collection in the deterministic script so MCP/model RPC time cannot contaminate p50/p95/p99.

Smoke checks:

```bash
kubectl -n argocd get applications.argoproj.io collaboration-service api-gateway web-app
kubectl -n playsay-dev get pods -l app.kubernetes.io/name=collaboration-service
kubectl -n playsay-dev get secret playsay-collaboration
curl -k -I https://online.play-and-say.ru/collab/ws
```

Expected `curl` result is an HTTP response from the service path, not a full websocket session. Functional verification happens in the browser: teacher creates a group lesson, two students join, each student edits an individual document, everyone edits the group document, colored presence cursors appear, reconnect restores text and annotations, and finalize creates a normal material submission.

Automated Sprint 5 UI smoke and Sprint 6 homework smoke live in `playsay-platform`. Jenkins runs them automatically after updating dev image tags, using the Playwright smoke container and the `keycloak-dev-users` secret in the `jenkins` namespace. The same scripts can still be run locally with the agent Playwright install without adding Playwright to the app dependencies:

```bash
cd /Users/evgeniymednov/Documents/Projects/Play\&Say/playsay-platform
PLAYWRIGHT_PACKAGE_DIR=/Users/evgeniymednov/.codex/tools/playwright \
  ./scripts/smoke/sprint5-ui-smoke.mjs
PLAYWRIGHT_PACKAGE_DIR=/Users/evgeniymednov/.codex/tools/playwright \
  ./scripts/smoke/sprint6-homework-smoke.mjs
```

The Sprint 5 and Sprint 6 scripts default to the current AX41 dev contour (`https://dev.online.honey.school`, issuer `https://dev.ops.honey.school/keycloak/realms/playsay`) and obtain Keycloak Authorization Code + PKCE tokens as `teacher-demo`, `student-demo`, and `student-demo-2`. They read demo passwords from env vars in Jenkins or from the dev `keycloak-dev-users` Kubernetes secret through the AX41 jump host during local runs without printing them. Sprint 5 creates a temporary published private material, active group lesson and required collaboration documents through the API, then drives real browser classroom pages for teacher + two students; it verifies individual documents, teacher supervision/edit, group document sync, colored material-scoped cursors clipped to the lesson material surface, annotation sync after scroll/resize/reload, and finalize creating a normal material submission. Sprint 6 creates temporary homework material, standalone group/single assignments and lesson carry-over homework, then verifies homework UI, permissions, score/errors progress and resubmit. Both scripts clean up temporary lessons and archive temporary materials at the end.

## LiveKit Dev Video

Sprint 3 video work started early to make the platform demonstrable from the schedule screen.

GitOps resources:

- ArgoCD app: `argocd-apps/dev/apps/livekit.yaml`;
- Helm chart: `helm-charts/livekit`;
- namespace: `livekit`;
- image: `livekit/livekit-server:v1.11.0`;
- LiveKit secret name: `livekit-keys` in namespaces `livekit` and `playsay-dev`.
- coturn secret name: `coturn-auth-secret` in namespace `livekit`.

The dev chart runs one LiveKit pod with `hostNetwork: true` and `enableServiceLinks: false` on the current single-node VPS. `enableServiceLinks` must stay disabled because Kubernetes service env vars such as `LIVEKIT_PORT=tcp://...` conflict with LiveKit's own numeric `LIVEKIT_PORT` option. Host nginx proxies signaling through the product origin:

- public signaling URL: `wss://online.play-and-say.ru/livekit`;
- local signaling target: `127.0.0.1:7880`;
- LiveKit TCP fallback: `7881`;
- dev ICE UDP range: `50000-50020`.
- standalone TURN host: `online.play-and-say.ru:3478` over UDP/TCP;
- coturn relay UDP range: `49160-49200`.

The LiveKit API key/secret are generated or synced by:

```bash
./scripts/sync-livekit-secret.sh
```

`deploy-cluster-addons.sh` runs the sync script automatically when it exists. Do not commit or print the secret values. If the `livekit` namespace already has `livekit-keys`, the script reuses it and copies it to `playsay-dev` for `api-gateway`.

The standalone coturn shared secret is generated by the Ansible `coturn` role on the VPS:

```text
/etc/playsay/coturn-auth-secret
```

Sync the canonical 64-character hex value into Kubernetes before the LiveKit chart with TURN enabled syncs. The script removes CR/LF and rejects any other shape without printing the value:

```bash
./scripts/sync-coturn-secret.sh
```

`deploy-cluster-addons.sh` also runs the coturn sync script automatically. A changed Secret does not alter an already running pod environment, so schedule a no-room maintenance window and request the explicit restart:

```bash
./scripts/sync-coturn-secret.sh --restart-livekit
```

The LiveKit container defensively removes CR/LF and validates the secret again before writing `/tmp/livekit.yaml`. Do not print the file content or decoded Kubernetes value. If UFW or another firewall is later enabled, allow `3478/tcp`, `3478/udp`, and `49160:49200/udp`.

The LiveKit chart sends webhooks to the internal api-gateway service:

```text
http://api-gateway.playsay-dev.svc.cluster.local/livekit/webhook
```

`api-gateway` handles `participant_joined` and `participant_left` by updating `lesson_participant.joined_at`, `left_at`, `attendance_status`, and setting the lesson to `IN_PROGRESS` on first join. The controller accepts `application/json` and `application/webhook+json` as raw bytes, verifies the JWT `sha256` claim against those exact bytes, and only then decodes JSON. The endpoint is hidden from the public OpenAPI contract and must not be called manually without a valid LiveKit webhook signature.

Host nginx config is generated with a `/livekit/` location under `online.play-and-say.ru`, and the main `location /` must also pass WebSocket upgrade headers so `/api/ws/lessons` can reach the web-app container and then `api-gateway`. After changing the script on an existing server, rerun the add-ons script or manually verify the rendered host config:

```bash
nginx -t
systemctl reload nginx
```

Smoke checks:

```bash
kubectl -n argocd get applications.argoproj.io livekit api-gateway web-app
kubectl -n livekit get pods -o wide
kubectl -n playsay-dev get secret livekit-keys
kubectl -n livekit get secret coturn-auth-secret
systemctl status coturn --no-pager
ss -lntup | grep -E ':(3478|7880|7881)\b'
curl -k -I https://online.play-and-say.ru/livekit/
```

Verify TURN authentication with an actual allocation, not only an open port. Keep the secret in a transient shell variable and never enable verbose output:

```bash
set -e
COTURN_SMOKE_SECRET="$(tr -d '\r\n' </etc/playsay/coturn-auth-secret)"
turnutils_uclient -W "$COTURN_SMOKE_SECRET" -p 3478 -n 1 -c 127.0.0.1
unset COTURN_SMOKE_SECRET
```

The command must exit `0`, coturn logs must not contain `Cannot find credentials`, and a cross-network browser check must show a selected `relay` ICE candidate when relay-only policy is forced in the diagnostic client. Also confirm normal Play&Say calls prefer a healthy direct path when available.

For a functional check, log in to `https://online.play-and-say.ru` as a teacher, create or reuse a scheduled lesson with `student-demo`, `student-demo-2`, and `student-demo-3` as participants, and enter the classroom. Before students open the room, teacher/admin must see one persistent placeholder tile per assigned student with “not connected yet”; a student must never receive that presence map. Log in as each student in a separate browser profile and confirm the teacher tile changes `OFFLINE → ONLINE`. Open the classroom URL as a student: the branded pre-join must appear without creating a LiveKit participant, and the teacher tile must change to “checking connection”. Allow camera/microphone permissions, verify the camera preview and choose the intended input/output. Hold the sound button for `0.3–5` seconds, speak, release it, listen to the automatically played recording and confirm “yes, I hear”; the live meter is informational and background noise alone must not mark the microphone ready. Where supported, verify playback follows the selected output; otherwise it must use the system output. Changing either audio device must reset the check. A short/failed/skipped recording must show a warning and still allow the explicit second-click entry. Device choices survive reload, while pre-join appears before every entry.

Repeat pre-join at `1280×720`, `1440×900`, and a phone viewport. At `1280×720`, the join button must remain visible, the result area must not resize when the hearing confirmation appears, and the page must not jump upward. Only after entry confirmation may the room-token request run and LiveKit connect. The teacher’s placeholder must then be replaced by the real LiveKit participant with no duplicate; in an individual lesson the absent student is the main tile and local teacher video is PiP, while a group lesson shows every assigned student. In the room, verify microphone/camera device menus can switch inputs without leaving, the page does not scroll, and controls expose microphone/camera/screen share according to participant permissions. Finally close/reopen the student WebSocket and confirm `ONLINE` is restored; with two student tabs, one tab in pre-join keeps the aggregated state at `CHECKING_DEVICES` until it leaves.

For screen-share audio, use macOS 14.2+ and a current Chrome/Edge profile. Start full-screen sharing with `Share system audio` enabled in the browser picker: the first capture must request the macOS `Screen & System Audio Recording` permission, and after permission is granted Chrome must be restarted if macOS requests it. The remote participant must hear shared media once while microphone audio remains independent, and the remote voice must not loop back as echo. Repeat with browser audio sharing disabled and confirm the localized macOS no-audio warning appears; its reselect action must stop both existing publications and reopen the picker, where enabling system audio produces both `ScreenShare` and `ScreenShareAudio`. Also repeat with another Chrome tab and `Share tab audio`. If student autoplay is blocked, the compact start-media control must make the published screen audio audible. Finally stop sharing through both the Play&Say button and Chrome UI and confirm screen video/audio publications and the warning disappear. In Safari, confirm video-only sharing continues and shows the Safari-specific Chrome/Edge recommendation. At `1280×720` and `1440×900`, the warning and action must stay above the controls without resizing the classroom or covering the primary video.

## Application PostgreSQL

Sprint 2 starts the application database on the same dev VPS. It was introduced before the later VPS upgrade, and the database setup remains intentionally small until the first teacher trial proves that more capacity is needed.

GitOps applications:

- `cloudnative-pg`: CloudNativePG operator `1.29.1`, installed from a local Kustomize overlay pinned to the upstream tag `v1.29.1`;
- `app-postgres`: Play&Say application PostgreSQL cluster, rendered from `helm-charts/app-postgres`.

Dev shape:

- namespace: `playsay-data`;
- cluster name: `playsay-postgres`;
- PostgreSQL image: `ghcr.io/cloudnative-pg/postgresql:17.6-system-trixie`;
- instances: `1`;
- storage: `2Gi` PVC;
- requests/limits: `50m/128Mi` requests, `500m/384Mi` limits;
- database: `playsay`;
- owner: `playsay_app`.

Check status:

```bash
kubectl -n argocd get applications.argoproj.io cloudnative-pg app-postgres
kubectl -n cnpg-system get pods
kubectl -n playsay-data get cluster,pods,pvc,secrets
kubectl -n playsay-data get svc
```

CloudNativePG generates database credentials as Kubernetes secrets. Retrieve values only when needed for wiring an application or a manual smoke test; do not paste them into chat, Git, shell history snippets, or documentation.

Because `app-postgres` runs in `playsay-data`, while `api-gateway` runs in `playsay-dev` and Jenkins agents run in `jenkins`, copy the generated application connection secret into those namespaces after the database is healthy:

```bash
./scripts/sync-app-db-secret.sh
```

The script copies `playsay-postgres-app` from `playsay-data` into `playsay-app-db` in `playsay-dev` and `jenkins`, using the source secret's `fqdn-jdbc-uri` as the target `jdbc-uri`. It handles secret values through temporary files and does not print them. Re-run it if CloudNativePG rotates the application password or if a namespace is recreated.

`api-gateway` uses this secret through Helm env vars:

- `PLAYSAY_DB_JDBC_URL` from `playsay-app-db` key `jdbc-uri`;
- `PLAYSAY_DB_USERNAME` from key `username`;
- `PLAYSAY_DB_PASSWORD` from key `password`;
- `PLAYSAY_LIQUIBASE_ENABLED=false` in the runtime pod.

Keep the CloudNativePG operator overlay less aggressive than the upstream default: `--max-concurrent-reconciles=2`, `500m/256Mi` limits, and 5-second probe timeouts. The upstream `100m` CPU limit plus 1-second probes repeatedly lost leader election while Jenkins was building `dev-28` on the original 2 vCPU / 4 GB VPS.

Useful connection endpoints inside the cluster:

- read/write service: `playsay-postgres-rw.playsay-data.svc.cluster.local:5432`;
- read-only service: `playsay-postgres-ro.playsay-data.svc.cluster.local:5432`;
- database: `playsay`;
- app user: `playsay_app`.

Initial Sprint 2 schema is owned by `api-gateway` changelogs:

- changelog root: `backend/api-gateway/src/main/resources/db/changelog/db.changelog-master.xml`;
- first changeset: `2026-05-24-001-create-sprint2-domain-tables`;
- tables: `app_user`, `student_profile`, `teacher_profile`, `course`, `lesson_template`, `lesson`, `lesson_participant`, `assignment`, `submission`;
- `/users/me/profile` persists editable fields in `app_user` instead of memory.

Manual migration smoke path, matching Jenkins network and secrets:

1. Ensure `playsay-app-db` exists in `jenkins` by running `./scripts/sync-app-db-secret.sh`.
2. Start a temporary pod in `jenkins` with `liquibase/liquibase:5.0.3`.
3. Copy the `db/changelog` directory into the pod.
4. Download PostgreSQL JDBC driver `42.7.8`.
5. Run `liquibase status --verbose` and `liquibase update`.

On 2026-05-24 this path applied one pending changeset successfully and the expected tables appeared in `public`.

After enabling this database, re-check VPS pressure:

```bash
uptime
free -m
kubectl top nodes
kubectl top pods -A | sort -k3 -h | tail -n 20
```

## Optional Separate Server Bootstrap

Install Ansible dependencies:

```bash
cd playsay-infra/ansible
ansible-galaxy collection install -r requirements.yaml
```

Create inventory:

```bash
cp inventories/dev/hosts.yaml.example inventories/dev/hosts.yaml
```

Edit `inventories/dev/hosts.yaml`:

- `ansible_host`
- `public_ipv4`
- `ansible_ssh_private_key_file`
- `dev_domain`

Run bootstrap:

```bash
cd playsay-infra
./scripts/new-server.sh dev
```

## Optional Local kubectl

Local kubeconfig is not required for initial bootstrap. It is useful later for diagnostics:

```bash
mkdir -p ~/.kube/configs
scp playsay@<server-ip>:/home/playsay/.kube/config ~/.kube/configs/playsay-dev
export KUBECONFIG=~/.kube/configs/playsay-dev
kubectl get nodes
```

If the k3s API is not exposed publicly, create an SSH tunnel and replace the kubeconfig server URL with `https://127.0.0.1:6443`.

## Optional Separate Cluster Add-ons

```bash
export PLAYSAY_DOMAIN=dev.example.com
export LETSENCRYPT_EMAIL=admin@example.com
export ARGOCD_HOST=argocd.dev.example.com
export HEADLAMP_HOST=headlamp.dev.example.com
export OPS_HOST=ops.play-and-say.ru
export OPS_PORT=18443
export OPS_TLS_MODE=auto
# Optional CIDRs, for example Amnezia VPN subnet and/or fixed admin IP.
export OPS_ALLOW_CIDRS=
export INSTALL_JENKINS=true
export INSTALL_INGRESS_NGINX=false
export INSTALL_CERT_MANAGER=false
export CONFIGURE_HOST_NGINX=true

./scripts/deploy-cluster-addons.sh dev
```

## ArgoCD

Initial admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

Open:

```text
https://argocd.dev.example.com
```

## Upgrade VDSina VPS

Upgrade completed on 2026-05-24 after Sprint 2 CI pressure. Current dev VPS shape:

- CPU: 4 vCPU
- RAM: 8 GB
- Disk: 160 GB NVMe
- Traffic: 32 TB

The root disk still needed an in-guest online resize after the provider-side upgrade.

Baseline metrics captured before Sprint 1 on the original 2 vCPU / 4 GB / 80 GB VPS:

- CPU: about 5% from `kubectl top nodes`;
- Kubernetes memory: about 2702 Mi / 69%;
- host memory: 3.8 Gi total, 2.6 Gi used, 1.3 Gi available;
- swap: 2.0 Gi total, 754 Mi used;
- disk `/`: 79 Gi total, 16 Gi used, 61 Gi available;
- largest local dirs: `/var/lib/rancher` about 7.6 Gi, `/var/log` about 1.3 Gi, `/var/lib/docker` about 108 Mi.

Historical upgrade triggers:

- Keycloak/PostgreSQL or Jenkins builds start causing OOM kills or pod restarts;
- `MemAvailable` stays below about 500 Mi during normal idle/dev usage;
- swap stays above about 1 Gi and the UI/builds become painfully slow;
- Jenkins builds repeatedly cause transient `NodeNotReady` or external `/jenkins` `502` errors;
- the first teacher trial conference needs a more stable environment.

The VDSina panel flow was:

1. Open the server configurator.
2. Increase resources:
   - actual Sprint 2 upgrade: 4 vCPU / 8 GB / 160 GB
   - future Sprint 4+: 8 vCPU / 16 GB / 160+ GB if needed
3. Apply changes and let the server reboot.
4. Expand the root partition and filesystem on the VPS:

```bash
growpart /dev/vda 1
resize2fs /dev/vda1
```

Before the in-guest resize, the provider disk was already `160G`, but `/dev/vda1` and `/` were still about `80G`. After the resize:

- `/dev/vda1`: `160G`
- `/`: ext4 `158G`, about `23G` used and `129G` available

5. Verify:

```bash
kubectl get nodes
kubectl get pods -A
df -hT /
free -h
systemctl is-active nginx k3s docker
nginx -t
```

After the resize, `nginx`, `k3s`, and `docker` were active, `nginx -t` passed, ArgoCD apps were `Synced / Healthy`, and the deployed `api-gateway` / `web-app` pods were ready on build `dev-28`.

Also run the post-install verification checklist above after any future reboot or resize, including the public site, Amnezia Docker containers, nginx syntax, ops UI, and `online.play-and-say.ru`.

## Dev Backup Stub

Sprint 1 keeps backups intentionally simple until real production data exists.

Backup scope:

- Keycloak PostgreSQL database;
- application PostgreSQL database once the platform database is introduced.

Storage target:

- local directory on the dev VPS, for example `/var/backups/playsay`;
- files must not be committed to Git or copied into the workspace;
- external S3/restic storage for database dumps is deferred until real user data or staging/prod hardening; material assets already live in dev MinIO and must be included in the real backup plan before production data.

Expected backup shape:

```bash
mkdir -p /var/backups/playsay
pg_dump "$KEYCLOAK_DATABASE_URL" > "/var/backups/playsay/keycloak-$(date +%F-%H%M%S).sql"
pg_dump "$PLAYSAY_DATABASE_URL" > "/var/backups/playsay/playsay-$(date +%F-%H%M%S).sql"
```

Use Kubernetes secrets or pod environment variables to obtain database connection details. Do not paste database passwords into chat, Git commits, shell history snippets, or documentation.

## Disaster Recovery Drill

1. Create a fresh VPS.
2. Run `./scripts/bootstrap-dev.sh --ip <new-ip> --domain dev.example.com --email admin@example.com`.
3. Switch DNS to the new IP.
4. Let ArgoCD restore Git-defined applications.
5. Restore Keycloak and application PostgreSQL dumps from `/var/backups/playsay` when those databases exist.
6. Run the post-install verification checklist above.

Before real student/teacher data appears, replace the local-only backup target with off-server storage and test a full restore.

## Rollback

Application rollback is GitOps-based:

```bash
cd playsay-infra
git revert <bad-commit>
git push
```

ArgoCD will sync the reverted state.

## Game Adapter Service

`game-adapter-service` is a stateless internal Node.js service deployed by ArgoCD from `helm-charts/game-adapter-service`. It has no database and no public ingress. `api-gateway` calls `http://game-adapter-service` with the shared token from secret `playsay-game-adapter`; the adapter reads the OpenAI key from the existing `playsay-openai` secret. Default reviewed configuration is model `gpt-5.6-sol` with reasoning effort `medium`. Do not place either secret value in Helm values, Jenkins parameters, logs, or chat.

The runtime image includes system Chromium and `playwright-core`. Each generated game is checked fail-closed before it can become `READY_FOR_REVIEW`: original and candidate run offline with the same seed/viewport, each physical validation input must emit exactly one declared semantic action, observable DOM/control state must remain equivalent, source CSS declarations must not change, and runtime/network/action-rate checks must pass. The current validator version is `mechanics-v3`. A range step uses `{kind:"set-range",selector:"#speed",value:"3"}`, validates the original `min/max/step`, dispatches `input` then `change`, and still requires exactly one semantic action. Failed validation persists only a bounded code/version/mechanics flag in the existing JSON report; it never stores source HTML, selectors or action payloads. Rows validated by v2 become `REVALIDATION_REQUIRED`; applied rows are not automatically rolled back. The pod runs as UID/GID `10001` with a read-only root filesystem; Chromium writes only to the `runtime-tmp` `emptyDir` mounted at `/tmp/playsay`. Keep the default runtime request `250m/256Mi`, limit `1 CPU/1Gi`, and `emptyDir.sizeLimit=256Mi` unless measurements justify a change. Building the Debian+Chromium layer requires the dedicated Game Adapter Kaniko container request `512Mi` and limit `2Gi`; the previous `1Gi` limit was OOM-killed while snapshotting the installed Chromium packages.

Create or reconcile the service token before the first ArgoCD sync:

```bash
cd playsay-infra
./scripts/sync-game-adapter-secret.sh
```

The script preserves an existing token and updates only the named modern cluster namespace. It must not be run against the legacy VPS or either protected `legacy/play-and-say-vps` branch. The application is internal-only, so no nginx route, DNS record, browser CORS origin, or WebSocket permission is required. Classroom collaboration continues over `wss://dev.online.honey.school/collab/ws`, direct production `wss://online.honey.school/collab/ws`, and the Selectel production alias `wss://online.honeyschool.ru/collab/ws`; the root `honeyschool.ru` landing does not host classroom WebSockets.

Install/update the Jenkins job after the infra commit is present:

```bash
./scripts/configure-jenkins-jobs.sh
```

`playsay-game-adapter-service-develop` tests and builds `@playsay/game-sync` first, then tests/builds the adapter, builds the runtime image and updates `helm-charts/game-adapter-service/values-dev.yaml` with an immutable digest. Changes in `frontend/game-sync-sdk/**` intentionally route to both the adapter and web-app because the iframe bridge and injected SDK must use the same protocol. Changes in `frontend/game-adapter-service/**` route only to the adapter.

After rollout, verify only resource presence and health; never print secret data:

```bash
kubectl -n playsay-dev get secret playsay-game-adapter playsay-openai
kubectl -n playsay-dev rollout status deploy/game-adapter-service
kubectl -n playsay-dev get svc game-adapter-service
kubectl -n playsay-dev port-forward svc/game-adapter-service 18088:80
curl -fsS http://127.0.0.1:18088/actuator/health
```

For a rollout smoke, inspect the pod without printing environment values, then submit one known fixture through `api-gateway` and confirm that the job reaches `READY_FOR_REVIEW` only with `mechanicsValidation=PASSED`, `validatorVersion=mechanics-v3`, matching source hash, and report checks including `one-action-per-intent`, `range-min-max-step`, `range-input-change-order` and `source-differential` when a slider exists. Submit a fixture that changes a score/lane delta or CSS animation duration and confirm terminal `GAME_ADAPTER_MECHANICS_CHANGED`. A malformed manifest/runtime action or mechanics divergence is terminal (`FAILED`) and must not be automatically retried; OpenAI 429/5xx and unavailable Chromium are retryable. Existing rows without `mechanics-v3` must show `REVALIDATION_REQUIRED`; use the material editor revalidate action, which creates a new job from the original immutable asset without replacing the current block. Check validator failures with:

```bash
kubectl -n playsay-dev get pod -l app.kubernetes.io/name=game-adapter-service
kubectl -n playsay-dev logs deploy/game-adapter-service --since=15m | grep -E 'VALIDATION|RUNTIME_VALIDATOR|ACTION_RATE|GAME_MECHANICS_CHANGED|ACTION_CARDINALITY'
kubectl -n playsay-dev describe pod -l app.kubernetes.io/name=game-adapter-service | grep -E 'OOMKilled|Evicted|runtime-tmp'
```

If OpenAI or Chromium is unavailable, new adaptation jobs retry and then fail without affecting existing games. Do not stop the classroom, collaboration service, Docker, Amnezia, old VPS, or any public site as a recovery action. Existing `SDK_V1` and legacy fallback games continue to run because AI is never used during a lesson. Roll back the service through the infra Git commit/digest; an applied game adaptation is rolled back independently from the material editor, which restores the original immutable asset.

## AI Tutor Service

`ai-tutor-service` разворачивается ArgoCD из `helm-charts/ai-tutor-service` в `playsay-dev`. `web-app/nginx.conf` направляет `/api/ai-tutor/` на cluster service, поэтому отдельный публичный NodePort или host-nginx route не нужен.

Возрастная политика AI-разговора определяется только backend по `student_profile.birth_date`: `<13 = CHILD`, `13–17 = TEEN`, `18+ = ADULT`; non-student роли получают `ADULT`. Параметра `agePolicy` в запросах каталога и создания сессии нет. Если у `STUDENT` дата рождения не заполнена, ожидаем `409 Conflict`; сначала сохраните дату рождения через профиль SPA/API. `ai-tutor-service` читает `app_user` и `student_profile` через JPA entity/repository и не содержит прямых SQL-вызовов.

Keep `org.hibernate.orm.connections.pooling` at `WARN` for this service: the shared dev JDBC URI can contain connection parameters and must not be printed by Hibernate's startup database-info logger.

Перед включением живого голоса проверьте Secret `playsay-openai` с ключом `api-key`; значение нельзя выводить в логи. Dev chart включает `PLAYSAY_AI_TUTOR_REALTIME_PROVIDER=openai`, модель `gpt-realtime-2.1` и выполняет Liquibase при single-replica startup. Если Secret или provider недоступен, установите `openai.enabled=false`: каталог и сохранение сессий продолжат работать в явном stub-режиме.

Проверка после rollout:

```bash
kubectl -n playsay-dev rollout status deploy/ai-tutor-service
kubectl -n playsay-dev get svc ai-tutor-service
kubectl -n playsay-dev port-forward svc/ai-tutor-service 18087:80
curl -fsS http://127.0.0.1:18087/actuator/health
```

Production-допуск детских голосовых сессий блокируется до документированного родительского согласия, сроков удаления аудио и safety-eval свободных тем. AI-тренер не выполняет pronunciation scoring: неразборчивую реплику нужно запросить повторно без сохранения `TURN_EVALUATION`.

## Individual Lesson Push-to-Talk Translation

Перевод в live classroom работает только для `INDIVIDUAL` lesson с одним teacher и одним student и выключен для каждого ученика по умолчанию. До smoke основной преподаватель, активный замещающий преподаватель или администратор должен явно включить галку голосового перевода в карточке ученика. Без галки у teacher и student отсутствуют кнопка, статусы, captions, disclosure и связанные pointer/keyboard actions; frontend не вызывает translation API. После профильного разрешения обе стороны всё равно отдельно включают функцию внутри урока. Browser listener создаёт второй WebRTC connection к OpenAI Realtime Translation; source LiveKit microphone track подключается к нему, пока remote participant удерживает push-to-talk, и отключается после capture tail до 300 мс. Переведённый звук и последние три caption существуют только в браузере, backend их не сохраняет.

`api-gateway` выдаёт короткоживущие client secrets через authenticated `POST /api/schedule/lessons/{lessonId}/translation-session`. Постоянный provider key должен оставаться в существующем Secret `playsay-openai`, key `api-key`; не выводите его через `kubectl get secret`, shell history или логи. Dev values включают:

```yaml
lessonTranslation:
  enabled: true
  provider: openai
  model: gpt-realtime-translate
  baseUrl: https://api.openai.com/v1
  existingSecret: playsay-openai
  apiKeyKey: api-key
```

Chart передаёт в `api-gateway` `PLAYSAY_LESSON_TRANSLATION_ENABLED`, `PLAYSAY_LESSON_TRANSLATION_PROVIDER`, `PLAYSAY_LESSON_TRANSLATION_MODEL`, `PLAYSAY_LESSON_TRANSLATION_BASE_URL` и secret-backed `PLAYSAY_LESSON_TRANSLATION_API_KEY`. Перед classroom smoke проверьте только наличие Secret и rollout, не значение ключа:

```bash
kubectl -n playsay-dev get secret playsay-openai
kubectl -n playsay-dev rollout status deploy/api-gateway
kubectl -n playsay-dev logs deploy/api-gateway --since=10m | rg 'Lesson translation credential request failed|Started ApiGatewayApplication'
```

Smoke выполняется двумя authenticated браузерами в одном начавшемся individual lesson:

1. Оставьте профильную галку выключенной и войдите teacher и student. У обоих не должно быть кнопки, статусов, captions, disclosure или клавиатурного управления переводом; в Network не должно быть запросов к `translation-session`.
2. Проверьте backend guard: запрос `POST /api/schedule/lessons/{lessonId}/translation-session` от участника урока возвращает `409` с `LESSON_TRANSLATION_PERMISSION_REQUIRED`, а в backend-логах нет попытки запроса credential provider.
3. Основной преподаватель, активный замещающий преподаватель или администратор включает галку в карточке ученика. Обновите страницу classroom либо войдите заново в обоих браузерах; открытый без обновления room token не обязан менять UI.
4. Teacher и student отдельно включают перевод внутри урока. Teacher удерживает кнопку и student слышит `app_user.locale` (`ru`, `de` или `fr`), затем student удерживает кнопку и teacher слышит английский. Во время translated output исходный голос должен быть приглушён, после реплики — восстановлен. После refresh captions должны исчезнуть.
5. Снимите профильную галку. UI уже открытого classroom может оставаться до refresh/повторного входа, но новая попытка получить credentials должна сразу вернуть `409`; после обновления элементы перевода снова полностью отсутствуют.

Group lesson, неподдерживаемый locale и участник вне lesson должны получать явный отказ без отправки аудио provider.

Если provider недоступен или нужно быстро отключить контур, установите `lessonTranslation.enabled=false` и синхронизируйте ArgoCD. Это отключает только credential endpoint/translation control и не мешает основному LiveKit classroom. Не заменяйте этот rollback остановкой Docker, LiveKit, Amnezia или root site на `play-and-say.ru`.
