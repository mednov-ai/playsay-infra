# RF TURN allocation monitoring correction — 2026-09-09

## Scope

This evidence records only aggregate production observations and the bounded correction to the Selectel RF-edge allocation collector. It contains no lesson, room, participant, address, credential, SDP, candidate, or content data.

## Detection

- Observation window began at `2026-09-09 06:26:07 UTC`.
- LiveKit recorded one room, two active participants, four published media tracks, two initial RTC sessions, zero reconnect sessions, zero close/disconnect events, and two TURN connections whose selected relay belonged to the established RF edge.
- The RF host had `6` UDP sockets inside the configured `49152-49251` relay range.
- The deployed collector exported `0` because it inspected the peer-address field from `ss -H -lun` instead of filtering local source ports.
- nginx and coturn were active with zero restarts; UDP input, receive-buffer, and send-buffer errors were zero.

## Correction contract

- Use the native bounded `ss` source-port filter and count only non-empty result rows.
- Fail before opening the temporary textfile when the socket query fails, preserving the last valid sample.
- Preserve `playsay_rf_edge_media_relay_udp_sockets` and `playsay_rf_edge_media_relay_active_udp_allocations` with identical non-negative integer values.
- Make focused monitoring validation refresh the collector and compare both metrics with an independent bounded socket count; retain the wider configuration preflight separately.

## Delivery evidence

- The semantic fix was integrated into `playsay-infra/develop` and published as `release/01.007.04`; the applied source revision was `da76cd309195186264c4645ea986d98249533b77`.
- The production gate reached zero LiveKit participants at `2026-09-09 07:28:32 UTC` before any apply.
- A full-play check was rejected without applying because it included unrelated nginx drift and a reload handler. The release added a tested `--monitoring-only` wrapper scope whose preview contained exactly the collector and validator and no handler.
- The scoped apply changed exactly those two files. Its immediate second check reported `changed=0`.
- Idle validation reported the two exported metrics and the independent bounded socket count as `0`.
- A suppressed authenticated TURN/UDP probe created a stable allocation with independent bounded count `3`; focused validation refreshed the collector and confirmed both exported metrics equalled that positive count.
- After the probe process exited, the server allocation drained naturally `3 → 1 → 0`, reaching zero at `2026-09-09 07:53:18 UTC`. Focused validation then again confirmed equal zero metrics.
- nginx and coturn remained active with `NRestarts=0`; RF allocation and authentication failures were zero. Production VictoriaMetrics reported zero UDP receive-buffer errors, UDP send-buffer errors, and pod restart increases across the twenty-minute delivery window.
- The earlier real `.ru` lesson remains the browser-path evidence: LiveKit simultaneously recorded two Selectel TURN connections. The post-fix positive metric proof used the controlled authenticated probe; no replacement browser lesson was created after the scheduled lesson ended.

The wider legacy `--configuration` preflight still rejects the host's existing listener inventory before reaching monitoring validation. This was present outside the collector correction and was not broadened or bypassed; `--monitoring` is the dedicated fail-closed metric check. The main change remains open for its existing full-lesson canary tasks.
