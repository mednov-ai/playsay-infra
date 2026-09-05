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

Dev and production SFU share AX41's public address. A coturn IP allowlist alone therefore cannot isolate environments. The dev process needs its own UID and fail-closed egress rules restricted to the verified dev SFU destination ports (currently UDP 51000–51049); DNS/localhost and administrative surfaces must not become relay peers. Verify reply handling, reboot persistence and rejection of production ports with synthetic credentials before acceptance. This still shares the kernel and physical resources; intrusive tests during production lessons are prohibited. Nonstandard dev ports cannot certify production 3478/5349 reachability.

## Baseline and coordinated work (2026-09-04)

Clean working branches `codex/route-rf-users-via-selectel-geoip` start from platform develop `2acf8dccf2272f6022a99c3defb3c6e86b01497c` and infra develop `0767347ed3916adc1acdea045be04ab99d4cc9c0`. Production .08 source is `541bc558539e804ee597e044e9f87d0f977a83dc`, infra `e0d3be5cde3f8a04713f2a9c84b030565258b191`. Original dirty checkouts were preserved. No commit, push, CI trigger or remote mutation was performed in this preparation.

Signaling selection, Room identity, long-lived proxy locations and independent signaling/media binding already exist. `route-rf-classroom-signaling-through-selectel` was reconciled from combined full-off rollback to current plane-specific rollback. Its production response, real no-VPN, full-window and rollback tasks remain open. `restore-regional-media-routing-release-parity` tasks 5.1–5.4 remain open; relay tasks 8.8–8.11 and collaboration tasks 8.4–8.5/9.2–9.6 retain their own acceptance. The historical relay and signaling narratives classify different September 1 observations differently (TURN allocations versus signaling failures); without matching exact windows they must not be combined into one proven root cause. Functional RF dev results cannot close production tasks.

## Central log storage design

Inventory of dev/prod workloads found VictoriaMetrics/vmagent/vmalert/Alertmanager but no central log backend. Selectel runs nginx, coturn and rsyslog, without Vector/Alloy/Promtail/Fluent Bit. Metrics storage is not log storage.

The prepared first-stage backend is a single VictoriaLogs instance in the existing `playsay-dev` cluster. Its query UI is reachable only through the VPN-protected `dev.ops.honey.school/victoria-logs/` route. Ingestion uses `dev.ops.honey.school/victoria-logs/insert/`, accepts only the Selectel peer, and also requires HTTP Basic authentication. The deployment retains data for 7 days on a 10 GiB PVC and is limited to 512 MiB memory and 500m CPU. Production reliability does not depend on this dev instance. Retention by age is not a hard size quota, so rollout also checks free disk and ingestion rate.

The prepared Selectel agent is Fluent Bit with one sanitized HTTPS output, a 64 MiB filesystem queue, a 128 MiB service memory limit and 10% of one CPU. Vector was considered but its disk buffer minimum is 268435488 bytes, above this budget. The nginx parser keeps status and timing fields from the dedicated dev signaling log. The coturn filter converts selected lifecycle/errors into bounded categories and drops the raw journal message before output. The coturn input uses only a bounded memory buffer because Fluent Bit persists input chunks before filters; raw journal records must never use filesystem buffering. The 64 MiB filesystem queue applies to the dedicated privacy-safe nginx source. Normal authentication challenges are not classified as failures. No request URI, query, client IP, credential, SDP, candidate, room, lesson or participant identity enters the buffer.

Two different protected credentials are used and neither belongs in Git. AX41 nginx workers read the Basic-auth password hash (`root:www-data`, mode `0640`, parent directory `0710`) from `/etc/honeyschool/secrets/edge-log-ingest.htpasswd`. Fluent Bit on Selectel reads `EDGE_LOG_INGEST_USERNAME`/`EDGE_LOG_INGEST_PASSWORD` from `/etc/honeyschool/secrets/edge-log-ingest.env`. Ansible templates reference these paths but do not contain either value. The dev/prod VMs do not fetch these secrets: the Selectel agent posts directly through the public dev ops ingress, nginx authenticates it, and proxies accepted writes to VictoriaLogs in `playsay-dev`.

The checked-in configuration remains dormant: `victoria_logs_enabled: false` on AX41 and `honey_school_edge_logs_enabled: false` on Selectel. Coordinated dev delivery creates both secrets first, deploys VictoriaLogs, validates the authenticated ingestion path, and only then enables the edge collector. Rollback disables the collector first and then the backend; the bounded local queue may be removed only after its safe contents are no longer needed.

Read-only snapshots: Selectel available memory 1645 MiB, free root space 21781 MiB, no swap; dev available memory 2253 MiB, free root space 48248 MiB, 56 MiB swap in use. These point-in-time values do not certify concurrency or sustained capacity. Use GitOps for the backend deployment and the separately reviewed RF dev path for edge changes.

Sources checked 2026-09-04:

- [VictoriaLogs retention](https://docs.victoriametrics.com/victorialogs/#retention)
- [Fluent Bit buffering](https://docs.fluentbit.io/manual/4.2/data-pipeline/buffering)
- [Vector HTTP disk buffer minimum](https://vector.dev/docs/reference/configuration/sinks/http/)

## GeoIP provisioning dependency

IPinfo Lite MMDB uses `country_code` and `asn`, not the old `country_asn` schema or MaxMind `country.iso_code`. Data is licensed CC BY-SA 4.0 with attribution to [IPinfo](https://ipinfo.io/developers/ipinfo-lite-database). No IPinfo secret reference was found in the checked-in infrastructure. Download entitlement and actual IPv4/IPv6 database verification remain open. The proposed AX41 token path was checked read-only and is absent.

Protected token reference on the AX41 physical host: `/etc/honeyschool/secrets/ipinfo-lite-download-token`, root-owned mode 0600, provisioned through the owner's protected secret workflow. Do not put the token into chat, Git, shell command arguments or logs. No download with account credentials has been attempted and no provider data has been committed.

## Local verification

API routing tests: 25 passed, including actual YAML binding, dev/prod issuer and endpoint rejection, malformed origins, legacy compatibility and independent media rollback. API detektMain: zero findings. Both coordinated OpenSpec changes pass strict validation. These checks do not prove cross-environment JWT rejection at the deployed authentication boundary, secret independence, network isolation or no-VPN acceptance.

## Diagnostic implementation boundary

The browser currently reports ICE selection separately for publisher/subscriber, using only bounded transport classes and a nullable exact environment relay match. A missing candidate URL is unknown, not proof of RF routing. This does not yet prove received media or cover the complete entry/auth/policy/signaling chain. The local summary keeps at most 50 events in sessionStorage; diagnostic HTTP failure never clears authentication or interrupts media. The authenticated gateway accepts enum fields, UUID and a nullable boolean and rate-limits each subject to 120 events/minute with bounded in-memory tracking. The full timeline UI and full diagnostic timeline remains open. Server correlation IDs are isolated per authenticated subject and expire 15 minutes after the first event without sliding renewal; unknown request fields are rejected.

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
