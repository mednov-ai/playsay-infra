# RF media relay canary evidence

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
- `.school` baseline unchanged:
- `.ru` relay-only selection for both browsers:
- Camera/microphone bidirectional subscription:
- Screen-share start/receive/stop cycle:
- Rollback drill result and duration:

## Real lesson window

- Exact Moscow/UTC start/end and stabilization end:
- VPN disabled at start; recovery comparison timestamp if later required:
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

## Decision

- Result: `PASS` / `FAIL`
- Every gate passed:
- Acceptance remains limited to one concurrent two-participant lesson:
- Regional control returned to `off` or continuous authenticated monitoring evidence:
- Flag-first rollback, allocation drain, and coturn-only stop drill with nginx preserved:
