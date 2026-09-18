# 2026-09-17 RF-to-AX41 signaling-route incident

## Privacy and scope

This record contains only aggregate timestamps, proxy outcomes, transport state, and host/service health. It excludes learner names, authenticated subjects, lesson and room identifiers, client addresses, tokens, TURN credentials, SDP, ICE candidates, query strings, user agents, and lesson content.

The proven incident window is `2026-09-17 14:08:19-14:09:56 MSK` (`11:08:19-11:09:56 UTC`). The affected browser path entered through the Selectel RF ingress and then traversed verified TLS to the AX41 edge.

## Sanitized timeline

| UTC | Moscow time | Aggregate observation |
| --- | --- | --- |
| `11:08:19.271` and `11:08:19.529` | `14:08:19.271` and `14:08:19.529` | Selectel nginx began two signaling upstream attempts toward AX41. |
| `11:08:19.341` and `11:08:20.964` | `14:08:19.341` and `14:08:20.964` | Two previously established AX41 WebSocket sessions ended. |
| `11:08:24.339` and `11:08:25.963` | `14:08:24.339` and `14:08:25.963` | LiveKit closed two participants with `PEER_CONNECTION_DISCONNECTED`; six aggregate `dtls timeout` events occurred. |
| `11:08:34.255` and `11:08:35.054` | `14:08:34.255` and `14:08:35.054` | Selectel returned `499` after `15.783 s` and `14.726 s`; neither record had an upstream status, and neither request appeared in AX41 nginx. |
| `11:08:35` | `14:08:35` | AX41 UFW recorded two delayed incoming TCP resets from Selectel; these followed the failed attempts and are cleanup symptoms, not evidence of a blocked SYN. |
| `11:08:52.655` | `14:08:52.655` | A new Selectel attempt began. |
| `11:08:52.892` | `14:08:52.892` | The matching AX41 nginx request began `237 ms` later. |
| `11:08:52.895` and `11:08:53.373` | `14:08:52.895` and `14:08:53.373` | LiveKit signaling and RTC join recovered. |
| `11:09:55.338` and `11:09:56.290` | `14:09:55.338` and `14:09:56.290` | The second participant completed signaling and RTC join. |

## Negative evidence

- AX41 nginx had no corresponding attempts for the two failed Selectel upstream connections and no relevant 5xx response.
- AX41 continued serving unrelated requests without a correlated error burst.
- AX41 host CPU was approximately `9%`, about `16 GiB` memory was available, and there was no OOM, link flap, NIC error/drop, conntrack exhaustion, or full state table.
- coturn showed no correlated authentication or allocation failure.

## Classification and proven boundary

The narrow proven failure is transient loss of the Selectel-to-AX41 TCP/TLS/WebSocket path on port `443`. The transport interruption lasted approximately `33 seconds`; learner-visible recovery extended to approximately `97 seconds` before both participants had rejoined RTC.

The evidence does not prove a permanent provider block, an AX41-address block by Russian access providers, a Selectel policy block, or a specific failing hop. Provider attribution requires independent bidirectional probes with preserved timing and failure-stage metrics.

## Observability gap exposed

The existing public HTTP probe and minute-level loopback RF collector could not distinguish TCP connect, TLS handshake, expected HTTP response, and WebSocket-upgrade stages or preserve a short outage when RF metrics were not centrally delivered. The follow-up adds independent five-second path probes, privacy-safe cross-edge request correlation, bounded local persistence, authenticated delivery, fast active-classroom alerts, and a sanitized incident bundle.
