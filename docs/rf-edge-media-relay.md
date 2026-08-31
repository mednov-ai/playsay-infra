# RF-edge classroom media relay contract

The first production regional relay is coturn on the existing Selectel RF edge. No VM, disk, public address, provider resource, or recurring compute charge is added. The established `rf_edges` inventory, `ansible/playbooks/rf-edge.yaml`, and `scripts/apply-rf-edge-release.sh` remain the only configuration path. The host stays at Ubuntu 24.04, 1 vCPU, and 2 GiB RAM; nginx continues to own Russian browser, API, authentication, and WebSocket ingress.

coturn has an independent configuration, 64-character REST secret, `turn.honeyschool.ru` certificate/private key, listeners, quotas, systemd accounting/limits, and aggregate metrics. It does not own or reload nginx. The public addition is TURN TCP/UDP `3478`, TURN/TLS TCP `5349`, and relay UDP `49152-49251`; UFW remains default deny. Node exporter binds only to loopback.

Generate the regional secret on a trusted workstation directly into a mode-`0600` ignored file. Deliver it as root to `/etc/playsay/rf-edge-media-relay-auth-secret` and independently to the protected production api-gateway Secret. Never print it. Rotate only with routing off and zero allocations: replace both protected copies, reconcile coturn, repeat invalid-credential and authenticated UDP/TCP/TLS allocation checks, then enable routing. On suspected exposure, turn routing off first, replace both copies, and allow old credentials to expire.

Point `turn.honeyschool.ru` at the established RF-edge address. Issue an independent ACME certificate without reusing any nginx private key. The deploy hook validates the certificate/key pair and writes `/run/playsay-rf-edge-media-relay-certificate-reload-required`; it never restarts coturn. Consume the marker only with zero allocations, then repeat TURN/TLS allocation.

Capacity is limited to one concurrent two-participant 45-minute lesson with 720p camera, microphone, and one screen-share cycle. Pass requires zero media reconnects, loss below 2%, RTT p95 below 300 ms, jitter p95 below 50 ms, total host CPU below 70%, at least 512 MiB available memory, RX and TX below 30 Mbps each, zero swap/OOM/UDP errors/restarts/allocation failures, and healthy nginx/coturn. A failure disables regional selection for new room tokens before coturn is touched.

This is a deliberate shared failure domain, not high availability and not evidence for 100 lessons. A dedicated or second relay, resize, wider relay range, or concurrency increase requires a separate reviewed provider-state and capacity change with rebuild, drift, backup, and rollback ownership.
