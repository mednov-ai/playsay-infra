# Stack upgrade production resume — 2026-11-04

The owner explicitly accepted the retained PostgreSQL/Keycloak candidate risks
and authorized production delivery. The owner then explicitly approved skipping
stage acceptance for this candidate only, retaining all other required checks
and immediate post-rollout acceptance. Exact risk scope is recorded in the
workspace `specs/contracts/security-risk-acceptances.md`. No temporary stack is
authorized by these instructions.

Read-only live preflight at 15:22:06 UTC (18:22:06 Moscow) found all 19 PROD
ArgoCD applications Synced/Healthy on release/01.007.24. Fresh PROD and DEV
maintenance guest readers returned healthy, known next-opening state and zero
for every reported activity counter. PROD next opening was 1793807400
(2026-11-04 15:50:00 UTC / 18:50:00 Moscow); DEV reported no next opening.
The next-hour lesson exclusion gate therefore refuses production promotion.
This is not evidence of ten minutes of zero activity, Selectel drain, or a
completed safe-window gate. No production Application target, workload, database,
route or release pointer was changed during this resume.

The remote production preparation PR77 is draft at
1599b76bb663b286d080c0124f3ff3d99061ede6. Platform source ac483353beb2abab8c1d076a887044b536d24c1f
is published on codex/stack-upgrade-prod-candidate-20261104; its local numeric
release/01.007.25 ref is not published. A numeric ready release, candidate-wide
fresh security evidence, refreshed backup/restore, exact-source schema checks,
identity import/recovery gates and safe admission still require completion.
Previous preparation is not a current pass for these gates.

The original repositories retain their pre-existing dirty work. Fetch in the
older infra worktree failed on `refs/remotes/origin/develop 2`; remote branch
and PR evidence was subsequently read with GitHub API rather than repairing or
overwriting that shared checkout. The separate reconcile worktree was clean
before adding this evidence.

The owner subsequently stated the scheduled 18:50 lesson is erroneous and
will not take place, and explicitly instructed proceeding. This overrides only
that schedule-window refusal for this promotion. Do not edit or delete the
lesson. Actual realtime/media activity, source freshness, backup/restore, schema
and release safety gates remain mandatory. The earlier stage exception and
candidate-specific risk acceptance remain in force.
