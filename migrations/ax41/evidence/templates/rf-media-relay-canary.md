# RF classroom signaling and media canary evidence

Record only aggregate results and timestamps. Do not include names, subjects, lesson/room ids, addresses, tokens, TURN credentials, SDP/candidates, device labels, raw logs, or lesson content.

## Existing RF-edge configuration

- Established `rf_edges` inventory target confirmed:
- Existing shape confirmed (`Ubuntu 24.04`, `1 vCPU`, `2 GiB`; no resize/new resource):
- `turn.honeyschool.ru` resolves to the established edge at:
- Independent certificate/secret file ownership validated without values:
- Ansible release revision and check/apply/idempotence result:
- nginx config/active status before and after apply:
- Declared listener/firewall validation:

## Allocation matrix

| Check | UTC timestamp | Result | Aggregate latency/error class |
| --- | --- | --- | --- |
| Certificate name/chain/expiry | | | |
| Invalid credential rejected | | | |
| TURN UDP 3478 allocation and bidirectional data | | | |
| TURN TCP 3478 allocation and bidirectional data | | | |
| TURN/TLS 5349 allocation and bidirectional data | | | |

## Pre-lesson smoke

- Exact Moscow/UTC window:
- Zero-active-lesson confirmation:
- `.school` baseline unchanged (`wss://online.honey.school/livekit`, no regional media):
- `.ru` atomic route selection for both browsers (`wss://online.honeyschool.ru/livekit` plus relay-only media):
- RF/AX41 unauthenticated WebSocket-path probe bounded status classes:
- Camera/microphone bidirectional subscription:
- Screen-share start/receive/stop cycle:
- Rollback drill result and duration:

## Real lesson window

- Exact Moscow/UTC start/end and stabilization end:
- VPN disabled at start; recovery comparison timestamp if later required:
- Selected signaling contour (`rf-two-hop` required for both `.ru` clients):
- RF/AX41 WebSocket establishment/status/closure aggregates:
- LiveKit start/resume/signal-source-close/duplicate-identity/participant-continuity aggregates:
- Selected ICE transport class (`relay/udp` preferred; no address retained):
- Signaling reconnect count (`0` required):
- Media reconnect count (`0` required):
- Packet loss maximum/p95 (`<2%` required):
- RTT p95 (`<300 ms` required):
- Jitter p95 (`<50 ms` required):
- Total RF-edge CPU maximum (`<70%` required):
- Total RF-edge available memory minimum (`>=512 MiB` required):
- Total RF-edge RX/TX maximum (`<30 Mbps` each required):
- Swap/OOM/UDP errors/nginx or coturn restarts/allocation failures (`0` required):
- nginx and coturn health throughout (`healthy` required):
- Chat-WebSocket observation (reported separately from media):

## Independent classification

| Plane | Result | Bounded aggregate or failure class |
| --- | --- | --- |
| RF signaling ingress | | |
| Selectel-to-AX41 signaling hop | | |
| AX41/LiveKit signaling | | |
| TURN/media | | |
| RF shared host | | |
| Application/API | | |
| Collaboration WebSocket | | |
| Client resource/network | | |

## Decision

- Result: `PASS` / `FAIL`
- Every gate passed:
- Acceptance remains limited to one concurrent two-participant lesson:
- Regional control returned to `off` or continuous authenticated monitoring evidence:
- Flag-first rollback, allocation drain, and coturn-only stop drill with nginx preserved:
