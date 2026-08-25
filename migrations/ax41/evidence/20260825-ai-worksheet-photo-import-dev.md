# AI worksheet photo import: AX41 dev delivery evidence

Date: 2026-08-25  
Scope: `playsay-dev` on AX41 only

## Source and delivery identity

- Platform feature/develop revision: `340780e04e88dd288226747c1e1b1fe133f88a7c` (`codex/add-ai-worksheet-photo-import` is present in `develop`).
- Infra revision after the completed rollback drill: `60337b0ef03ed89ed49f7fd2cba5d837c0fd9354`.
- Final dev images:
  - API gateway: `api-dev-120`, `sha256:7376abecdd65bed5de3a6de59b068325911a65f054d9fbf6ab86c1d07a5b1f7e`.
  - Web app: `web-dev-236`, `sha256:40384fdf68d34e17ad3ae144cb4abba9167f5296e0b87edf7993251ac4c4c767`.
  - Worksheet import service: `worksheet-import-dev-11`, `sha256:bf85ec2470d3c72f1f07072676b35b204211e6be637f08d11c2684d74898137f`.
- Jenkins worksheet-only dispatcher builds `#143` through `#147` and child builds `#7` through `#11` completed successfully. The final child build produced `worksheet-import-dev-11`; its code-only delivery correctly left the database migration stage not executed.
- Relevant final worksheet bot commits are `d0ed2af`, `b14ea95`, `72e7f65`, `c09d1fa`, and `640f482`. API and web bot commits selected `api-dev-120` and `web-dev-236` respectively.

## GitOps and runtime state

- ArgoCD applications `api-gateway`, `web-app`, and `worksheet-import-service` were `Synced` and `Healthy` at revision `60337b0ef03ed89ed49f7fd2cba5d837c0fd9354` before this evidence-only commit.
- All three affected deployments reported `1/1` ready replicas with the digests listed above.
- Dev gateway import was enabled. The worksheet service used provider `openai`, reasoning effort `low`, and request timeout `PT120S`.
- The initial worksheet database provisioning and migration completed successfully; later code-only builds skipped migration. Staging storage, material assets, source attachments, and provenance remained durable throughout rollout and rollback verification.
- Production remained unchanged: the worksheet service and gateway flags are disabled and the worksheet provider remains `stub`.

## Acceptance evidence

- Stub acceptance passed with 13 synthetic sources and 14 pages spanning JPEG, PNG, WebP, and PDF. It covered answer keys, every supported worksheet group type, confidence gating, rights checks, idempotency, private draft visibility, privacy boundaries, and schema-v2 classroom/homework compatibility.
- Desktop and mobile flows, keyboard and touch interaction, and visible/assistive text in `ru`, `en`, `de`, and `fr` passed. Existing representative Sprint 5 and Sprint 6 UI smoke checks also passed.
- Real-provider acceptance passed with a synthetic JPEG and one-page synthetic PDF. Analysis reached `READY`; materialization produced a private schema-v2 draft with two teacher attachments, while student material and attachment access returned `404`. The test material was archived.
- Manual continuation was verified on an owned synthetic failed session: it returned to `REVIEW_REQUIRED` without blockers and was then cancelled.
- After the rollback drill was restored, a new synthetic gateway request returned `201` and its session was immediately cancelled with `204`.
- Post-acceptance worksheet logs contained no error or warning entries and no credential or source-content markers. No customer worksheet, learner content, or Photo 1–8 artifact was used.

## Rollback disposition

- Gateway-first rollback: `bfe7dd6` disabled only the dev gateway entry point. New sessions returned `503 WORKSHEET_IMPORT_UNAVAILABLE`; existing session counts and the service replica remained unchanged.
- Provider rollback: `6128114` switched only dev analysis from `openai` to `stub`, retained the same accepted image and gateway-disabled state, and removed the runtime API-key reference.
- Provider and gateway restoration used `9d108c1` and `60337b0` respectively. The restored gateway accepted and cancelled a synthetic session successfully.
- At the service-disable checkpoint, all five nonterminal sessions were still inside the 72-hour retention window, there were no active leases, and the oldest session was approximately 6,350 seconds old. The safe service-disable condition was therefore not met, so the service was deliberately kept enabled for completion or TTL cleanup.
- Every rollback and restoration used reviewed infra Git commits and ArgoCD. No direct apply, manual Deployment or database mutation, force push, production change, or legacy-host access was performed.
