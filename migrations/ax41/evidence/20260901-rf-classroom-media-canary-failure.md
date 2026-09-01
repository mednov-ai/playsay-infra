# 2026-09-01 RF classroom media canary failure

## Privacy and scope

This record contains only aggregate timestamps, route classes, counters, health states, and resource values. It excludes participant names and subjects, lesson and room identifiers, client addresses, tokens, TURN credentials, secret-derived values, SDP/candidates, device labels, raw logs, and lesson content.

The exact production metrics interval was `2026-09-01 19:05:31-19:20:31 UTC` (`22:05:31-22:20:31 MSK`). Both participants tested the `.ru` classroom without VPN. The owner reported that the previously usable lesson became poor and appeared to stop using the relay.

## Deployed state

- Production root and API returned to `release/01.006.03` / infra revision `b252c6dc634bf33794734d326789e9b9c0904dbf` after a brief declarative root-only rollback was reversed.
- The API deployment remained ready and continuously reported runtime mode `rf-origin-relay`; it was not restarted or synced to the off configuration during the observation.
- Direct and RF signaling probes returned the expected bounded unauthenticated response.
- Privacy-safe RF and AX41 signaling evidence showed that WebSocket sessions reached both hops, but repeatedly closed.

## Production media and continuity aggregates

The exact 15-minute production window reported:

- `signal_connected_joins=25` and `rtc_connected_joins=15`;
- `participants_min=1` and `participants_max=2`;
- `rtt_p95_ms=2306.38`;
- `jitter_p95_ms=86.89`;
- `packet_loss_p95_percent=4.60`;
- `packet_loss_increase=8325` and `nack_increase=23239`;
- zero pod restarts and zero node UDP receive/send buffer errors;
- healthy core and RF probe targets;
- collaboration connections between 6 and 14 with zero forced closes.

A time-bounded LiveKit aggregate for the overlapping ten-minute window reported 37 participant starts, 24 resumes, 20 signal-source closes, three duplicate-identity events, two peer-connection-disconnected events, and 11 generic relay-candidate observations. The candidate observations contain no addresses and therefore do not prove selection of the RF coturn service.

## RF edge aggregates

The overlapping RF sample reported:

- maximum total CPU `3.972%`;
- minimum available memory `1,725,677,568` bytes;
- maximum RX/TX `0.342/0.519 Mbps`;
- zero relay UDP sockets and zero allocation failures;
- TURN authentication-failure samples between 9 and 15;
- zero swap, service restarts, OOM, and UDP errors;
- active nginx and coturn throughout the sample.

These values reject shared-host CPU, memory, network capacity, process restart, and kernel UDP pressure as the observed cause. They do not establish an RF media path: coturn had no observed live allocation while the lesson was active.

## Classification and decision

Result: `FAIL`.

The failure class is `REGIONAL_MEDIA_NOT_SELECTED_OR_AUTHENTICATED`, with a separate `SIGNALING_CONTINUITY_DEGRADED` observation. The two-hop signaling contour was reachable, but signaling reachability and generic relay candidates are insufficient evidence that browser media traversed Selectel. The required RTT, jitter, loss, and zero-reconnect gates all failed.

A post-window protected comparison loaded the production API Secret and the RF coturn auth file only into local process memory, validated both as 64-character values, and emitted only `match`. No secret, hash, or other secret-derived value was retained. Secret drift is therefore rejected as the cause and no rotation was performed.

The regional media canary MUST remain unaccepted until a fresh authorized `.ru` room-token credential completes a real RF TURN allocation, both browsers nominate the RF relay, and coturn reports nonzero correlated allocations. Healthy regional signaling must be controlled and rolled back independently from regional TURN media.
