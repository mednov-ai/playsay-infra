# Guarded maintenance availability recovery — 2026-10-25

## Incident and cause

At 03:30:11 MSK the guarded AX41 owner fenced both cabinet routes for its eligible libvirtd step. The native daemon restarted successfully at 03:30:34, but its cgroup retained four dnsmasq processes and a running QEMU guest with old executable/library mappings. The old success condition required every cgroup mapping to be current, so it marked the step failed_unsafe after its wait and retained the committed barrier. This was an implementation error in daemon-versus-managed-descendant ownership. No timeout takeover or guest/DNS restart was attempted. The scheduled 04:20 follow-up detected the committed failed state.

Admission was reopened at 04:27:13 MSK through the reviewed same-lease recovery protocol. The cabinet block lasted 57 minutes 2 seconds. Both public origins subsequently returned page 200 and protected API 401. Existing VM processes remained intact; all seventeen baseline product/data/auth/media containers retained image, restart count and start time.

## Reviewed recovery

Published release source 863b944c introduced an exact, bounded recovery owner; ba16a51e778aea41ccf64ee8edd428ac2b6f2e68 contains the regression fix. The scoped recovery play first quarantined Selectel's executing scheduler and then AX41's, preserving ordinary crash recovery, readers, observers and package/reboot suppression. It required empty native job inventory, stopped native executors, native package ownership and clean database, complete serving health, exact failed AX41/libvirtd/restart owner/lease/step, and the existing LiveKit firewall validator. An initial application denied systemd_jobs_pending without changing state; a later verified idle application succeeded. No native job was cancelled.

Each owning host retains private recovery originals under /var/lib/honeyschool/maintenance/recovery-<timestamp>: config, worker, coordinator, fence and debt. No credential was printed, no journal/flag/nft table was manually removed, no lease transferred and no critical command repeated. The existing authenticated fresh verification/release protocol opened both barriers. Full descendant debt and its original first-pending time remain.

## Fix and validation

The inspector reads every cgroup mapping. Only exact native /usr/bin/qemu-system-x86_64 and /usr/sbin/dnsmasq members below libvirtd are classified as managed descendants. Full pending debt includes them. restartable_pending covers daemon/other members; managed_descendant_pending retains their separate reason. A healthy changed daemon generation with no actionable mappings completes its step, and descendant-only debt cannot select another daemon restart. Unknown members are not excluded. A reload still cannot clear retained actionable debt.

The corrected modules were installed on AX41 and Selectel while executing schedules were stopped, then explicitly re-enabled through the existing numeric-release scoped control owner. Both installed module hashes match the published source. AX41's actual inspector reports pending=true, restartable_pending=false, managed_descendant_pending=true and restart_needed=false; the retained first-pending timestamp is 1792745408. Both barriers are open and both package locks free. Both timers are active with the next native trigger 04:40 MSK. Product refs and images are unchanged.

Thirty-eight focused tests pass, including exact recovery identity rejection, native-job/executor refusal, no native cancellation, retained guest debt, reload debt, and a successful healthy daemon restart with retained VM mappings. Twenty-seven certificate/template tests pass. Scoped idempotence, fresh rule/source/route health and final develop ancestry are retained with this delivery's descendant-fix-20261025-* artifacts.

The current-thread follow-up now checks every ten minutes in hours 03/04 MSK and stays with an already-started operation at the final 04:50 check until its outcome and cabinet availability are known. This reduces detection delay; it never grants a critical step or bypasses the native owner. Actual Selectel service-restart acceptance remains pending; no completion is inferred from recovery, package updates or fixtures. No automatic reboot/guest restart or external notification test exists.
