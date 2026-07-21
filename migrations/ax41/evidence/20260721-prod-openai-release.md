# Production OpenAI release 1.001.02

Date: 2026-07-21
Environment: `playsay-prod`
Release branch: `release/1.001.02`

## Approved scope

- Material generation in `api-gateway`: `gpt-5.6-sol`.
- Vocabulary suggestions in `vocabulary-service`: `gpt-5.6-sol`.
- AI Tutor and lesson translation remain unchanged and disabled for production.
- Dev remains on `gpt-5.4-mini`.

## Credential gate

The owner confirmed that a separate production OpenAI key was installed interactively as `playsay-openai/api-key` in namespace `playsay-prod`. The key value was not printed, copied to Git, or provided to the agent. This document records owner confirmation, not independent secret-value inspection.

## Git and validation gates

- Both model names are explicit environment-specific Helm values.
- Both production OpenAI feature flags are enabled only in this numeric patch release.
- The prod root Application and every child Application target `release/1.001.02`.
- Helm lint and rendered-manifest checks must pass before the branch is pushed.
- Production activation requires a manual root Application revision change/sync by the owner.

## Post-sync acceptance

- Confirm all production ArgoCD applications are `Synced/Healthy`.
- Confirm `api-gateway` exposes provider `openai` and model `gpt-5.6-sol` without printing the API key.
- Confirm `vocabulary-service` exposes model `gpt-5.6-sol` without printing the API key.
- Run one authenticated material-generation request and one vocabulary-suggestion request.
- Record only status, model, latency and provider/rate-limit error class; do not record credentials, prompts, generated lesson content or user data.

Rollback is a new numeric patch release that sets both production OpenAI feature flags to `false` and is manually synced through the same root Application process.
