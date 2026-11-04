# One-time production stack-upgrade risk acceptance

On 2026-11-04, after the production blockers were presented, the owner explicitly
instructed: «Риск принимаем, обновляем версии на проде». This accepts the retained
PostgreSQL/Keycloak image findings for the current `upgrade-spring-boot-react`
production candidate only and authorizes its production delivery. It includes
the 69 new CVE/package pairs (19 CVEs) compared with the current Bitnami identity
database image, as enumerated in
`playsay-infra/migrations/ax41/evidence/security/20261104-stack-upgrade-prod-baselines/comparison.md`.
Exact compared candidate images are PostgreSQL
`sha256:03a1c6a62b27e8ad31cae5c085131b5ac706b09403d6fcb6c58d16c8daa257cd`
and Keycloak
`sha256:f79ab63440522b836f91ecf9ce420709a442d298246c4a5502666753fd9292cf`.
This is unresolved accepted risk for this candidate, without automatic renewal
or extension to changed images or findings. Fresh complete scans, exact runtime
scope, backup/restore, schema convergence, lesson safety, candidate acceptance
and numeric GitOps release gates remain required. The owner's risk acceptance
does not establish stage availability or successful candidate acceptance.

On 2026-11-04 the owner additionally approved a one-time exception for this
exact production candidate: skip stage acceptance and continue production
promotion after all other required backup/restore, schema, security and
lesson-safety checks, with acceptance immediately after rollout. This does not
authorize creating temporary stacks or waive other release gates. The exception
ends with this candidate's promotion and acceptance; it is not a standing rule.
