# AX41 / Selectel certificate hotfix — 2026-10-19

## Result and remaining acceptance

The owner authorized delivery with `Разрешаю`. The expired AX41 shared certificate
was renewed on its original lineage, nginx validated and gracefully reloaded.
It now expires **2027-01-17 09:53:52 UTC**, with all original eight SANs. Normal
TLS and application access recover across PROD/DEV direct and regional routes.
A real Mailjet callback for an existing delivery was received and processed.
No new email was sent, no DNS/issuer/credentials changed, and no media service
was restarted.

**The hotfix remains open for external alert delivery.** Both PROD and DEV lack
`monitoring/playsay-telegram-alerts`; production Alertmanager actually uses `noop`,
without a Telegram receiver or resolved delivery. The owner was asked for an approved
recipient and a protected credential source. No notification test was sent. Rule
validation and healthy ArgoCD must not be presented as external notification acceptance.
The per-lineage notification column is pending in the acceptance matrix.

## Scope and release ownership

Infra source started from fresh develop `4fa336c0f335fb9dceeddb3c3d523e20f1b9846b`.
Numeric host overlay: `release/01.007.20`, PR #48. Durable code includes local-first
HTTP-01 fallback only for ops.honey.school and dev.ops.honey.school, and certificate
lifecycle/monitoring. The current platform source remains
`87a9389c41afba98757ca3375399c7dd1963aced` on release/01.007.19.
The production root and monitoring-lite select the infra overlay; the other 17
ArgoCD applications retain .19. All 12 product deployment image lists compare equal
before/after. The platform release pointer/candidate manifest remain .19 so later
platform release tooling resolves the real unchanged source. DEV desired-state
files compare equal to the fresh develop baseline.

The full production nginx render exposed accumulated unrelated route differences.
The released ACME-only owner therefore replaces only the recognized HTTP challenge
block for ops.honey.school, preserving every other byte and rejecting unknown or
ambiguous input. DEV's full render changes only its three HTTP challenge locations.
Initial live monitoring validation exposed the recording-rule remote-write requirement
and vmalert's automatic path append; both are corrected and covered by a render guard.
The previous alert evaluator remained running during the failed initial rollout.

## Release gates and protected rollback

All seven exact-source production Liquibase convergence workloads pass with zero
pending changesets; no migration was performed. Four database dumps and restore
listings pass. Keycloak was restored into an isolated temporary database; that
database and verification files were removed and absence verified.

Root-only protected host archives are retained on both owners at
`/var/backups/playsay/certificate-hotfix-20261019T1045Z/nginx-certbot-before.tar.gz`.
SHA256: AX41 `bad2bb54f8e2f641d2e945d2bcfb79dcff93862245c9ed15f2eed430517e3102`;
Selectel `d699568f8b9734b76e2a0b8f3fa764c8b45e8366b6979eb650642d20e268937a`.
Protected guest dumps use the same directory, with SHA256:

| Database | SHA256 |
|---|---|
| playsay | 044eb1deedf08446e2a2015d192f3397bd7b82663bb6e6982b26cef8eb6540e0 |
| keyboard | 79ca7ce72bccd21c99c1a17a4bf133be3d161628c24a2c1064e8c00239f5db19 |
| worksheet_import | 50c98bdab334a1fb8c7dec98962067860671ad4e326163295076d8f731861d33 |
| keycloak | e0e53fd3ef18c837c608a849e012dbb3d9db27b6d7ea338326f39f265c822c6a |

Two fresh successive runtime observations show zero participants, rooms,
collaboration connections and snapshot queues, with metric ages below 15 seconds.
The authoritative lesson access-window query is zero. Expired historical IN_PROGRESS
rows were preserved. No private key, database contents or raw provider output was
copied into this evidence.

Rollback restores only the affected nginx or lifecycle configuration through its
reviewed owner, validates before reload, and **retains the new valid certificate**.
Never restore the expired shared chain, disable verification, change DNS, restart
active TURN, or contact the deleted legacy host. Removing fallback reintroduces the
renewal failure and is only a temporary configuration rollback. Preserve the original
Certbot schedule and valid certificates when reverting preventive automation.

## Recovery acceptance

