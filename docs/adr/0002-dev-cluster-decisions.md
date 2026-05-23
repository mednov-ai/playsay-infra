# ADR 0002: Dev Cluster Decisions

## Status

Accepted

## Context

The dev environment runs in the Netherlands and contains no real personal data.

Several architecture choices were clarified:

- Keycloak uses its own PostgreSQL database.
- One SPA is used for all roles.
- LiveKit and coturn run inside the dev cluster.
- AI bridge is not needed for dev yet.
- Future AI integration should remain possible.

## Decision

Sprint 0 installs only the infrastructure foundation and the API Gateway demo backend.

Keycloak, its PostgreSQL database, LiveKit, coturn, Yjs persistence, and AI integration are deferred to their planned sprints.

The dev cluster keeps all runtime services in k3s unless a later WebRTC/network test proves that a separate node is required.

## Consequences

- Sprint 0 stays small enough for the initial 2 vCPU / 4 GB VPS.
- Keycloak persistence is handled deliberately in Sprint 1.
- LiveKit ingress/firewall decisions are made in Sprint 3 with real testing.
