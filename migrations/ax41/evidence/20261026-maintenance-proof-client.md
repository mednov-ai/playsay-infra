# Bounded maintenance proof client — 2026-10-26

## Reproduced defects and correction

Regression tests fail against the previous worker: a second proof RPC was sent after three seconds although independent zero observations require ten-second separation; a retry could start after the 45-second bound; and an unusable, unstarted grant could select the bare abort path after the coordinator had committed the step. These are client/protocol defects. Read-only socket traces do not establish that every historical activity_busy result was caused by control traffic.

Source 3a74ee6075b070fe5ba77ce669153724a7cc8f09 waits thirteen seconds after an observation-spacing/generation rebaseline result, retains short pre-fence advancement retries, checks the bound before each RPC, caps sleeps and rechecks synchronized window eligibility. A stale unused grant records verifying before its exact completion acknowledgement and follows existing same-owner health verification and release. It executes no native operation and clears no runtime debt. Positive or unknown activity still denies work. No counter, producer cadence, source coverage, spacing requirement, grant age, admission enforcement or critical-step guard changes.

## Staged deployment and checks

The clean published release/01.007.22 scoped control owner staged both hosts with execution disabled. Both barriers were open, coordinator idle and package locks free. Installed worker SHA256 on both hosts is 796e2ecd3e13f987c2d193289955771d799eec57c3306689a0deabaa94951b7c, matching published source. Four new installed isolated proof tests and twenty-four installed control tests pass on each host; they use only temporary state and process-local mocks. Forty-five local maintenance tests and twenty-seven certificate/template tests pass using the existing Ansible Python environment for Jinja2. An initial system-Python certificate invocation lacked Jinja2; it was rerun successfully with that environment.

Both normal scoped owners re-enabled execution after staged validation. Both timers are active with next native trigger 04:30 MSK, both barriers open. AX41 libvirt retains descendant-only debt without scheduling another daemon restart. Selectel retains five actionable service debts. No manual critical retry, clock/activity override, journal deletion or connection closure was used. Native outcome, final scope check, GitOps revision and develop ancestry are recorded in subsequent acceptance evidence; deployment or tests alone do not complete task 5.6.

Protected local artifacts: hotfix-results/lesson-safe-host-maintenance-20261023/proof-fix-20261026-* and proof-fix-installed-tests.py. Tasks 5.6 and 6.2 remain open for actual Selectel critical restart and post-step authenticated realtime/media acceptance, then final cleanup. Product image revisions remain outside this host-only change.
