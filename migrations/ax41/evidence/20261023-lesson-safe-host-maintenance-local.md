# Lesson-safe maintenance: local candidate, not deployed

Source baseline: cached infra origin/develop b97dddecfa79105d93cc0544af752d17ebb8b30d.
Isolated detached worktree `hotfix-lesson-safe-host-maintenance-infra`. No remote ref
refresh, commit, push, CI or host mutation was performed for this apply. Platform
source/images are unaffected. Both primary dirty checkouts were preserved.

The earlier read-only incident investigation found apt-daily-upgrade at 09:30:08
MSK on 2026-10-23, zlib installation at 09:30:48, an explicit needrestart nginx
restart, nginx stopped 09:30:49–54, and four corresponding Selectel upstream
connection failures. Two established websocket connections closed at 09:30:54.
Probe failures at 09:30:50/55 and subsequent media recovery support this causal
chain. There was no observed product pod restart or certificate event in that
window. This evidence does not establish unrelated client behavior or exclude
all additional faults. The earlier NIC aggregate counted packets; kernel-owned
counters at observation were rx_errors=0, rx_dropped=5, tx_errors=0, tx_dropped=0.
No raw user logs, identities, credential-bearing URLs or payloads are included.

Implemented local safe fallback: periodic installation/reboot deferral, additive
protected-service selection, explicit Moscow schedule, read-only serialized observer,
aggregate state/debt publication and monitoring. There is no install/restart command
in the observer. Missing admission exclusion never grants disruptive authority.
NIC v2 reads declared named counters and incident queries exclude old/incomplete
history. Scoped policy and counter plays have no critical-service restart handler.

Local verification: nine scheduler/activity/debt/discovery/lock/NIC tests; two-owner
Jinja rendering and Perl syntax; both scoped Ansible syntax checks; shell syntax;
Helm production lint; six PromQL rules validated and debt 24/72-hour firing/resolution
fixtures pass; RF DEV/media monitoring and edge-log contract checks pass. Certificate
regressions pass 26 tests using the existing external Ansible Python environment.
An initial certificate test invocation with plain Python lacked Jinja2; rerunning
with the documented environment passed. No production endpoint was used.

Remaining: reconcile actual service names/needrestart versions, all automatic
installer/cron/hook/reboot bypasses, complete read-only activity producer privileges,
source/package-list freshness, admission exclusion, effective live timer/policy
preflight, two-host idempotence/PID preservation, central ingestion and external
notification acceptance. Cross-host disruptive locking/executing maintenance and
real runtime update acceptance are not implemented or claimed; all such work stays
disabled. Numeric release selection/publication/deployment and develop ancestry
proof need separate authority. OpenSpec remains incomplete.
