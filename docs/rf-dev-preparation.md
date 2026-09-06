# Regional dev preparation

This tracks preparation and the explicitly listed partial delivery evidence for `route-rf-users-via-selectel-geoip`. Production remains under the owner's delivery hold. Existing production signaling and media settings must not be disabled merely to recreate an older canary baseline.

## Environment mapping

| Public entry | Verified TLS upstream at AX41 | Owner |
| --- | --- | --- |
| dev.online.honeyschool.ru | dev.online.honey.school | playsay-dev web/API, /livekit and /collab/ws |
| dev.key.honeyschool.ru | dev.key.honey.school | playsay-dev keyboard |
| dev.ops.honey.school | dev.ops.honey.school | dev Keycloak playsay realm and resources only |
| dev.turn.honeyschool.ru | Separate dev coturn process on Selectel | Dev media only |

Public dev.ops DNS moves to Selectel only in the authorized delivery window. The canonical dev issuer stays `https://dev.ops.honey.school/keycloak/realms/playsay`. VPN split DNS continues to the existing private AX41 management edge; public admin/master endpoints stay denied. No dev.ops.ru issuer is introduced. Each new hostname requires its own validated certificate and renewal path before enabling TLS. Dev aliases belong only to dev clients, CORS, callbacks and WebSocket allowlists; production values remain unchanged.

Candidate dev TURN listeners are 3479 UDP/TCP and 5350 TLS/TCP; they were not listening on Selectel during the read-only inventory. Reserve a separate relay range only after verifying configured rules and allocations, not just listening sockets. Production retains 3478/5349 and 49152–49251. No dev media enablement before independent secret, certificate, service UID, firewall and allocation checks. The API's environment allowlist now reserves these dev endpoints; dev flags remain off.

Dev and production SFU share AX41's public address. A coturn IP allowlist alone therefore cannot isolate environments. The dev process needs its own UID and fail-closed egress rules restricted to the verified dev SFU destination ports (currently UDP 51000–51049); DNS/localhost and administrative surfaces must not become relay peers. The UID output policy allows only replies on its TURN listeners and relay UDP to that dev SFU range, then drops every other destination and protocol, including IPv6. TCP peer relaying is disabled; client TCP/TLS transport remains supported. Firewall replacement is atomic and stopping its unit retains the deny rules. Verify reply handling, reboot persistence and rejection of production ports with synthetic credentials before acceptance. This still shares the kernel and physical resources; intrusive tests during production lessons are prohibited. Nonstandard dev ports cannot certify production 3478/5349 reachability.

## Baseline and coordinated work (2026-09-04)

Clean working branches `codex/route-rf-users-via-selectel-geoip` start from platform develop `2acf8dccf2272f6022a99c3defb3c6e86b01497c` and infra develop `0767347ed3916adc1acdea045be04ab99d4cc9c0`. Production .08 source is `541bc558539e804ee597e044e9f87d0f977a83dc`, infra `e0d3be5cde3f8a04713f2a9c84b030565258b191`. Original dirty checkouts were preserved. No commit, push, CI trigger or remote mutation was performed in this preparation.

Signaling selection, Room identity, long-lived proxy locations and independent signaling/media binding already exist. `route-rf-classroom-signaling-through-selectel` was reconciled from combined full-off rollback to current plane-specific rollback. Its production response, real no-VPN, full-window and rollback tasks remain open. `restore-regional-media-routing-release-parity` tasks 5.1–5.4 remain open; relay tasks 8.8–8.11 and collaboration tasks 8.4–8.5/9.2–9.6 retain their own acceptance. The historical relay and signaling narratives classify different September 1 observations differently (TURN allocations versus signaling failures); without matching exact windows they must not be combined into one proven root cause. Functional RF dev results cannot close production tasks.

## Central log storage design

Inventory of dev/prod workloads found VictoriaMetrics/vmagent/vmalert/Alertmanager but no central log backend. Selectel runs nginx, coturn and rsyslog, without Vector/Alloy/Promtail/Fluent Bit. Metrics storage is not log storage.

