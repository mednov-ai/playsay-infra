# ADR 0003: GitHub and Jenkins for CI

## Status

Accepted

## Context

The original Sprint 0 plan used GitLab.com and GitLab CI. The project owner prefers Jenkins because it is used at work and provides transferable enterprise CI experience.

The current VPS has limited resources and already runs the public site, nginx, Docker-based Amnezia VPN, and will run k3s. Full self-hosted GitLab is too heavy for this server.

## Decision

Use:

- GitHub for Git repositories and pull requests
- Jenkins in k3s for CI
- GitHub Container Registry (`ghcr.io`) for images
- ArgoCD for CD/GitOps

Jenkins is exposed under the existing ops nginx endpoint:

```text
https://ops.play-and-say.ru:18443/jenkins/
```

The product repository owns its pipeline through `Jenkinsfile`.

## Consequences

- Sprint 0 keeps a self-hosted CI UI without running full GitLab.
- Jenkins credentials must be configured after bootstrap.
- GitHub repository URLs and GHCR image owners must be set before the first real pipeline run.
- Jenkins plugin, backup, and update maintenance become part of infrastructure operations.

