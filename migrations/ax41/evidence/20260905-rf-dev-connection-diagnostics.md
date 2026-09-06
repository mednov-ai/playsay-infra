# RF dev connection diagnostics and TURN parity

This evidence is limited to authorized dev delivery and read-only production configuration comparison. It does not approve production rollout, actual RF ISP/no-VPN reachability, a 45-minute production lesson, or higher concurrency.

## Source and delivery

- Web #305, source `803a12f1f9e5e4432e23cba70814a97325ccc4d9`: local keyboard/button panel; Jenkins all stages passed.
- Web #306, source `c219e2e8423fbab13844ffbb5430b23d454519b4`: separate API policy and current inbound RTP progress; Jenkins all stages passed, dev GitOps `5128b00`.
- Web #307, source `e7abc3bc056b37297e230185c830312098de467a`: localized IPinfo attribution; Jenkins all stages passed.
- Final source `a1239aaeae05d26d3e1b9904ec6c14ee4bc8e1ef` adds observation of generated clients before authentication, without consuming response bodies or changing native errors. Jenkins web #308 passed all stages, including UI smoke. Dev GitOps revision `c5d6cdb` pins digest `sha256:1d96999f6f03f43eac244f55de970aef979ff8c2d6aa78fb356051a43a844bfc`; all 21 dev ArgoCD applications were Synced/Healthy after delivery.
- API code and contracts have no diff from the accepted API #159 source `4be2794e5e191becca14bf5f13583b2626ea6332`; this increment does not require a backend rebuild or migration.

## Browser evidence

Local verification passed 681 frontend tests, TypeScript, lint and build. The observation tests verify exact Response identity, unread body, preserved rejection identity, separate telemetry failures, public-host-only retention, API-policy/observed-media separation, disconnect invalidation and exact physical-key shortcuts outside editable fields/IME/repeats.

A 16-case isolated browser matrix covered direct/RF dev/production origins and ru/en/de/fr. It made no production requests. Native dialog opening, Escape, macOS shortcut, mobile width and dark surfaces were also inspected. Production runtime remains unverified.

Four actual UI login/callback/logout cases passed on #308: teacher and student on each direct/RF dev origin. The physical macOS shortcut opened/closed the panel, auth and generated API responses were observed, IPinfo attribution was present, logout returned to the same origin, and desktop/mobile pages had no horizontal overflow. The harness waits for the asynchronous API response before asserting its observation.

Two disposable teacher/student browser lessons passed on #305 and #306. #306 additionally exercised actual mobile dark diagnostics, API policy, current received-media indication, and a route preference change while the lesson stayed active. The original preference was restored using current profile values. Each lesson verified:

- authenticated dev-only entry, stable room across direct/RF policy requests and rejection of a production-origin route selection;
- playable audio/video, shared collaboration presence and exact dev TURN relay matching from native RTC stats, with inbound and outbound RTP in shared-PC mode;
- 15 successive 20-second intervals of increasing inbound RTP with no connection-state departure from connected;
- one received screen-share cycle, bounded local mirror preview and stop;
- intentional student reload followed by restored video/collaboration;
- actual intercepted HTTP 503 diagnostic intake while local events and received media remained available;
- cleanup of only the created lesson/material fixtures.

On #306 the teacher signaling socket lasted 336.317 seconds; the student's first socket lasted 313.214 seconds before the intentional reload, followed by 9.167 seconds before cleanup. These observed closures were planned. This is developer-network browser evidence with synthetic media, not a real pupil's RF ISP acceptance.

## TURN parity and isolation

The checked-in read-only `scripts/audit-rf-turn-parity.py` passed on actual Selectel configuration. REST-auth mode, quotas 8/4, nonce lifetime and baseline TLS/security restrictions agree; secrets and certificate references are independently nonempty/distinct. No secret values or derived values are emitted.

