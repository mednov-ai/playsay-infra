# 2026-09-02 RF collaboration incident baseline

Sanitized owner-observed baseline for the pending collaboration-only change:

- the `.ru` classroom collaboration token still selected `wss://online.honey.school/collab/ws`;
- drawing propagation lag was 5–10 seconds;
- aggregate collaboration connections grew from 23 to 36, with 13 connection changes in five minutes;
- aggregate backpressure forced closes and collaboration-service restarts remained zero.

The evidence distinguishes collaboration/Yjs from LiveKit signaling and TURN/media. It contains no query strings, tokens, room/lesson/participant identifiers, addresses, headers, drawing coordinates, or classroom content. Healthy server backpressure and restart counters do not prove healthy browser-to-browser drawing propagation.

Implementation is limited to collaboration URL selection, Yjs browser transport lifecycle, collaboration-service liveness/metrics, the explicit token-safe ingress location, and collaboration evidence. Existing LiveKit signaling and regional media controls remain independent and unchanged. Work proceeds in clean scoped platform/infra worktrees based on the repository `release/01.006.04` branches; the owner's pre-existing dirty worktrees remain untouched. Production manifests and the release candidate target `01.006.04`, while the runbook's newest accepted runtime evidence is still `01.005.03`; delivery must verify and record the live revision before any mutation.
