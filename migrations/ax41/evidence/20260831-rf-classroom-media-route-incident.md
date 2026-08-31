# 2026-08-31 RF classroom media-route incident

## Privacy and scope

This worksheet contains only aggregate infrastructure and media measurements. Learner names, authenticated subjects, lesson or room identifiers, client addresses, device labels, tokens, TURN credentials, SDP, and lesson content were neither queried for evidence nor retained here.

The incident window is `2026-08-31 08:30-08:50 MSK` (`2026-08-31 05:30-05:50 UTC`). Both browser sessions entered through `https://online.honeyschool.ru`. One participant initially used a VPN; the other recovered after changing to a VPN route. The independently observed chat-WebSocket reconnect loop is recorded separately below and is not classified as the media incident.

## Sanitized timeline

| Moscow time | UTC | Aggregate observation |
| --- | --- | --- |
| 08:36:30 | 05:36:30 | LiveKit outgoing microphone packet loss peaked at `41.5459%`. |
| 08:37:00 | 05:37:00 | Outgoing microphone packet loss remained at `22.3091%`. |
| approximately 08:42 | approximately 05:42 | LiveKit samples disappeared for approximately 60-90 seconds, consistent with a media reconnect. |
| 08:44:00 | 05:44:00 | Outgoing camera packet loss reached `15.8319%`. |
| full window | full window | Maximum observed RTT was approximately `225 ms`; maximum jitter was approximately `59 ms`. |
| recovery | recovery | Changing the client network route through VPN restored usable media. |

## Server and ingress health

- Production compute CPU remained below `18%`; approximately `29.5 GiB` memory was available.
- No relevant pod restart, OOM event, host UDP-buffer error, or production firewall/NAT validation failure was present in the interval.
- The Russian HTTP/API/WebSocket ingress had no corresponding 5xx or process-health event.
- LiveKit signaling remained reachable before the media loss; `.ru` HTTP and signaling traversal through Selectel did not imply that WebRTC media used Selectel.

## Production VictoriaMetrics correlation

The privacy-safe aggregate collector was verified read-only against production VictoriaMetrics for the exact `05:30-05:50 UTC` interval. It observed a maximum of `2` concurrent LiveKit participants, core application/LiveKit scrape health `1`, RF endpoint probe health `1`, `0` pod restarts, `0` UDP receive/send buffer errors, RTT p95 `189.24 ms`, jitter p95 `29.58 ms`, packet-loss p95 `0.627%`, `1,143` lost packets, and `4,270` NACKs. The aggregate p95 does not replace the short per-track peaks in the incident timeline. The current metrics expose no chat-WebSocket reconnect counter, so that value is retained as `not_available` and the browser observation remains separate.

## Classification

The accepted coarse failure class is `MEDIA_ROUTE_UNAVAILABLE`: authorization and signaling succeeded, server resources and ingress stayed healthy, media suffered severe route-dependent loss and a reconnect, and changing the client route recovered service. The retained evidence does not identify a specific carrier or network hop, so no narrower root-cause claim is made.

The chat WebSocket separately reconnected roughly every 2-5 seconds during the observation period and continued after the VPN route change. It is an application/signaling defect outside the regional media-relay acceptance result.

## Current AX41 baseline captured read-only

The active-topology checks were performed without configuration changes and with secret output suppressed:

- Direct classroom signaling/API health: direct `.school` and RF `.ru` public health routes responded successfully.
- LiveKit fallback: production TCP `7881` was externally reachable.
- TURN: production TCP/UDP `3478` and the bounded AX41 relay range were declared consistently by Ansible, LiveKit Helm values, UFW/DNAT reconciliation, and the runbook; a REST-secret authenticated allocation baseline was already accepted in the current AX41 evidence.
- Firewall/NAT: `/usr/local/sbin/playsay-validate-livekit-firewall` passed with one required rule per production contour and no host UDP buffer errors.
- Room-token contract: the response contained LiveKit server URL, short-lived token, room name, identity, expiry, and translation permission; no regional routing object existed.
- One-lesson resource baseline: production CPU stayed below `18%`, available memory stayed near `29.5 GiB`, pod restarts were zero, and no swap/OOM/resource-pressure event correlated with the incident.

These checks establish the retained AX41 rollback baseline; they do not certify a Selectel TURN allocation or a wider concurrency profile.
