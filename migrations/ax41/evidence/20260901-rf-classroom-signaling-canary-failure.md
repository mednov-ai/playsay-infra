# 2026-09-01 RF classroom signaling canary failure

## Privacy and scope

This record contains only aggregate timestamps, route classes, counters, health states, and resource values. It excludes participant names and subjects, lesson and room identifiers, client addresses, tokens, TURN credentials, SDP/candidates, device labels, raw logs, and lesson content.

The observed no-VPN interval was approximately `2026-09-01 18:23:28-18:35:40 MSK` (`15:23:28-15:35:40 UTC`). Both participants used the `.ru` classroom origin. The owner reported repeated reconnect behavior for teacher and learner; the teacher indicator reached `Server lost`, while the learner remained in `checking`. VPN restored usable connectivity and is recorded only as the recovery comparison after failure.

## Deployed state

- Production root: `release/01.006.00`; all ArgoCD applications were `Synced/Healthy` at the diagnostic snapshot.
- Regional policy: `rf-origin-relay`.
- Deployed LiveKit signaling URL: `wss://online.honey.school/livekit`.
- Therefore an authorized `.ru` response could contain RF relay-only media routing while still returning the direct AX41 `.school` signaling URL.

## Sanitized timeline and counters

LiveKit recorded repeated signaling recovery from `15:23:28 UTC` through `15:32:55 UTC`. Aggregate events in the inspected window were:

- three ICE reconnect/switch observations whose selected remote candidate class was `relay` over UDP;
- five participant closures with reason `SIGNAL_SOURCE_CLOSE`;
- seven participant closures with reason `DUPLICATE_IDENTITY` after repeated start/resume attempts;
- one `PEER_CONNECTION_DISCONNECTED` closure and one intentional client leave;
- repeated `starting RTC session`, `resuming RTC session`, data-channel closure, and removal-without-connection events;
- after the failed attempts drained, LiveKit reported zero rooms, participants, and published tracks.

These aggregates prove that TURN media selection occurred, but the browser-to-LiveKit signaling source did not remain stable. They do not retain candidate addresses or participant/room labels.

## RF edge and upstream health

At `15:35:11 UTC` the shared Selectel RF edge reported:

- load averages `0.04 / 0.03 / 0.00`;
- approximately `1632 MiB` available memory;
- zero nginx and coturn restarts;
- zero recent coturn allocation errors and authentication errors;
- zero relevant nginx upstream/timeout/reset/error events;
- five consecutive certificate-verified Selectel-to-AX41 HTTPS probes returned HTTP `200`, with connect time about `18 ms` and total time about `96 ms`.

The public `.ru` web and API endpoints returned HTTP `200`, and direct `.school` API health also returned HTTP `200`. No application, LiveKit, nginx, or coturn pod/process restart correlated with the reconnect loop.

## Classification

Result: `FAIL`.

The coarse failure class is `SIGNALING_ROUTE_UNAVAILABLE`, specifically an incomplete mixed route: RF TURN media was selected while LiveKit signaling remained direct to AX41. The healthy shared-host measurements reject Selectel CPU, memory, nginx, coturn restart, and allocation failure as the observed cause. VPN recovery is consistent with changing the direct browser-to-AX41 signaling path; it does not demonstrate a capacity increase.

This canary fails the required zero-reconnect gate and provides no wider concurrency evidence. The safe remediation is to disable regional selection for new room tokens, then deliver one server-authored `.ru` route that atomically pairs `wss://online.honeyschool.ru/livekit` signaling through Selectel with RF relay-only media. DNS, LiveKit, coturn, nginx, identity, and classroom data are not first rollback levers.