The prepared first-stage backend is a single VictoriaLogs instance in the existing `playsay-dev` cluster. Its query UI is reachable only through the VPN-protected `dev.ops.honey.school/victoria-logs/` route. Ingestion uses `dev.ops.honey.school/victoria-logs/insert/`, accepts only the Selectel peer, and also requires HTTP Basic authentication. The deployment retains data for 7 days on a 10 GiB PVC and is limited to 512 MiB memory and 500m CPU. Production reliability does not depend on this dev instance. Retention by age is not a hard size quota, so rollout also checks free disk and ingestion rate.

The prepared Selectel agent is Fluent Bit with one sanitized HTTPS output, a 64 MiB filesystem queue, a 128 MiB service memory limit and 10% of one CPU. Vector was considered but its disk buffer minimum is 268435488 bytes, above this budget. The nginx parser keeps status and timing fields from the dedicated dev signaling log. The coturn filter converts selected lifecycle/errors into bounded categories and drops the raw journal message before output. The coturn input uses only a bounded memory buffer because Fluent Bit persists input chunks before filters; raw journal records must never use filesystem buffering. The 64 MiB filesystem queue applies to the dedicated privacy-safe nginx source. Normal authentication challenges are not classified as failures. No request URI, query, client IP, credential, SDP, candidate, room, lesson or participant identity enters the buffer.

Two different protected credentials are used and neither belongs in Git. AX41 nginx workers read the Basic-auth password hash (`root:www-data`, mode `0640`, parent directory `0710`) from `/etc/honeyschool/secrets/edge-log-ingest.htpasswd`. Fluent Bit on Selectel reads `EDGE_LOG_INGEST_USERNAME`/`EDGE_LOG_INGEST_PASSWORD` from `/etc/honeyschool/secrets/edge-log-ingest.env`. Ansible templates reference these paths but do not contain either value. The dev/prod VMs do not fetch these secrets: the Selectel agent posts directly through the public dev ops ingress, nginx authenticates it, and proxies accepted writes to VictoriaLogs in `playsay-dev`.

VictoriaLogs, AX41 dev ingest and the Selectel collector are delivered in dev with their independent flags enabled. The delivery created the two protected credential files, verified authenticated synthetic ingestion, and then enabled the bounded collector. Rollback disables the collector first and then the backend; the bounded local queue may be removed only after its safe contents are no longer needed.

Read-only snapshots: Selectel available memory 1645 MiB, free root space 21781 MiB, no swap; dev available memory 2253 MiB, free root space 48248 MiB, 56 MiB swap in use. These point-in-time values do not certify concurrency or sustained capacity. Use GitOps for the backend deployment and the separately reviewed RF dev path for edge changes.

Sources checked 2026-09-04:

