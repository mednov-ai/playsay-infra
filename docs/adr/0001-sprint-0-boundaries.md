# ADR 0001: Sprint 0 Automation Boundaries

## Status

Accepted

## Context

Sprint 0 needs local repository structures and an infrastructure bootstrap script. Server registration and billing are handled by the project owner.

The agent must not receive long-lived secrets or perform uncontrolled remote changes. Real infrastructure changes are executed by a human using committed scripts and runbooks.

## Decision

Sprint 0 automation starts from an already-created VPS with:

- Ubuntu 24.04
- public IPv4
- initial `root` password access, or an existing project-specific SSH key
- inventory file filled locally by the owner

The main script is `scripts/bootstrap-dev.sh --ip <server-ip>`. It installs a project SSH key during first login, writes inventory, runs Ansible, and installs cluster add-ons directly on the VPS.

`scripts/new-server.sh dev` and `scripts/deploy-cluster-addons.sh dev` remain lower-level steps for manual phase-by-phase operation.

The VDSina API wrapper is included only as a thin future automation helper. Server creation remains a human-owned step for Sprint 0.

## Consequences

- Sprint 0 is reproducible without putting provider tokens in Git.
- The first real server can be bootstrapped safely after inventory is filled.
- Full provider lifecycle automation can be added later after testing the VDSina API payloads.
