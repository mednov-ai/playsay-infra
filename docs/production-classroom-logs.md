# Production classroom log observability

This is the contract for `hotfix-production-victorialogs`. Technical deployment of `release/01.007.11` was verified on 2026-10-04; the real two-participant RF classroom canary remains pending. See [delivery evidence](../migrations/ax41/evidence/20261004-release-01.007.11-production-logs.md), the historical [baseline](production-log-baseline-20261004.md), and the [runbook](runbook.md#production-classroom-logs-hotfix).

## Storage and access

Production has its own VictoriaLogs workload and PVC on the production guest; dev is independent. Initial retention is seven days, PVC request 10Gi, resource requests 50m/128Mi and limits 500m/512Mi. Prod pins VictoriaLogs 1.53.0 by immutable multi-platform digest. Dev storage and existing Fluent Bit collector retain their current configuration.

Production query UI/API is VPN-only at `https://ops.honey.school/victoria-logs/select/`. Public/admin/internal/debug/flags/metrics paths and vmalert proxy controls are denied by edge nginx. Host/guest NodePort access remains private under the existing AX41 firewall/k3s nodeport-address policy; direct cluster/host administration is trusted operator authority. Logging does not reuse product identity or dev ingestion authority.

Only the exact JSON-line insert endpoint and a separate metrics insert endpoint accept dedicated production Basic credentials, POST, verified TLS and the three declared source addresses. RF resolves the certificate hostname to the physical AX41 ingress, bypassing Selectel's own public ops proxy. Each collector has a distinct username in a separate production htpasswd file; dev credentials are excluded. The collector's root-owned curl configs carry secrets and TLS/resolve settings; secrets never enter Git, arguments or output. Ingestion sets the explicit JSON-stream content type and immutable parser query parameters; form-encoded request parsing must never consume a log payload silently.

## Source and retained-field contract

| Source | Collector | Event classes and boundary |
|---|---|---|
| rf_nginx | Selectel | signaling_request with HTTP status, bounded upstream timings and opaque 32-hex request_id; reports handshake/request completion, not media |
| ax41_nginx | Physical AX41 | same signaling fields and shared request_id; guest cannot read this host file |
| rf_coturn | Selectel production coturn journal | allowlisted allocation opened/closed, authentication challenge and transport_error; no sessions, addresses or messages |
| livekit | Production guest CRI files | allowlisted RTC opened/closed/error reasons; coarse time correlation only, no room/participant identifiers |
| api_route | Production guest CRI files | existing regional_route diagnostic UUID and exact DTO stage/outcome/connection-role/transport/endpoint-match enums |
| collaboration | Production guest CRI files | opt-in connection_opened/closed, heartbeat_termination, connection_error; fixed channel/close class/age; existing snapshot_failure and external_activity_input_failure classes |

All records have environment=prod, source timestamp normalized to UTC, collected_timestamp (the local sanitization/enqueue time), event and bounded severity. Collector heartbeat records include input_ok. `collected_timestamp` is not a VictoriaLogs receive timestamp. Delivery latency metrics measure source time to successful HTTP acknowledgment and provide a conservative operational freshness measure. No shared TURN/LiveKit identity is invented.

Only explicit reconstructed fields enter persistent state or transport. Raw messages, addresses, user/room/lesson/participant identities, URLs/query/headers/cookies, credentials/token-derived values, SDP/ICE and content are excluded. Unknown/malformed records increment rejection counters and are discarded. Parser coverage is deliberately bounded; unknown LiveKit/TURN messages are not full-text retained. API enum changes and new source formats require parser tests before rollout.

Collaboration event output is opt-in, at most 100 events/second, and stops adding output at 16KiB stdout backlog. Suppression increments `playsay_collaboration_connection_diagnostics_suppressed_total`; logs never contain exceptions or close-reason strings. Other transport/heartbeat behavior is unchanged.

## Failure/resource contract

Three independent systemd collectors use Python standard library plus curl. Inputs are read only; SQLite stores sanitized events and non-secret file/journal cursors transactionally. There is no raw Fluent Bit filesystem buffer in the production pipeline. A stable random event UUID persists across HTTP retries; uncertain HTTP acknowledgment can cause duplicate insertions. Incident queries deduplicate event_id.

Per collector: 64Mi total state budget, 128Mi MemoryMax, 10% of one CPU, selected maximum 32 input files, 16KiB input/CRI fragment bound, 2KiB sanitized record, batches of 128 and finite connection/request timeouts. Payload queue uses at most one quarter of the state budget, SQLite pages at most one third, leaving room for transaction journal, metadata and metrics. Overflow evicts oldest sanitized rows and increments source dropped counters. File rename rotation is handled with held inode handles; CRI fragments stay in memory and are replayed from the last committed record after restart. Copy-truncate may lose data if truncation and regrowth happen entirely between polls; read errors/capacity are visible, but exact loss from an unobserved rewrite cannot be counted. No archived-log backfill is promised.

Initial file collection reads the currently available file from its saved offset (zero on first start); journal collection starts now on first start and resumes from cursor thereafter. A purged journal cursor fails collection visibly and requires a reviewed cursor reset; it is not silently reported as healthy. The first-start historical tail can exceed normal freshness targets until drained.

Storage byte retention removes daily partitions and preserves a minimum partition window; 8Gi is a pressure threshold, not a hard quota. Local-path PVC requests also do not enforce a filesystem quota. The 1Gi free-space write-stop threshold and 7Gi occupied/2Gi free alerts protect the host; monitor actual filesystem use and reserve headroom. Stop collectors first under pressure, preserve the PVC and evidence. Time retention does not guarantee seven full days under excessive volume.

Collector metrics: per-source heartbeat, input/delivery health, accepted/rejected/dropped/read-error counters, backlog/oldest age, last acknowledgment and delivery lag. Heartbeat is every 15 seconds. Alerts evaluate every 15 seconds and cover missing heartbeat/failed input/transport within two minutes; zero events with healthy input is distinguished from missing telemetry. Existing dev ingestion remains separate. Logs may fail or be suppressed without blocking lessons.

## Acceptance and delivery boundary

Local parser/privacy, rotation/restart, overflow/retry, chart render, nginx scope and Docker TLS/storage tests are necessary but do not prove production readiness. Authorized dev acceptance must exercise the real input paths, live resource budgets, no unexpected loss and normal p95 acknowledgment lag <=30 seconds. Production requires the existing approved zero-active-lesson window, storage before collectors, dedicated credential verification, second-pass Ansible changed=0, GitOps Synced/Healthy and a two-participant RF canary.

Only collaboration-service is rebuilt for the new event generation; every other production digest and routing setting must be preserved against the live release baseline, not replaced by cached develop values. Both repositories must contain the semantic fix on published develop, with the runbook's source/result SHA evidence, before closure. No commit/push/CI/deployment is authorized by local apply alone.

Rollback of observability disables collectors, removes only the logging ingress include and disables new storage workload through GitOps while keeping its PVC. Disable collaboration event output through its flag; applying the flag or restoring its image uses the normal collaboration GitOps rollout and requires a zero-lesson window. It is not a restart-free product operation. Collector/storage rollback itself never restarts product services or changes media routing. The deleted former VDSina is never a rollback target.

### Isolated live DEV acceptance

After operational authorization, `python3 scripts/dev-production-log-acceptance.py --ssh-key /protected/key/path` exercises the reviewed sanitizer/outbox from a temporary RF client against verified TLS DEV ingestion. It reads existing dev transport credentials only in memory, uses separate AccountID/ProjectID headers, tests retained stable IDs after a failed transport, and queries nine sanitized records across six sources, including Linux CRI partial-record/rename-rotation and cold outbox/cursor restart fixtures from the dev guest. Temporary curl files and queue are removed. It changes no product services or dev collector settings. Local rotation/privacy/overflow tests remain complementary; this synthetic check does not establish real production input coverage or RF media acceptance.

VictoriaLogs stores the configured `event` message field as `_msg`; the exact-window report recognizes both stored `_msg` and pre-ingestion fixture `event`. Every source exports explicit zero accepted/rejected/dropped/read-error counters before a first failure, so a first loss has an observable zero baseline.

Exact-window coverage includes the largest heartbeat gap, including window boundaries. A gap above 45 seconds is `incomplete_telemetry`, even when another heartbeat or event is present; do not infer healthy silence across that gap. Future window ends are rejected.

The production log alert group explicitly uses one-second `eval_delay` and query `latency_offset` with its 15-second interval and 60-second stale threshold/30-second hold. This avoids the default 30-second query/evaluation delay extending detection beyond two minutes. Other alert groups keep their current defaults. See [upstream data-delay and group options](https://docs.victoriametrics.com/victoriametrics/vmalert/).