- [VictoriaLogs retention](https://docs.victoriametrics.com/victorialogs/#retention)
- [Fluent Bit buffering](https://docs.fluentbit.io/manual/4.2/data-pipeline/buffering)
- [Vector HTTP disk buffer minimum](https://vector.dev/docs/reference/configuration/sinks/http/)

## GeoIP provisioning dependency

IPinfo Lite MMDB uses `country_code` and `asn`, supports verified IPv4/IPv6 fixtures and is licensed CC BY-SA 4.0 with attribution to [IPinfo](https://ipinfo.io/developers/ipinfo-lite-database). The protected token on AX41 is `/etc/honeyschool/secrets/ipinfo-lite-download-token` (root, `0600`). Actual authenticated download, reader lookups, normal systemd updates and last-good rollback have passed. Values and provider data are excluded from Git and command arguments.

Dev-only GeoIP entry and the daily timer are enabled through the dedicated exact-ref Ansible play; production entry remains disabled. Both controls and database rollback were exercised while a two-browser RF dev media session remained connected. [Acceptance and limitations](../migrations/ax41/evidence/20260906-dev-geoip-acceptance.md) distinguish actual MMDB/browser tests from the pending real RF no-VPN acceptance.

## Local verification

API routing tests: 25 passed, including actual YAML binding, dev/prod issuer and endpoint rejection, malformed origins, legacy compatibility and independent media rollback. API detektMain: zero findings. Both coordinated OpenSpec changes pass strict validation. These checks do not prove cross-environment JWT rejection at the deployed authentication boundary, secret independence, network isolation or no-VPN acceptance.

## Diagnostic implementation boundary

The browser currently reports ICE selection separately for publisher/subscriber, using only bounded transport classes and a nullable exact environment relay match. A missing candidate URL is unknown, not proof of RF routing. Subscriber media progress is now reported separately from ICE only when inbound bytes increase between samples; a missing/reset counter is unavailable. The on-demand panel now separates observed API/auth/signaling/collaboration connections, declared API policy, selected media relay and current inbound progress; observations older than 15 seconds are marked stale. The local summary keeps at most 50 events in sessionStorage; diagnostic HTTP failure never clears authentication or interrupts media. The authenticated gateway accepts enum fields, UUID and a nullable boolean and rate-limits each subject to 120 events/minute with bounded in-memory tracking. The panel displays the bounded local event summary; centralized evidence is queried through the protected log backend. Server correlation IDs are isolated per authenticated subject and expire 15 minutes after the first event without sliding renewal; unknown request fields are rejected.

Collector acceptance must inspect Fluent Bit input/output/drop/retry counters through its loopback port 2020 and compare them with a known synthetic event. An empty log query alone proves neither source health nor absence of errors. Verify normal coturn 401/438 challenges as `authentication_challenge`, authenticated ingest rejection, backlog growth and recovery, volume headroom and configured service limits before enabling collection for lesson diagnostics.

## Isolated ingress delivery

RF dev ingress is rendered into `/etc/nginx/conf.d/honey-school-rf-dev.conf` through `honey-school-dev-ingress`. It reuses the existing upgrade map and declares its own privacy-safe signaling format before its virtual hosts and does not rewrite the production virtual-host file, landing, firewall, packages, coturn or logging services. Bootstrap installs only HTTP ACME challenge handlers and returns 404 for other HTTP requests. The existing registered ACME account issues independent dev certificates after DNS is authoritative; HTTPS enablement then uses `ingress-check` and `ingress-apply`. Each apply validates the whole nginx configuration before graceful reload and restores the prior dev file on failure.

From a clean exact committed checkout, use `scripts/apply-rf-edge-dev-release.sh COMMIT bootstrap-check INVENTORY` before `bootstrap-apply`; after certificates exist, use `ingress-check` before `ingress-apply`. These modes select only `rf-dev-ingress`; host/environment assertions always run. The full `check/apply` modes additionally include independent media/log roles and are not required for initial ingress setup.

## 2026-09-05 HTTP bootstrap evidence

Infra commit `88e14db` was pushed to the topic branch and applied with the exact-ref wrapper in `bootstrap-apply` mode from the trusted workstation. The preflight reported production participant count 0. Check mode showed only the new `/etc/nginx/conf.d/honey-school-rf-dev.conf`; apply reported `failed=0`, full `nginx -t` passed and nginx was gracefully reloaded. The production virtual-host file, coturn, firewall and application workloads were not part of the play. Forced dev Host HTTP returns expected 404 until certificates enable HTTPS; production online still returns 200. DNS A records for dev.online/dev.key on the RF domain and independent dev certificates are absent. REG.RU browser session is not authenticated; owner sign-in is required before DNS work can proceed. This is not HTTPS, OIDC, TURN or lesson acceptance.

## 2026-09-05 certificate and HTTPS preparation

REG.RU dev.online/dev.key/dev.turn and Dynadot dev.ops now resolve to Selectel. Independent certificates for dev.online.honeyschool.ru, dev.key.honeyschool.ru and dev.ops.honey.school were issued with the existing ACME account and webroot; all expire 2026-12-04. Initial issuance uses `--no-directory-hooks` to avoid executing unrelated production TURN certificate hooks. Private keys remain on Selectel.

The first HTTPS apply at `527e877` failed whole-config validation because the dev file is loaded before the production signaling log format declaration. The role restored the HTTP bootstrap file without reload. Dev rendering now declares its own format before use; this preserves the production configuration and removes the file-order dependency.

## 2026-09-05 isolated HTTPS delivery

Infra `1c7403a0715e1d3d29a097bb1bdad6458b033021` passed reviewed ingress-check and ingress-apply after a fresh production participant count of zero. Whole nginx validation passed, apply changed only the dev file and gracefully reloaded nginx (`changed=2`, `failed=0`); the repeat check returned `changed=0`. No production configuration or coturn was changed.

Forced Selectel TLS 1.2 full-transfer checks returned dev online HTML 1467 bytes, JavaScript 1127675 + 374719 bytes and CSS 283538 bytes; dev keyboard HTML 1381 bytes, JavaScript 377414 bytes and CSS 66755 bytes. Public OIDC discovery retains the exact dev issuer. Public root, admin, master realm and log query paths return 404. These checks prove ingress only, not authenticated callback or media acceptance.

The prepared VictoriaLogs NodePort is 32089 (verified unused in dev), distinct from collaboration's 32086; the AX41 upstream matches. Both ingress hops allow a bounded 4 MiB ingestion request, avoiding an RF-only 256 KiB rejection of collector batches. Backend/collector enablement remains coordinated and pending.

Dev client alias provisioning uses `scripts/configure-keycloak-dev-rf-aliases.sh` on playsay-dev with the local k3s kubeconfig. It refuses another host, realm, client or Keycloak server; only unions the two dev RF callbacks/origins/logout entries into the existing client. It preserves user accounts and realm settings. Admin credentials travel over stdin to the pod, never command arguments on the control node; the temporary kcadm session is removed on exit. Run the script from the exact delivered infra revision and verify public PKCE authorization for each alias afterward.

Provision dev-only ingestion authentication from the trusted workstation using `python3 scripts/provision-dev-edge-log-credentials.py --ssh-key /protected/key/path`. It creates the Selectel environment file first, sends only a bcrypt password hash to AX41, refuses rotation and can complete a interrupted second-host write. It suppresses credential and subprocess output on failure. Existing-file success is not authentication verification; test the real ingest endpoint separately.

The independent `ansible/playbooks/ax41-dev-log-ingress.yaml` reconciles only a marked dev HTTPS log block in the existing AX41 file, using the same location template as the full edge role. It refuses host/upstream/peer drift and requires the protected hash before enabling ingress. Run syntax/check from the exact clean pushed revision, review the diff, obtain a fresh zero-participant window, then apply and repeat check. It validates all nginx virtual hosts before graceful reload and restores the prior file on error; it neither applies the full AX41 host role nor rewrites production virtual hosts. Desired dev log ingress is enabled after storage/secret provisioning; Selectel collection remains disabled until authenticated synthetic ingestion succeeds.

After storage and authenticated ingestion verification, collector delivery uses the exact-ref wrapper's `logs-check` and `logs-apply` modes, selecting only `rf-dev-logs`. Package installation suppresses automatic service startup; the protected configuration is dry-run validated before the bounded service starts. AX41 ingest requires only the worker-readable hash; the plaintext Selectel environment file remains root:root 0600. Synthetic intake verified rejection without credentials (401) and acceptance with credentials (200) after correcting worker access to the hash.

On a fresh host, APT check mode cannot resolve Fluent Bit until its repository metadata exists. The reviewed `logs-packages-apply` phase installs only the prerequisites/repository/package with service autostart suppressed. Then `logs-check` must review configuration and resource limits before `logs-apply` can start the collector. A failed initial package check is not evidence of validated runtime configuration.

## 2026-09-05 central log delivery evidence

Dev storage revision `ea1127746887dc62119d64bdf5c96b47c6a07008` is on develop; ArgoCD monitoring-lite is Synced/Healthy, the VictoriaLogs pod is 1/1 Running with zero restarts, and its private health endpoint returns OK. The scoped AX41 ingress apply passed whole-config validation and changed only the marked dev location block plus graceful reload, after production participants were independently verified zero.

Selectel collector exact revision `7ef9aad9cb6b616a7175c62df8c9fb142c9e9969` was applied through logs-packages-apply/check/apply. Installed Fluent Bit is v5.1.2. Configuration dry-run passed, service is active, observed MemoryCurrent was 5607424 bytes, MemoryMax 134217728 bytes and CPUQuotaPerSecUSec 100ms. Repeat logs-check reports changed=0. A known pair of safe signaling requests produced input records=2 and output proc_records=2; errors, retries, retries_failed and dropped_records all remained zero. VictoriaLogs independently returned count=2 for environment=dev/source=nginx_signaling/event=signaling_request. One synthetic authenticated ingest record is also present; unauthenticated ingest returns 401.

At the initial collector delivery dev TURN was not provisioned; the initial input records=0 was unavailable source evidence. The later dev TURN delivery and allocation results are recorded below. Backpressure/recovery, TURN lifecycle filtering, continuous source/drop metrics, full diagnostic UI, GeoIP dataset and real two-user media acceptance remain open. No production rollout occurred.

The committed `test-edge-log-runtime.py` ran against installed Fluent Bit and its installed privacy filter, with an isolated loopback-only receiver and synthetic input. It recovered from two HTTP 503 responses, classified the normal 401 challenge as expected, emitted only the field allowlist and found no raw synthetic private value in the disk buffer. The probe stopped its own process and removed only its temporary files. Production/backend endpoints and the working collector were not stopped for this test. Continuous aggregation/panels remain separate follow-up work.

Dev media delivery uses the exact-ref wrapper `media-check` and `media-apply` modes, selecting only `rf-dev-media`. On a fresh host, run `media-bootstrap-apply` to prepare only installed packages and the unprivileged account before checking UID-based firewall rules; this phase starts no dev service. Provision the independent secret with `scripts/provision-dev-turn-credentials.py --ssh-key /absolute/path/to/key`; it refuses mismatched existing values and never rotates them. The root-only Selectel file and the dev api-gateway `rf-media-relay-auth` Secret contain matching independent values. No production Secret is accessed. Issue a separate `dev.turn.honeyschool.ru` ACME certificate before the media check. Routing flags remain off until real allocation and environment-isolation checks pass.

The dev certificate deploy hook matches only its exact ACME lineage, refreshes dev-readable copies and writes `/run/honey-school-dev-turn-certificate-reload-required`. It never restarts a relay automatically. Consume that marker only after confirming zero dev allocations, restart only `honey-school-dev-turn`, then repeat TLS allocation before removing the marker.

## 2026-09-05 dev TURN provisioning

Exact revision `55a96deca86de3eedba66f50b0deada10fa82ad2` provisioned the independent dev process after zero participants in both environments. The media-only apply succeeded and repeat check reported changed=0. The independent ACME certificate expires 2026-12-04. Protected secret comparison passed; no production secret was read or rotated. Observed dev service memory was 4567040 bytes, NRestarts=0; nginx and production coturn remained active.

`check-dev-turn-allocations.py` runs as root on Selectel and prints only bounded outcomes. UDP, TCP and certificate-validated TLS rejected invalid authentication, allocated within the dev relay range and accepted explicit allocation release. Each allocation requests a 30-second lifetime as cleanup protection. These edge-local checks do not prove an external RF browser or bidirectional SFU media. Runtime inspection found coturn's default DTLS UDP listener on 5350; the candidate explicitly disables DTLS to retain the declared listener set before media enablement.

The GeoIP role preserves root:www-data 0710 on the shared AX41 secret directory so nginx can traverse to its 0640 ingest hash. The provider token itself stays root:root 0600; workers cannot read it. Dev TURN final listener correction at `e1ed3f0` was delivered without a production restart; UDP/TCP/TLS allocation checks passed again and only declared listeners remain. Three UID egress probes were denied by nftables: production SFU port, unrelated peer and local administrative port. This is an environment-isolation check, not end-to-end media evidence.

The isolated `test-geoip-nginx-runtime.py` probe passed 18 cases against real nginx: cold/explicit navigation, IPv4/IPv6, RU/non-RU/unknown, spoofed client headers, trusted proxy with a direct upstream Host, environment/ops/RF-host exclusion, method/API/auth/WebSocket exclusions, preserved query and private no-store redirect headers. It uses synthetic country classification and a separate loopback process; it neither reloads the live nginx nor verifies the IPinfo MMDB.

Full RF dev check at `faccf72f340788eba5c6faec3c2cc4235202d7b2` completed with changed=0 across ingress, dev relay and collector. The dev log ingress body limit is now 4 MiB at both edges, aligned with bounded collector flushes. Shared nginx reload passed validation in a zero-participant window; production settings were not changed.

Central storage received dev TURN events after the probes. The first startup also exposed coturn attempting to open the production-default SQLite path under its isolated UID. The dev unit now declares its own ephemeral runtime directory and SQLite path; the static REST credential remains in its protected configuration. The production database is never opened or reused.

The AX41 candidate now normalizes forwarded client IP: direct requests use their TCP peer, only the fixed RF peer may supply the browser X-Real-IP, and an absent RF header falls back to the peer. `$remote_addr` is never rewritten, preserving proxy identity for access controls and loop prevention. The isolated nginx probe passed 19 cases, including normalized IPv6 forwarding with unchanged proxy peer and rejection of spoofed headers. This main AX41 template change remains prepared, not delivered under the production hold.

Default coturn verbosity does not emit allocation lifecycle records. Dev coturn enables its normal verbose lifecycle output (not extra-verbose packet tracing), and the collector recognizes the installed coturn ALLOCATE success and final session-close forms. Raw journal input remains memory-only and is replaced by the strict event allowlist before output. Lifecycle event counts are diagnostic events, not authoritative active-allocation gauges.

At final lifecycle revision `2c2e43450a44b29a0c2a4c9e8e7dad894ce9f700`, full RF dev check returned changed=0 after apply. The current dev coturn invocation has no SQLite startup error. A three-transport probe produced exactly three allocation-created, three allocation-closed and six expected authentication-challenge records in VictoriaLogs. Earlier two SQLite errors remain historical records; negative credential probes are likewise intentional test evidence.

Browser checks exercised real application login/callback/sign-out on RF dev (teacher, desktop 1440 px) and direct dev (student, mobile 390 px). Both returned to the same origin after sign-out, removed browser tokens, and had no horizontal overflow. An independent teacher/student PKCE and authenticated-profile check through RF dev also passed. These are developer-network checks, not RF last-mile no-VPN acceptance.

## 2026-09-05 dev application routing delivery

API Jenkins #159 and web #299 succeeded from platform `4be2794e5e191becca14bf5f13583b2626ea6332`; registration #64 and keyboard #93 had already succeeded. API #158 completed tests and the additive migration but refused its deploy stage when source HEAD changed; #159 reran against a frozen branch, retaining the standard HEAD guard.

Infra develop `283de85b27378373ccdbd8e64796a590e68a295f` preserves the latest Jenkins image references and enables only dev RF signaling, media, collaboration and callback origin. Actual Helm prod/dev/rollback binding tests pass. API, registration and web report Synced/Healthy. The main AX41 GeoIP configuration remains undelivered and redirects disabled. Authenticated room-token checks confirm the direct dev baseline, exact RF dev relay policy, stable room identity and no production endpoint selected for a foreign production Origin. Full browser media testing is still in progress.

The running dev API image is `ghcr.io/mednov-ai/playsay-api-gateway@sha256:baeed3057c49b671a582af10d7bbc41c3d36f494641548b6ebc59b5f3e0a0d87`, Ready with no rollout failure. Independent synthetic audio probing identified a test Chromium requirement for `--use-fake-ui-for-media-stream`; explicit context permissions alone returned NotSupportedError. The corrected test reaches both classroom sessions; this test-harness issue does not justify an application audio change.

A direct-dev two-browser comparison passes local/remote video, received audio and collaboration. RF dev WSS carries messages both directions; the client fails PC connection while DTLS stays connecting. Dev coturn reports EPERM sends, and its deny counter grows. A bounded dev-process syscall trace with payload strings disabled identifies only AX41 destinations outside 51000–51049 (ephemeral ports), matching libvirt MASQUERADE's 1024–65535 rewrite. The candidate therefore preserves exact dev SFU source ports toward Selectel in an independent priority-99 SNAT table; no production destinations are opened on dev TURN.

Dev-only SNAT revision `d0a6a44` applied successfully on AX41 and repeat check returned changed=0. Capture then showed additional rewritten ports already arriving from the guest. Dev LiveKit was gathering across the CNI/Flannel interfaces as well as the VM uplink. GitOps revision `1b09fcbe8899c6062dd9735fcc55d5e51ead017e` restricts dev RTC interfaces to `enp1s0`; LiveKit is Synced/Healthy.

After both fixes, the two-browser RF dev functional test passed: exact relay URL and relay-only configuration for every active browser PeerConnection, inbound/outbound RTP, local/remote video, received audio, collaboration presence, synthetic screen share, visible bounded preview with no recursive video, stop and student reload/rejoin. HTTP/WebSocket requests stayed on dev hosts. This is a developer-network synthetic-media test, not RF last-mile or 45-minute production acceptance. Current LiveKit supports one connection carrying both flows; observations must not count it as two separate connections. Concurrent dev vocabulary delivery replaced the prior web image with web-dev-302; full diagnostic UI rollout must therefore use a merged source retaining those fixes.

Scoped browser-only TCP and TLS transport probes subsequently passed the same complete two-user functional scenario. The probes filter only the test browser room-token ICE URL list to one server-provided dev endpoint; credentials, relay-only policy and server identity are unchanged. Native stats verify the selected exact TCP/TLS URL and both RTP directions. Production-SFU, unrelated-peer and local-admin negative egress probes still return EPERM from a real dev relay-range socket. These are not real-RF-ISP or production-port acceptance.

## Earlier shared-PC dev verification, 2026-09-05

Web Jenkins #304 succeeded from merged platform `0eb849eae3dab7c2df0346add5c0b7378ed025c4`, preserving the develop vocabulary fixes and adding shared-PC flow diagnostics. Its digest is `sha256:7065ffbf2606c85cd22c7a84eb17bc78d2f219f80dfbb47d9a3a597241017c9f`; GitOps revision `b0997b238f3c53a4a8e1aa62bb8acfbd2ec8574b` is Synced/Healthy. The standard UI gate used its configured second attempt after a content-bound geometry assertion; homework passed its first attempt. Seven focused media/probe tests and TypeScript also pass.

The final RF-dev browser run passed built-in PUBLISHER/SUBSCRIBER flow evidence in shared-PC mode, actual inbound/outbound RTP, three consecutive 20-second media checks, bounded synthetic screen share, stop and student rejoin. Teacher WSS remained open 93 seconds; the student's first WSS closed at the intentional reload after 70 seconds. No unexpected reconnect marker appeared. A scoped HTTP-503 diagnostic-endpoint failure was actually exercised; local MEDIA/SUCCESS evidence and lesson media recovered after reload. This is bounded functional evidence, not the planned long-duration/no-VPN RF acceptance.

Dev TURN and Fluent Bit remained active with NRestarts=0 and observed memory peaks below 7 MiB each. After the network corrections the dev deny counter stopped increasing on valid media; three explicit forbidden-destination probes still failed with EPERM. IPinfo protected download token remains absent. Automatic GeoIP redirects and this change's production rollout remain unperformed. The user-requested keyboard route panel is tracked separately as task 4.7 and is not implemented by the shared-PC diagnostic fix.

## TURN parity audit, 2026-09-05

Read-only comparison of running Selectel configurations confirms identical REST shared-secret authentication mode, total/user quotas 8/4, stale nonce 600 seconds, multicast/loopback/CLI restrictions and TLS 1.0/1.1 disablement. Both coturn services have zero restarts. Separate secrets and certificates are intentional environment isolation.

| Setting | Dev | Production | Acceptance implication |
| --- | --- | --- | --- |
| Client UDP/TCP | 3479 | 3478 | Same offered protocol, different network reachability gate |
| Client TLS/TCP | 5350 | 5349 | Same offered protocol, different network reachability gate |
| Relay UDP range | 49300–49399 | 49152–49251 | Independent allocations; both 100 ports |
| TCP peer relaying | Disabled | Not explicitly disabled | Dev isolates peers; client TURN/TCP still works |
| DTLS | Disabled | Not explicitly disabled | DTLS is not an offered dev acceptance transport |
| Lifecycle verbose | Enabled | Not enabled | Dev collector has independent resource/privacy limits |

Do not remove dev isolation to achieve text-identical configuration. Dev UDP/TCP/TLS browser evidence validates the offered transport semantics, not production ports, credentials, ISP filtering or concurrency. Promotion must carry the tested application/configuration changes and explicitly recheck the production-specific differences in an authorized canary. The IPinfo protected token was rechecked and remains absent; real provider DB download and automatic geographic entry cannot be certified.

The repeat policy gate passed all 19 isolated real-nginx cases (cold navigation, synthetic IPv4/IPv6 RU/non-RU/unknown classification, trusted hop and spoofed headers, cache isolation, route/host/environment exclusions and loop avoidance). GeoIP/updater, RF dev isolation and edge collector contract suites passed. This closes navigation-policy verification only; provider MMDB access remains a separate missing prerequisite.

Production promotion candidate now also sets `rtc.interfaces.includes: [enp1s0]`, the same uplink-only gathering behavior verified on dev. Read-only production VM inspection confirmed that uplink name. This is a feature-branch candidate only, not a production apply or acceptance. Keep production's existing ports, resource profile, batch IO and credentials. The extra dev-only source-port SNAT remains scoped to the strict dev TURN egress firewall; do not blindly copy dev IP/port mappings into production. A numeric release must include this candidate chart value together with the tested chart template and web/API source.

The read-only parity gate is now reproducible with `scripts/audit-rf-turn-parity.py`; all checks passed, including independent nonempty REST secrets and distinct certificate references (values never emitted). Source review also confirmed that retired student-invite endpoints return LESSON_LINK_REPLACED. Current reusable lesson links provide both allowlisted origins with RF copy default, continuation preserves the validated attempt origin through LessonAccessOriginPolicy, and reminder/reschedule URLs use the recipient RF/AUTO preference through the same policy. Existing origin, reminder and lesson-access regressions passed in the accepted API dev build; no sender-IP inference or token/signature migration was added.

## Connection panel delivery and extended dev acceptance

Current panel, four-origin isolated browser checks, actual dev authentication, TURN parity and collector rollback evidence is recorded in [the connection diagnostics acceptance](../migrations/ax41/evidence/20260905-rf-dev-connection-diagnostics.md). This supersedes the earlier statement that task 4.7 is unimplemented. Production runtime and real RF ISP/no-VPN acceptance remain separate gates.