- Public DEV and PROD ops HTTP probes: local-only 200, origin-only 200, local-wins
  collision 200, missing 404. All task challenge files removed on both hosts.
- PROD and DEV file ownership remains separate. The DEV apply preserved the original
  production checksum. TURN PIDs remain 526088 and 787137 throughout.
- AX41 shared staging validation and staging hook rehearsal pass for all eight names;
  Selectel prod/dev ops hook rehearsals also pass without changing production chains.
- Strict direct AX41 SNI probes for all eight names match disk fingerprint
  `03270cc1ee14fef8c29103802f8ecf10bcdd3127df9f0c110bdf5870b3833a03`.
  Public Selectel ops chains are independently trusted; AX41 remains TLS 1.2.
- PROD/DEV web and keyboard on both domains return 200. Protected unauthenticated
  gateway probes return 401. Canonical OIDC discovery returns 200 with unchanged issuer.
- Four browser PKCE/login/protected-gateway checks pass with normal TLS from the
  workstation through an AX41 SOCKS vantage. This does not certify an independent
  Russian last-mile connection. Own synthetic identities and application profiles
  were removed, with zero non-fixture references and absence checks. Private fixture
  credentials were removed. No test lesson or email was created.
- PROD and DEV Mailjet harmless `[]` smoke returns 200/401/401 for valid/missing/wrong
  authentication. All seven registrations per environment are alive, Version 2 and
  match the expected endpoint as booleans. No provider configuration mutation needed.
- A real external authenticated callback received HTTP 200 at epoch 1792407517;
  the corresponding existing provider attempt became OPENED at epoch 1792407518,
  preserving original event epoch 1792392455. Safe correlation hash:
  `0597d4b75776a6a9a0d09311af3f6c30`. In reviewed source, polling sets event time to
  the check time; this older event plus the one-second receipt/update correlation
  distinguishes callback processing from polling. No message/recipient was recorded.
  Recovery precedes Mailjet's 2026-10-20 06:47 UTC deadline.

## Preventive automation and checks

All 11 owned lineages match host SANs and webroot renewal configuration. All have
fresh trusted disk/served chains, matching fingerprints, successful eligibility
`not_due` and successful staging rehearsal. Existing Certbot 2.9.0 is reused with
one persistent timer at 00:00/12:00, hourly health at minute 05, weekly staging Sunday
03:15 and metric publication every five minutes. The package cron is systemd-guarded;
no duplicate active renewal scheduler was added. TURN activation remains deferred
through existing markers and verified zero-allocation procedures.

The health collector publishes 11 successful health, eligibility and rehearsal
observations centrally. Recording rules define expected inventory independently
of the collector. Expiry warning/critical thresholds are 30/14 days; health/eligibility/
rehearsal freshness is 2 hours/26 hours/8 days. nginx mismatch grace is 15 minutes,
TURN pending warning one hour, and persistent renewal/rehearsal failure escalates
at 24 hours. External alert delivery remains pending as described above.

Verification: 26 certificate tests; 17 PromQL behavior fixtures and 27 rule syntax
checks; installed vmalert 1.123.0 dry-run; existing DEV ingress, TURN monitoring and
edge log contracts; Helm prod/dev renders/lint; Ansible syntax; shell syntax and
scoped ingress checks; git diff whitespace check. No runtime dependency or product
image was introduced or rebuilt. Fresh runtime inventory, schema, backup and activity
gates remain distinct from local tests.

Accepted implementation source: `67406ccc87a4ad8a483e21cc785c26108dd12aeb`.
All 19 production applications are Synced/Healthy, including the root/monitoring
overlay on .20. The live evaluator has 27 certificate rules with zero evaluation
errors; persisted expected inventory and successful health/eligibility/rehearsal
queries each return 11. No certificate alert is firing. The isolated 17-case fixtures
cover failure/recovery, but external delivery is pending.

The release is integrated through [PR #48](https://github.com/mednov-ai/playsay-infra/pull/48).
Final remote release-head ancestry and semantic-source verification are retained in
the task's sanitized post-merge artifact. Ancestry is checked after the PR merge,
without editing the release again solely to embed its own final commit hash.
