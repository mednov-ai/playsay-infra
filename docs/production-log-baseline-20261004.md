# Production log hotfix baseline, 2026-10-04

Change: `hotfix-production-victorialogs`. This document records the read-only inventory, scope resolution and local verification; it is not delivery acceptance.

## Repository and runtime baseline

- Original platform checkout: `codex/hotfix-production-lesson-entry-recovery`, ahead by one commit, with extensive pre-existing changes. Original infra checkout: `develop`, behind cached origin/develop by 407 commits, with extensive pre-existing changes. Both are preserved.
- Isolated local infra worktree: `/Users/evgeniymednov/Documents/Projects/Play&Say-victorialogs-infra`, detached at cached origin/develop `6edf07d`. No fetch, commit, push, CI or deployment occurred. Cached ref is an implementation reference, not current remote integration evidence.
- Live prod root and collaboration ArgoCD applications target `release/01.007.10`, observed sync revision `a6341d001fe1f933da0f05045bff410a7c490ec0`, health Healthy.
- API runtime source annotation: `437556ff664d`, image `ghcr.io/mednov-ai/playsay-api-gateway@sha256:728e9eef939cdece3270a3fd44e7fd7c562d4889e391dac04f3b9fda1413f4c9`.
- Collaboration runtime source annotation: `437556ff664d`, image `ghcr.io/mednov-ai/playsay-collaboration-service@sha256:6352387cfe1664b5b2625d98123f7ff88504d883722925c4223b9703da06de88`.
- LiveKit image: `livekit/livekit-server:v1.11.0`.
- Live source annotation was used for source inspection; relevant collaboration source files match cached origin/release/01.007.10.
- Current edited checkout runbook/AGENTS prohibits use of deleted VDSina. Cached origin/develop runbook still contains conflicting historical old-VPS rollback wording. Current AGENTS and live AX41 facts control; no legacy hosts were contacted. Correct relevant wording in the scoped documentation during implementation.

## Six-source coverage matrix

| Source | Actual host/input | Existing events | Implementation implication |
|---|---|---|---|
| RF nginx signaling | RF edge `/var/log/nginx/playsay-rf-livekit-signaling.log` | epoch, shared opaque request ID, status/upstream timings | Tail actual live path and rotate safely; do not assume old template filename |
| AX41 nginx signaling | Physical AX41 `/var/log/nginx/playsay-livekit-signaling.log` | Same bounded handshake/end-of-request fields | Guest collector cannot read physical host files; needs separate physical-host collector |
| RF coturn | RF edge `coturn.service` journal, active/running | Allocation/auth/error lifecycle | Parse in memory before any persistent queue; retain classes, never sessions/endpoints |
| LiveKit | Prod guest `/var/log/containers/*_livekit_livekit-*.log` | RTC lifecycle, reasons, channel errors, congestion | CRI and LiveKit timestamp/JSON parsing, exclude room/participant/endpoint fields |
| API regional route | Prod guest `/var/log/containers/*_playsay-prod_api-gateway-*.log` | Existing `regional_route_diagnostic attempt_id=... stage=... outcome=... connection_role=... transport_class=... regional_endpoint_matched=...` | Allowlist bounded enums and existing opaque attempt UUID |
| Collaboration | Prod guest `/var/log/containers/*_playsay-prod_collaboration-service-*.log` | Startup, snapshot persistence failures, external_activity_input_failure; no connection lifecycle log events | Current proposed connection/error logging acceptance cannot pass without source changes or an explicit scope revision |

## Design issues found during inventory (resolved in scope)

1. Design assumes two production collectors including host nginx on the prod guest. AX41 edge nginx runs on the physical host and its live log files were confirmed there. Use three independent bounded collectors (RF edge, physical AX41, prod guest), with source-specific credentials and private/authenticated ingress as appropriate.
2. Current proposal excludes application event generation and product image rebuilds, but requires collaboration connection/error logs. Exact runtime-source inspection shows `CollaborationHeartbeat.track` calls metric observer methods; `CollaborationMetrics.recordConnectionOpened/Closed` increments counters only. `server.ts` has no connection-lifecycle logger. Existing `console.warn` calls cover snapshot failures and external-activity errors, not socket open/close reasons.

