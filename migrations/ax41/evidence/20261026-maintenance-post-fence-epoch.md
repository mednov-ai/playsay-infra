# Post-fence activity proof ordering — 2026-10-26

## Reproduced defect

The previous snapshot validator classified counters before checking whether every read began in the current admission-fence epoch. A healthy ingress read with Writing=1 taken just before closure returned activity_busy immediately, even though it could not establish post-fence activity or quiet. The new regression test fails against the previous code and passes against the corrected predicate. This can cause premature aborts around fence/control traffic; it does not establish that every prior busy decision had this cause. Actual current activity remains a valid denial.

## Bounded correction

First validate every complete source's health, schema, age, generation and lesson lookahead. Once admission is closed, require every read_started_at to be inside that fence epoch before classifying counts. Pre-fence positive reads cause the existing bounded observations_precede_fence wait and cannot create a zero baseline. A busy pre-claim snapshot still denies reservation; any positive post-fence count still defers and reopens admission. Missing, unhealthy, malformed or stale sources remain immediate failures. No count/timestamp is rewritten, no source or kind of traffic is excluded, and two independently separated current zero readings, lease identity, admission, package and time guards remain mandatory.

Code source: 627ffd08. Installed model SHA256 on both hosts: d07fa4c99bb711dfe174fe9a6aef9c5e037abb3465aad1536f7f004f83bf1dec. Only the infrastructure gate and its regressions/docs change; guest producers, intervals, sockets/counters, product API/images/data and application revisions remain unchanged.

## Delivery and validation

The existing clean published numeric release owner staged the change with execution disabled on AX41/Selectel. Live staging proof confirms both configs disabled, both executors stopped, both barriers open, package locks free and exact model hashes. Twenty-four installed control tests per host use temporary journals/FakeFence, never production activity or a production clock override. Both were re-enabled through the same scoped owner after these checks. Forty-one focused local tests and twenty-seven certificate/template regressions pass. The new cases cover immutable pre-fence positive input, actual busy pre-claim/post-fence decisions, unknown pre-fence sources, absence of an old zero baseline and two fresh separated observations.

Both scoped check modes finish changed=0. Both native timers are active, both executor-enabled series are 1, all five source health series are 1, recovery-required is 0, fourteen maintenance rules and twenty-seven certificate rules evaluate without errors, and nineteen Applications are Synced/Healthy with unchanged .19 product refs. No critical retry, connection closure, fake live zero or manual journal/lease operation was performed for acceptance. Only the native scheduler may start the next eligible attempt; the first corrected attempt is observed separately at 03:40 MSK.

Durable sanitized artifacts: hotfix-results/lesson-safe-host-maintenance-20261023/epoch-fix-20261026-* and epoch-fix-installed-tests.py. The final release-head merge-back and exact GitOps revision are recorded after publication. Tasks 5.6/6.2 remain pending until real Selectel service-restart/runtime acceptance and final cleanup; fixture success or this predicate correction alone does not close them.
