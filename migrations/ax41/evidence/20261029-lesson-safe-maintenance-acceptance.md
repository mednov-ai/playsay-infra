# Lesson-safe host maintenance: native completion and acceptance — 2026-10-29

## Native operation

The regular Selectel 03:40 MSK systemd timer completed the remaining `systemd-networkd` restart. No heartbeat/manual critical invocation was used. Before this attempt, the daemon retained its 2026-10-15 process (PID 1259014), generation `e0c9cdfabb55c984daecd9f0907bf67a39d27a2e5b958c17ce58326e3371e44e`, with actionable debt. The new active process is PID **2772786**, started **2026-10-29 00:40:46 UTC / 03:40:46 MSK**, NRestarts=0, generation `6a76192fca189c346984c2d1df2b68ad9542c6f2abe7e17b8ace3f480a34d833`. Both direct runtime inspection and central per-service metrics report pending/restartable_pending=false.

The observer saw admission closed at 03:40:25, verification at 03:40:49 and both worker completion/open admission by 03:40:58. Its earlier source observations were real, fresh, healthy PROD/DEV/AX ingress/Selectel ingress/TURN reads. Native authority retained window, package locks, same-owner lease/fence, preflight and activity guards. Earlier 03:20/03:30 activity denials were retained, never overridden. Both workers/coordinator returned idle, package locks were free, recovery_required=0. No reboot, VM/QEMU/dnsmasq restart, connection termination, takeover, clock/activity editing or manual journal/flag/nft reset occurred.

The following 03:50 native timer runs finished inactive/MainPID=0/Result=success with no_eligible_debt, open admission and no repeated daemon restart. Exact AX41 libvirt QEMU/dnsmasq descendant debt and its original first_pending_at=1792745408 remain visible; restartable_pending=false. This is retained guest/DNS debt, not a reason to repeat libvirtd maintenance. Unknown package/reboot debt is not claimed resolved.

## Authenticated serving and media acceptance

Four native browser journeys passed against installed assets without overrides:

| Environment | Public origin | Verified transport |
| --- | --- | --- |
| PROD | online.honey.school | authenticated OIDC PKCE, room token, two classrooms, shared presence, bidirectional audio/video |
| PROD | online.honeyschool.ru | same checks plus REGIONAL_RELAY and selected local TURN relay candidate |
| DEV | dev.online.honey.school | authenticated OIDC PKCE, room token, two classrooms, shared presence, bidirectional audio/video |
| DEV | dev.online.honeyschool.ru | same checks plus REGIONAL_RELAY and selected local TURN relay candidate |

Each journey used a disposable teacher/student and supported lifecycle APIs. Both participants had connected peer connections and increasing inbound/outbound audio/video RTP bytes across a six-second interval; both local selected RF candidate pairs were relay candidates. Playable local/remote video and current classroom screenshots were checked. Chromium supplied synthetic camera/microphone streams. This proves actual server/signaling/collaboration/media/TURN transport; it does not certify physical devices or every consumer ISP path.

The first test runner tried recording before the preview microphone was ready and timed out; its fixture cleanup succeeded. The corrected runner waited for an enabled recorder and used real keyboard recording controls. An initial RF token request without Origin correctly selected baseline routing. Supplying the same Origin as the actual first-party browser selected REGIONAL_RELAY; no server policy was changed. The erroneous ops.honeyschool.ru test issuer was corrected to the deployed ops.honey.school issuer. Failed attempts remain in protected evidence and are not counted as passed acceptance.

All created lessons were deleted with subsequent GET=404, private materials archived through the supported API, teacher/student assignments removed and created profiles deleted. All eight task-owned Keycloak accounts (four per environment) were deleted through its supported administration API with absence verification. Local disposable credential files were removed afterward. Browsers closed normally. Post-cleanup observations showed zero lesson windows, LiveKit rooms/participants, collaboration/game/external connections and snapshot queues. Nonzero native TURN relay socket observations were preserved and not treated as zero or forcibly closed; no maintenance operation depended on a post-test zero.

## Preservation and regression evidence

Both production public pages returned 200. Nineteen Argo applications were Synced/Healthy; the newer authorized release 01.007.23 desired state was preserved. Sixteen original non-web product containers retained their exact image/process/restart identities. The web runtime matched authorized .23 digest `sha256:ea8ab86ab6b42ae33efe32fe8e1ba2c1da76e5db340c00bd9ef887d842ac2e75`, ready with zero restarts. No product deployment or schema migration was performed by this task.

All five executor source observations remained complete/fresh/healthy; all three RF-to-AX HTTP/TCP/TLS probes succeeded. Eleven certificate observations were healthy using the ten-minute latest-sample query appropriate to five-minute publication. Fourteen maintenance and twenty-seven certificate rules had zero evaluation errors. NIC semantics_version=2 aggregate 5 equalled the RX/TX error/drop component sum; telemetry does not reinterpret those values as cross-host packet loss. External alert receiver delivery remains unconfigured, as explicitly retained in the original acceptance scope.

Focused regressions: 47 host-maintenance tests and 27 certificate tests passed. Published-release scoped Ansible control checks passed on both hosts with changed=0, failed=0, unreachable=0. The first Selectel check had a transient SSH connection failure; the bounded read-only retry passed and both outputs are retained.

Protected local evidence: `hotfix-results/lesson-safe-host-maintenance-20261023/night-20261029-0340-*`, `night-20261029-0350-*`, and `acceptance-20261029/` (four successful results/media-stats/screenshots, failed-run records, account absence proofs). Recovery originals, operational credentials and historical debt evidence are retained as operational recovery material, not disposable fixtures. No secrets/user records are included in this document.

## Integration

Runtime maintenance source 071f9bb1 was already an ancestor of fresh origin/develop 2770417e before this evidence update. This documentation-only final release head must also be integrated into fresh develop, preserving the .23 product/GitOps state; final SHA ancestry is recorded in the task checkpoint after publication. Normal systemd maintenance/certificate timers remain enabled. The chat follow-up is disabled only after final checks and integration succeed.