The infrastructure cannot reconstruct missing connection events from silent stdout. Collector heartbeats cannot substitute for these business events. Two reviewable options:

- Extend the hotfix to add bounded, privacy-safe connection/close/error events to collaboration-service, with proportional tests and rebuilding only the affected product image. This meets the originally requested coverage but changes the infra-only design and affects both repositories' develop integration.
- Keep this an infrastructure-only hotfix collecting existing collaboration error logs and use its existing metrics for connection continuity. Explicitly revise the capability's lifecycle coverage and acceptance criteria; do not claim connection events are centrally logged.

## Safe fixture examples

`scripts/tests/fixtures/production-log-source-examples.json` contains synthetic parser-input examples derived from inspected source formats. They are not actual lesson records or evidence that a collector works. The collaboration sample is an existing snapshot error class and deliberately contains no fabricated connection event.

## Status

The owner approved adding privacy-safe collaboration lifecycle/error events. The design now uses three independent collectors and rebuilds only collaboration-service, with both repositories requiring develop integration. The historical blockers/options above record why this scope was needed.

Local implementation includes opt-in bounded collaboration events, production storage, protected scoped ingress, allowlisted SQLite collectors, metrics/alerts, exact-window query and rollout/rollback docs. Local verification: 55 collaboration tests + TypeScript build; seven parser/queue/window tests; three ingress/chart tests including byte-identical dev monitoring render; Docker TLS ingress and pinned VictoriaLogs smoke with all six sources plus collaboration lifecycle, UTC timestamps, canary-secret removal, rejected public/dev/method/admin requests and stable retry IDs. Ansible syntax validation is local only; remote check/idempotence and dev/prod canary acceptance remain pending. Pinned vmalert 1.123.0 dry-run successfully parsed the rendered alert rules. Remote firing/notification timing remains unverified.

Production pin: `victoriametrics/victoria-logs@sha256:251121fa882af99b95ba0c230a4a2f412ea602d2698c64a96c58dc9842bb755d` (1.53.0). [Official changelog](https://docs.victoriametrics.com/victorialogs/changelog/#v1530) documents current HTTP endpoint protections. Reviewed [maintainer advisories](https://github.com/VictoriaMetrics/VictoriaLogs/security/advisories) showed none published; this is not container vulnerability-scan clearance. Image help and local startup confirmed byte-retention/free-disk flags. [Disk retention guidance](https://docs.victoriametrics.com/victorialogs/#retention-by-disk-space-usage) retains a minimum partition window, so byte limit and local-path PVC request are not hard quotas.

Fresh `npm audit --omit=dev --json`: zero runtime findings. Initial full Node audit found six existing toolchain findings. Scoped Vitest 4.1.11 plus compatible transitive refresh resolves them: final full npm audit has zero findings, with 55 tests and TypeScript build passing again. Raw before/after reports are retained in platform docs/security/production-logs-hotfix-npm-audit-{before,after}.json. Container scans and remote CI gates remain pending; JVM exceptions were not used for Node findings. No image publication, remote CI, commit/push, production changes or published develop integration occurred.

## Delivery authorized

Owner authorized the full Git/CI/dev/production cycle on 2026-10-04. Fresh refs and read-only runtime still identify release/01.007.10. Infra non-image/build production values match that release. Platform delivery source is cut from production rather than develop to exclude unrelated collaboration changes; exact scoped source passes 47 tests + build, whereas initial develop-based tests passed 55. This source must be dev-accepted explicitly and recorded as ACCEPTED_DEV_COMMIT; semantic fix integration into both published develop branches remains mandatory.
