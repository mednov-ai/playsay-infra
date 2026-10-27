# Selectel completed coturn / ungranted commit incident — 2026-10-27

## Actual incident and root cause

The native 03:00 MSK owner restarted Selectel coturn at 03:01:01. New process generation d5318c6799aefe5eb1e17d59f8f34d6814cfe6f3683c373b6cc572d04e66048f is active with pending=false/restartable_pending=false; the previous generation was a859b021f705f902956b4d0918201862831b07e5273ab8b3222e73be54dc4e4b. The coturn step was acknowledged successful. During preparation of the following service, current activity denied the final pre-grant snapshot. No new step token was issued, but the coordinator remained committing with the last-completed coturn token. The worker's ordinary verify/release consequently failed lease_phase_invalid and persisted recovery_required/runtime_not_verified. No speculative control-traffic exemption or zero rewrite is justified by this observation.

The coordinator now returns a failed ungranted commit to verifying after a completed native step, or fenced before any native step. Existing committed barriers, last completed identity and all activity checks remain. Atomic step_running creation and native preflight are unchanged. Regression tests prove a positive commit-stage sample is denied without a fresh token and leaves same-owner verification possible.

## Scoped forward recovery

Published source d8e9c21280f383b470bb3e0d083797f22ae18aa3 extended the scoped recovery owner only for this exact Selectel coturn completed-success/current-token identity and worker error. It refuses outstanding/mismatched grants, native jobs, package locks/unclean database and unavailable serving health. No guest reboot, service replay, lease takeover, journal/flag/nft deletion or connection termination occurred.

The first read-only check denied systemd_jobs_pending. A later full check passed both hosts. Apply quarantined both native schedules, retained protected original configs/journals/debt, and moved only this completed same-owner commit to verifying. Its final Selectel stage initially denied package_lock_busy without opening admission. The published final stage was resumed using the same playbook, inventory, rf_edges limit and --start-at-task 'Read bounded recovery phase'; its own native/identity/health checks ran again. Existing authenticated verify/release then reopened both routes. The AX41 coordinator records fenced_at=1793059240 and last_released_at=1793059536: 03:00:40–03:05:36 MSK, 4m56s. Both public cabinet routes return 200, coordinator idle and package locks free. Three Selectel actionable debts remain (DEV TURN, logs, systemd-networkd); AX41 libvirt descendant-only debt remains visible without another daemon restart.

## Verification and remaining gates

Forty-seven local maintenance tests and twenty-seven certificate/template tests pass; recovery playbook syntax and scoped diff checks pass. Normal source installation, installed regression/hash verification, re-enable/idempotence, fresh metrics/product parity, exact GitOps head and final-head develop integration are subsequent separately recorded gates. Actual remaining service and authenticated realtime/media acceptance are still pending; this incident recovery does not close tasks 5.6/6.2.

Protected artifacts: hotfix-results/lesson-safe-host-maintenance-20261023/night-20261027-0300-*, commit-recovery-20261027-* and commit-fix-20261027-*. Raw executor journal is retained privately; sensitive identities/credentials are not published.