The actual `check-dev-turn-allocations.py` probe passed UDP, TCP and TLS: invalid credentials and credentials derived from the production REST key were rejected on dev, while the dev credential allocated only within 49300–49399 and released successfully. This probe did not allocate on production.

Intentional differences remain: dev listeners 3479/5350 versus production 3478/5349, independent relay ranges, no dev TCP peer relay/DTLS, and dev lifecycle verbosity. Client TURN/TCP and TURN/TLS remain supported. See `docs/rf-dev-preparation.md` for the complete mapping.

The production promotion candidate includes the same `enp1s0` RTC interface filter tested on dev, after read-only confirmation of that uplink on the production VM. Both Helm renders pass. Production ports, resources and batch IO remain environment-specific. The candidate was not applied to production; dev-only SNAT mappings must not be blindly copied into prod.

## Collector rollback and resources

With both participant metrics positively equal to zero, exact-ref `logs-check`/`logs-apply` stopped only Fluent Bit at `1f5c32ab7364896f8a8a5f7b325f05b8030e8925`, then restored it at `8985cb4e2c453af099ad9fd05ce86dae622e33c0`. Each apply changed one service state. Final check reported `changed=0`. nginx and both TURN services retained identical activation timestamps and restart counts. A private VictoriaLogs query observed 14 sanitized dev events in the recent two-minute window after restoration.

During the #306 lesson, 26 shared-edge samples from 20:36:40Z to 20:43:17Z recorded maximum CPU 43.881%, minimum available memory 1556 MiB, maximum RX 6.658 Mbps/TX 5.807 Mbps, zero swap/OOM/UDP error increments and no nginx/production-coturn outage or restart. The existing resource collector's allocation counter belongs to production coturn: its zero is not dev allocation evidence. Dev media evidence comes from the browser and separate dev allocation checks.

## Extended-window investigation

The first #308 dev lesson was sampled every 20 seconds, with a separate 15-second shared-edge resource collector. Four real UI login cases completed before this window. Early server histogram observations showed RTT p95 above 300 ms and later jitter p95 above 50 ms despite continuous RTP. After 64 successful intervals, both browsers logged signaling ping timeout and resume failures, then the media stability assertion failed. This did not complete the planned 45-minute gate. Own fixture cleanup was independently verified through the API: lesson HTTP 404 and material ARCHIVED. No 45-minute success is claimed for this run.

Read-only investigation found approximately 100 ms ICMP RTT from the test workstation to Selectel and 15 ms from the dev VM to Selectel; these are supplementary path measurements, not WebRTC quality evidence. LiveKit used approximately 50m CPU/95 MiB at the sampled instant. Its cgroup throttling counters did not increase across the subsequent sample interval, and memory pressure/OOM counters were zero; dev TURN reported zero throttling. Early Fluent Bit counters showed 44 sanitized output records and zero output errors/retries/failed retries/drops. Input/output totals differ because the privacy filter intentionally removes unrelated journal records.

TURN journal evidence shows successful 600-second allocation refreshes at 21:30:11Z and 21:30:18Z, after normal 438 nonce challenges; allocations were released at cleanup, so expiry is not established as the cause of the first signaling failure. Both nginx hops recorded the two long 101 sessions closing together, approximately 1240/1247 seconds after upgrade; their journals/error logs showed no restart/reload/upstream error during the inspected interval. Browser socket-event lifetime measurements were approximately 1268/1266 seconds. Server close reasons after the failure/cleanup included CLIENT_REQUEST_LEAVE and PEER_CONNECTION_DISCONNECTED, not SIGNAL_SOURCE_CLOSE or DUPLICATE_IDENTITY.

The second unchanged-config run passed all 135 successive 20-second intervals (45 minutes) with increasing inbound RTP and no media-state transition or signaling recovery. Native aggregate measurements were:

| Role | RTT p95, ms | Jitter p95, ms | Packet loss, % |
| --- | ---: | ---: | ---: |
| Teacher | 135.88 | 9 | 0.10551 |
| Student | 127.38 | 6 | 0.06296 |

