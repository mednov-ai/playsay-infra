# Develop reconciliation and release 01.007.00 preparation

The owner authorized merging published hotfixes and accepted RF/GeoIP changes into develop and creating/building the next ordinary release. The latest instruction explicitly excludes production promotion and remote production changes.

Platform baseline: develop `61a1bfdb945da03a06ed474e6eda7c1f25e66c47`; production source `751b8b7b977a7d57325d46b80db3562723f5818b` (release/01.006.14). Reconciliation commit `ff739cb8` retains the complete production history and merges `origin/codex/hotfix-user-deletion-dev`. The resulting tree exactly equals that previously tested dev branch. The only merge conflicts were additive: retaining the RF connection-route migration before the deletion checkpoint migration and retaining the RF preference mutation import.

Infra baseline: `f62bb35ce01bb0f5096c791665d23d79357a8509`. Merge the RF GeoIP branch and deletion-recovery runbook branch; preserve the current production release pointer `release/01.006.14`. Production GeoIP stays disabled. The candidate LiveKit uplink filter remains an undeployed source change.

Audit: for every fetched remote branch containing `hotfix`, compare against the reconciled HEAD using `git log --right-only --cherry-pick --no-merges HEAD...<branch>`. Both repositories have zero unmatched patches. Ancestry of the latest production platform source and exact tree equivalence to the tested dev source were checked independently. Historical release-specific image pointers are not merged over current environment values; the existing candidate-preparation workflow restores current production image/build metadata for unchanged modules.

Local validation passed: release-target contract, regional-routing finalizer contract, infra release preservation test, GeoIP updater contract, RF dev edge contract, and real API binding of rendered prod/dev/media-rollback Helm settings (Gradle RegionalMediaRoutingBindingTest). No repeated browser/long-duration lesson run was needed for this tree-identical merge. Production acceptance is not claimed by these checks.

Build status and candidate SHA must be recorded after CI finishes. Creating or building release/01.007.00 does not authorize promotion; production remains on its prior release.
