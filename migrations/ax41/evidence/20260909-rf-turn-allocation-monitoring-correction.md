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
- Make configuration validation refresh the collector and compare both metrics with an independent bounded socket count.

## Delivery evidence

Pending the reviewed numeric infra release, zero-active-lesson check, idempotent Selectel apply, and idle/active/post-drain validation.
