# Dev GeoIP acceptance — 2026-09-06

## Scope and refs

Owner authorized finishing GeoIP provisioning, dev-only entry/auth acceptance and independent rollback/environment isolation. Production delivery remains on hold. Infrastructure delivery uses the clean pushed feature branch `codex/route-rf-users-via-selectel-geoip`, dedicated `scripts/apply-ax41-geoip-dev.sh` and `ax41-geoip-dev.yaml`; no complete AX41 host/edge play was applied.

- `f6cbb3a`: install reader, separately managed policy and four dev-only location hooks; updater activation restores prior state on failure.
- `b8d55dd`, `0e869cf`: correct systemd sandbox for nginx syntax validation (PID, logs and nginx temporary directories).
- `2365f69`: dev entry enabled with production disabled.
- `8c56932`: serialized updates, protected temporary files, independent timer pause and validated last-good rollback retaining original age.
- `ed91738`: dev entry disabled and timer paused for rollback verification.
- `ba92834`: entry restored independently while timer remained paused.
- `efb282c`: daily timer restored; final exact-ref check returned changed=0.

## Provider and updater

IPinfo token is root-owned `0600` on AX41; values never enter Git or command arguments. Actual MMDB download succeeds (23,802,987 bytes); reader metadata reports IPv6-capable format and build epoch 1788681813 (2026-09-06 08:03:33 UTC). `mmdblookup` confirms RU/AS13238 for public fixtures 77.88.8.8 and 2a02:6b8::2:242, and US/AS15169 for 8.8.8.8 and 2001:4860:4860::8888. These are public test fixtures, not learner addresses. [Official IPinfo schema/licensing](https://ipinfo.io/developers/ipinfo-lite-database) was checked: country_code/asn, IPv4/IPv6, CC BY-SA 4.0 attribution; the existing product attribution link is present.

The first service run and a subsequent validation attempt failed because nginx syntax validation needed writable runtime paths in the service sandbox. Both were fixed through Git/Ansible and retained in the failure counter. Subsequent normal systemd updates succeed. Actual last-good rollback passed with the timer paused and restored the original success timestamp. The final timer is active/enabled. Unit tests cover normal update, invalid credentials, stale download failure, nginx/reload failure restoration, and rollback without a download or renewed age.

## Entry and authentication

A loopback-only isolated nginx process used the real installed MMDB and the deployed policy/snippet. Explicit public IP fixtures were mapped to the reader input only in that isolated process; no public spoofing header or country override was added. RU IPv4/IPv6 returned 302, non-RU IPv4/IPv6 and unknown returned 204. Production, callback, API and WSS exclusions passed. Previous real-nginx spoofed-header/trusted-hop policy tests passed all 19 cases.

Browser navigation consumed decisions from the isolated MMDB process while loading actual dev application/auth endpoints. Tests passed path/query/fragment preservation, login/logout, callback completion on the original origin when geographic entry becomes active during login, and recovery-page navigation. Invalid reset-code requests returned 400 on both dev origins without external returnTo navigation. No real user's password was changed and no recovery email was sent. This verifies recovery routing/error handling, not email delivery.

Four actual teacher/student login/callback/logout cases on both dev origins passed. Production API rejected dev JWTs with 401. Both canonical issuers rejected callback URLs from the other environment with 400. A fresh direct classroom-link test exposed a pre-existing lost return path in explicit login and default silent SSO; platform `778289b6` fixes both and excludes callback credentials from the retained path. Web #309 delivered that fix; a fresh browser successfully returned to its authorized lesson and displayed prejoin, and fixture cleanup passed. Platform `00e53fe7` additionally keeps router state pathname-only while retaining query/fragment in the restored browser URL; final #310 verification is pending.

## Rollback during media

Two RF dev browsers passed 24 × 20-second steady-media intervals during updater delivery, entry disable/restore and database rollback. No unexpected signaling recovery or media connection transition occurred, and received RTP progressed throughout. RTT p95 teacher/student was 122.345/127 ms, jitter 16/16 ms, packet loss 0.17284%/0.15316%.

The later screen-capture extension timed out waiting for the teacher's active-share control. That extension is not counted as passed; it does not erase the completed eight-minute rollback interval. This is not a new full lesson/screen-share or no-VPN acceptance claim. Fixtures were independently verified as lesson 404 and material ARCHIVED after cleanup. The earlier unresolved long-run signaling failure remains in the preceding evidence and release assessment.

## Environment boundary and final state

Production TURN rejected dev REST credentials on UDP/TCP/TLS; dev TURN rejected invalid and production-derived REST credentials and then successfully allocated/released within its own relay range on all three transports. Keys were used only inside server memory; no valid production allocation was created. Earlier forbidden dev egress destination checks and shared-edge resource acceptance remain applicable; these bounded checks do not certify production ports for real RF ISP access or higher concurrency.

AX41 nginx retained master PID 1245751 and NRestarts=0. Byte comparison proved the original routes unchanged apart from exactly four dev browser-entry includes; production virtual-host content was preserved. Direct/RF dev web and keyboard HTTPS endpoints returned 200. The isolated MMDB policy process was stopped and cleaned. Production GeoIP remains false; no production application/media rollout or service restart was performed.