The encompassing server histogram window measured RTT p95 174.47 ms, jitter p95 20.24 ms and packet-loss p95 0%. Unavailable Yjs heartbeat-termination metrics were not converted to zero. After the steady window, received screen share, bounded local mirror, stop, student reload/rejoin, collaboration recovery and an actually exercised diagnostic HTTP 503 fallback all passed. HTTP/WSS requests stayed in dev. Strict browser certificate validation was enabled for this repeated run.

The teacher signaling socket lasted 2741.449 seconds; the student's first socket lasted 2713.952 seconds before the intentional reload, then 10.587 seconds before cleanup. The own-lesson server log summary reported zero SIGNAL_SOURCE_CLOSE, zero DUPLICATE_IDENTITY and zero reconnect markers; three CLIENT_REQUEST_LEAVE records correspond to the planned reload and completion. Independent API verification confirmed lesson HTTP 404 and material ARCHIVED.

This is one successful long developer-network run with synthetic media and 720p capture defaults, not an RF ISP/no-VPN or production capacity certification. The earlier failed run remains unresolved evidence; a successful repeat without configuration changes does not establish its cause or erase it from release assessment.

The completed shared-edge collector produced 200 samples from 2026-09-05T21:42:07Z to 2026-09-05T22:34:26Z. Maximum CPU was 8.360%, minimum available memory 1599.6 MiB, peak RX 6.071 Mbps and TX 5.824 Mbps. Swap, OOM and UDP error increments were zero; monitored nginx/production-coturn had no down samples or restarts. The shared-host gate passed. As above, its production allocation counters are not used to certify dev allocation behavior.

## Final delivery and cleanup state

All 21 dev ArgoCD applications remained Synced/Healthy on the same #308 digest after the long run. Direct/RF web, RF Key, canonical dev issuer discovery and RF API health returned HTTP 200 with TLS validation. The final Fluent Bit sample recorded 114 sanitized output events, zero output errors/retries/failed retries/drops and approximately 6.4 MiB cgroup memory; Fluent Bit, dev TURN, production coturn and nginx were active with zero restarts. A protected VictoriaLogs query confirmed 16 recent sanitized dev events. Both long-run fixture cleanups were independently checked.

The independent network canary completed 582 successful HTTPS checks across direct/RF dev origins, with zero failures. It was stopped after the lesson and cleanup; it does not substitute for actual WebSocket/media evidence. Test browser contexts and local Vite/preview processes were closed. Original platform/infra dirty working trees and unrelated files were preserved.

## Remaining gates

At the end of the lesson verification the protected IPinfo token was absent on AX41; the subsequent provisioning result is recorded below. IPv4/IPv6 classification, activated GeoIP redirects and their live rollback are not certified. Real RF ISP/no-VPN acceptance, production-specific ports/credentials, live production panel checks, the production-specific 45-minute quality gate and capacity authorization remain open. The first long dev failure also remains an explicit release-assessment risk requiring observation in the RF canary. Production delivery remains on hold.


## IPinfo token provisioning — 2026-09-06

After explicit owner authorization and dashboard login, the token was transferred from the clipboard through SSH stdin to `/etc/honeyschool/secrets/ipinfo-lite-download-token` on AX41. File metadata independently confirmed root ownership and mode `0600`. The token value was not included in Git or command arguments. An isolated authenticated HTTPS download succeeded (23,802,987 bytes); protected temporary curl configuration and downloaded database were removed. No active MMDB, nginx configuration, service restart or redirect activation was performed.

The host has no `mmdblookup`, so actual country/ASN IPv4/IPv6 field checks remain pending and the complete provisioning acceptance task remains open. Infra commit `169e7e7` removes the incorrect 16-character token minimum and tests a synthetic 14-character token plus invalid-token rejection. Production delivery remains on hold.
