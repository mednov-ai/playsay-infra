# 100 concurrent lesson capacity gate

This gate validates the single-node AX41 production profile. It is not a high-availability test: restarting LiveKit, coturn, API or collaboration can disconnect active lessons.

## Fixed workload profile

- 100 isolated individual rooms, two full publish/subscribe participants per room.
- VP8 camera video at 1280x720, 30 fps and at most 2 Mbps; Opus audio with DTX.
- 30% of participants forced through TURN.
- One schedule WebSocket and one collaboration/Yjs WebSocket per participant.
- Representative Yjs edits throughout the run and one snapshot flush every 10 seconds.
- Screen sharing, recording and external-activity tracks are excluded.

The stock `lk load-test` command models publishers and subscribers as separate participants. It is useful for an SFU stress preflight but does not reproduce two bidirectional participants per isolated room. The acceptance run therefore uses browser workers with fake 720p camera/audio inputs and the normal Play&Say login, room-token, schedule WebSocket and Yjs paths. Run workers from two external load-generator hosts; do not run them on AX41.

## Realtime port budget

LiveKit production owns UDP `50000:50511`: 512 ports. LiveKit requires two UDP ports per participant in this mode, so the fixed 100-room/two-participant profile consumes up to 400 ports and leaves 112 ports (21.9%) of headroom. The 120-room burst consumes up to 480 ports and leaves only 32; it is an acceptance burst, not a supported steady-state target. Expand the range or add a media node before raising the steady-state target above 100 rooms.

coturn owns relay UDP `49152:49999`: 848 ports. The 30%-forced-relay profile has 60 relayed participants; even the conservative static gate of two relay ports per participant requires only 120. `scripts/validate-100-lesson-capacity.sh` calculates both budgets from rendered/current configuration and fails if either range is too small. Port-range arithmetic is only a configuration gate: successful external ICE/TURN probes and the full load test remain required for certification.

## Production memory contract

| Workload | Request | Limit | Managed heap |
|---|---:|---:|---:|
| LiveKit | 2 GiB | 4 GiB | n/a |
| API gateway | 768 MiB | 1536 MiB | `-Xmx768m` |
| Keyboard service | 512 MiB | 1 GiB | `-Xmx512m` |
| Media service | 768 MiB | 1536 MiB | `-Xmx512m` |
| AI tutor | 448 MiB | 768 MiB | `-Xmx384m` |
| Registration | 384 MiB | 512 MiB | `-Xmx256m` |
| Vocabulary | 384 MiB | 512 MiB | `-Xmx256m` |
| Keycloak | 768 MiB | 1536 MiB | `-Xmx768m` |
| Collaboration | 256 MiB | 768 MiB | Node old space 512 MiB |
| Email/payment when enabled | 256 MiB each | 512 MiB each | `-Xmx192m` each |

Every JVM keeps at least 50% or 128 MiB outside heap, whichever is more relevant for its working set, for metaspace, code cache, threads and native buffers. Percent-based `MaxRAMPercentage` is not accepted in prod capacity values.

## Execution

1. Confirm there are no real active lessons and record an approved maintenance window.
2. Apply AX41 host networking first, then prod guest sysctl/coturn, and finally the release containing LiveKit, application resource and monitoring changes.
3. Verify `scripts/validate-100-lesson-capacity.sh`.
4. Create synthetic users/lessons through supported application APIs. Do not copy real users or lesson data.
5. Ramp active rooms through `10, 25, 50, 75, 100`, holding each step for five minutes.
6. Hold 100 rooms for 30 minutes. During the hold, run one normal bounded CI job.
7. Hold 120 rooms for 10 minutes, then stop new clients and verify recovery.
8. Delete all synthetic lessons/users and archive the VictoriaMetrics interval and load-generator report.

## Acceptance

- At least 99% of clients connect; join-time p95 is at most 5 seconds.
- Media packet-loss p95 is at most 2%, RTT p95 at most 250 ms and jitter p95 at most 30 ms.
- RX and TX remain below 700 Mbps; LiveKit CPU and memory remain below 75% of their limits.
- No OOM, pod restart, CPU throttling, `UdpRcvbufErrors`, `UdpSndbufErrors` or conntrack drop occurs.
- API latency p95 is at most 500 ms; schedule WebSocket and Yjs delivery p95 are at most 250 ms.
- Hikari pending connections, collaboration forced closes and snapshot retries stay at zero.

If any criterion fails because of sustained CPU or NIC pressure, do not certify the AX41 profile. Move LiveKit/coturn to a dedicated media node with 10 Gbit/s networking; raising limits on the shared AX41 is not an accepted fallback.

## Rollback

- Stop and remove synthetic clients before rollback.
- Roll back application and Helm revisions first. The widened firewall ranges may remain open during rollback.
- Never narrow UDP ranges while active ICE/TURN allocations exist.
- Restore the prior coturn/LiveKit ranges only in a second maintenance window after metrics show zero participants.
