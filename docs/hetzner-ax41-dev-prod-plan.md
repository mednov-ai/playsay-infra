# Hetzner AX41 Dev/Prod Consolidation Plan

**Status:** implementation in progress; safety bundle verified, AX41 host/VPN baseline active and both empty workload VMs running; application/data/TLS cutover is still pending
**Target host:** `65.109.55.110`, Hetzner AX41 in Finland
**Audience assumption:** the first production audience is outside Russia; the existing Russian-data production contract in `spec.md` remains mandatory when Russian citizens' personal data is collected.

## 1. Decision and boundaries

The target is the already provisioned Hetzner AX41 dedicated server with two isolated KVM/libvirt virtual machines:

- `playsay-dev`: migrated current dev cluster, Jenkins, synthetic data and automatic delivery from `develop`;
- `playsay-prod`: clean production cluster, separate state and integrations, built only from a protected three-part release branch named `release/<version>.<subversion>.<patch>` (for example `release/1.001.00`).

The host keeps its installed Ubuntu 24.04 LTS, mdadm RAID1 and ext4 filesystem. Do not reinstall it with Proxmox and do not replace the working mdadm/ext4 storage with ZFS merely to create the two VMs. Ubuntu's KVM/QEMU/libvirt stack provides the required VM isolation without another hypervisor distribution.

This is a temporary single physical failure domain. VM separation protects prod from dev cluster mistakes and bounded resource exhaustion, but it does not provide hardware HA. Public-site hosting, DNS, TLS issuance and external mail-domain configuration are owned separately and are not migrated by this plan. The Kubernetes `web-app` and `email-service` remain part of their respective clusters.

Dev and prod must not be namespaces of the same k3s cluster. They have separate Kubernetes API state, ArgoCD, Sealed Secrets keys, databases, object storage and external credentials.

## 2. Physical host and resource contract

Observed host baseline on 2026-07-20:

- Hetzner AX41, AMD Ryzen 5 3600, 6 cores / 12 threads with AMD-V;
- 64 GB installed RAM, approximately 62 GiB usable, plus 32 GiB host swap;
- two Samsung 512 GB NVMe drives in the installer-created mdadm RAID1;
- `/` on ext4, approximately 436 GiB usable;
- Ubuntu 24.04.4 LTS, kernel 6.8;
- one primary public IPv4, `65.109.55.110`, and a 1 Gbit/s uplink.

The RAID must finish initial synchronization and report both members healthy before VM creation. SMART and mdadm alerts are mandatory. RAID, qcow2 snapshots and replication inside the same host are not backups.

| Workload | vCPU | RAM | Maximum virtual disk | Priority |
|---|---:|---:|---:|---|
| `playsay-prod` VM | 8 | 42 GB | 200 GB qcow2 | highest CPU and I/O weight |
| `playsay-dev` VM | 2 | 12 GB | 120 GB qcow2 | CPU-capped; serialized CI, lower weight than prod |
| Ubuntu host | shared | approximately 8 GiB remain unassigned | at least 70 GB physical free space | libvirt, networking, proxy, VPN and filesystem cache |

Virtual disks live in a dedicated libvirt storage pool on the existing ext4 filesystem. Sparse qcow2 capacity is not permission to overcommit physical storage: alerts start below 20% free and new writes/deployments stop below 15% free. Ballooning is not used to take guaranteed RAM away from prod. The initial guests declare 10 vCPUs in total, leaving two hardware threads plus scheduler flexibility for the host; prod receives the higher CPU/I/O weight.

The dev CPU allocation is based on VictoriaMetrics from the current 4-vCPU/8-GB VPS. During the observed lesson window on 2026-07-20 08:50-09:40 Europe/Moscow:

- real compute usage excluding I/O wait averaged `0.87` CPU cores, p95 `0.95`, maximum `0.98` on a two-minute rate;
- apparent host CPU usage averaged about `70%`, but `43.9` percentage points were I/O wait; disk busy averaged `69%` and I/O PSI `some` averaged `55%`;
- memory available averaged only `0.53 GiB`, swap used `1.09 GiB`, and major faults averaged about `3127/s`;
- all Kubernetes containers used `0.28` cores on average; LiveKit used `0.13`, Play&Say application pods `0.04`, and Jenkins was effectively idle at `0.004` cores.

Across 2026-07-13 through 2026-07-20, host compute p95 was `1.63` cores, p99 `2.77`, and the rare maximum `3.58`; Jenkins itself peaked at about `1.19` cores. Therefore 4 dev vCPUs would reserve unnecessary scheduler capacity. Start at 2 vCPUs/12 GB: normal lessons retain roughly 2x compute headroom, while serialized builds may take longer but cannot crowd prod. The larger RAM allocation and local NVMe RAID1 address the measured paging/I/O bottleneck more directly than extra vCPUs.

The dev RAM allocation is also based on VictoriaMetrics working-set data. During the lesson window all Kubernetes containers averaged `5.85 GiB`, with p95 `5.92 GiB` and maximum `5.95 GiB`. Across 2026-07-13 through 2026-07-20 the total Kubernetes working set peaked at `6.24 GiB`; Jenkins was part of that total and independently peaked at `2.69 GiB`. A 12 GB dev guest therefore retains roughly 5 GiB above the observed Kubernetes maximum for the guest OS, filesystem cache and transient build/lesson overlap without reserving 16 GB permanently.

The AX41 exposes approximately 62 GiB usable RAM. Assigning 12 GB to dev and 42 GB to prod leaves approximately 8 GiB for the Ubuntu host. Memory ballooning remains disabled: this is a fixed initial allocation, not an overcommit target. Alert when host `MemAvailable` stays below 4 GiB for 15 minutes, and block non-essential VM starts, backups and build bursts until pressure is resolved; sustained host swap-in or memory-pressure stalls require revisiting the split before increasing either guest.

Raise dev from 2 to 3 vCPUs only through a reviewed OpenTofu/Git change when at least one condition is reproduced after migration: compute utilization excluding I/O wait stays above 85% for 15 minutes; serialized Jenkins build duration regresses by more than 30% against the post-migration baseline; or dev LiveKit/API thresholds fail while CPU is saturated. High load caused by I/O wait, memory pressure or a broken build is not by itself a reason to add CPU. A fourth dev vCPU requires a new prod-isolation review.

The current serialized Jenkins agent and capacity guard remain enabled after migration. Resource limits may be relaxed only after a dev build stress test proves that prod latency and LiveKit quality remain within their acceptance thresholds.

## 3. Network and security

The primary IPv4 remains assigned to the Ubuntu host. No additional public IPv4 is required for the initial topology. The host provides nftables forwarding/NAT, WireGuard management access and a minimal nginx/HAProxy edge service for hostname routing; it does not run application containers.

Private networks:

- workload bridge: `10.60.0.0/24`;
- `playsay-prod`: `10.60.0.20`;
- `playsay-dev`: `10.60.0.30`;
- management WireGuard: `10.250.0.0/24`.

Host SSH, libvirt administration and guest administrative SSH are reachable only through the management VPN after bootstrap. Libvirt TCP is not exposed publicly. The public firewall defaults to deny. Forwarding rules are explicit and environment-specific:

| Traffic | Prod | Dev |
|---|---|---|
| HTTP/HTTPS | host edge routes prod hostnames to `10.60.0.20` | host edge routes dev hostnames to `10.60.0.30` |
| TURN | `3478` TCP/UDP, `5349` TCP | `3479` TCP/UDP, `5350` TCP |
| LiveKit TCP fallback | `7881` | `7882` |
| LiveKit UDP media | `50000-50099` | `50100-50149` |

Recommended hostname split:

- prod: `online.play-and-say.ru`, `key.play-and-say.ru`, `ops.play-and-say.ru`;
- dev: `dev.online.play-and-say.ru`, `dev.key.play-and-say.ru`, `dev.ops.play-and-say.ru`.

Actual DNS records, certificates, public-site vhosts and mail records are created in the separately owned domain/site work. The infrastructure contract only publishes required upstream addresses and ports. Ops routes remain VPN-only even when they have DNS names. Existing public-site configuration must not be overwritten.

Amnezia is explicitly not migrated. Its existing containers remain untouched during the short overlap and terminate with the old VPS when the owner deletes it after the remaining three-day paid period. AX41 management uses a separate WireGuard deployment and must not depend on the old Amnezia service.

## 4. Infrastructure as Code contract

OpenTofu manages libvirt networks, storage volumes and VMs after the Ubuntu host is prepared. It does not repartition the host, create the mdadm array or install the host OS it manages.

Planned repository additions:

```text
playsay-infra/
├── terraform/
│   ├── modules/libvirt-vm/
│   └── environments/hetzner-ax41/{platform,dev,prod}/
├── ansible/
│   ├── inventories/hetzner-ax41/
│   ├── playbooks/{ax41-host,dev-vm,prod-vm}.yaml
│   └── roles/{libvirt-host,vm-network,wireguard,edge-proxy,cockpit}/
├── argocd-apps/
│   ├── dev/
│   └── prod/
├── helm-charts/                         # shared charts plus values-dev/prod
├── migrations/ax41/
│   ├── expected-prod-seed.yaml
│   ├── manifest.schema.json
│   ├── export-{dev,prod-seed}.sh
│   ├── import-{dev,prod-seed}.sh
│   └── verify-bundle.sh
└── docs/hetzner-ax41-dev-prod-plan.md
```

Responsibilities:

- OpenTofu: libvirt network, VM lifecycle, CPU, memory, qcow2 disks, private addresses, autostart and protection against accidental prod deletion;
- cloud-init: hostname, QEMU guest agent, SSH keys and base guest network;
- Ansible: Ubuntu host bootstrap, guest Ubuntu 24.04, k3s, OS hardening, nftables, edge proxy, coturn, VPN-only Cockpit Machines, node exporter and backup agents;
- ArgoCD: applications and cluster-scoped Kubernetes resources;
- Jenkins: build/test, GHCR publication and dev image-digest updates.

### 4.1 Git ownership and artifact boundary

The migration is Git-first, but Git is not a database or backup store. A fresh AX41/VM must be reproducible from one reviewed `playsay-infra` commit plus explicitly referenced encrypted runtime artifacts.

| Stored in Git | Stored outside Git |
|---|---|
| OpenTofu modules, provider lock files and non-secret inputs | OpenTofu state and backend credentials |
| Ansible inventories without passwords, roles and playbooks | SSH private keys and one-time bootstrap credentials |
| cloud-init templates without secrets | generated VM cloud-init secret payloads, if any |
| Helm charts, dev/prod values and ArgoCD root/apps | kubeconfigs and ArgoCD repository credentials |
| Jenkins JCasC, plugins, job XML and bootstrap scripts | Jenkins credentials, build caches and mutable job history |
| Keycloak realm/client/role configuration templates with environment placeholders | CLI exports containing users, password hashes, client secrets or sessions |
| SealedSecret ciphertext scoped to the intended cluster | Sealed Secrets private keys and original plaintext secrets |
| database schema/Liquibase and migration export/import code | PostgreSQL dumps containing runtime or personal data |
| migration manifest schema, expected counts and encrypted-bundle checksum | manifest with personal UUIDs, raw MinIO objects and the encrypted data bundle |
| verification, smoke, backup and restore scripts | restic/Storage Box credentials and backup repositories |

Raw PostgreSQL dumps, Keycloak exports and MinIO objects must not be committed, including through Git LFS. They contain mutable production data, personal identifiers, binary teaching content or password material. Each bundle is encrypted before leaving the source host and uploaded to the off-host restic/Storage Box repository. Git stores only its opaque bundle identifier, encrypted-file SHA-256 checksum, expected non-personal counts, source Git commit and destination environment.

Every applied infrastructure or migration operation records:

- the exact `playsay-infra` commit and dirty-tree check;
- the `playsay-platform` image digests deployed by that commit;
- the OpenTofu plan checksum and remote-state version;
- the encrypted data-bundle identifier/checksum;
- the source cutoff timestamp and verification report.

An uncommitted local script, hand-edited Kubernetes object or undocumented server command is not an accepted migration input. Emergency changes must be captured back into Git before final cutover.

Initial tooling contract:

- OpenTofu `>= 1.12, < 2.0`;
- `dmacvicar/libvirt` provider pinned to a reviewed `0.9.x` release, never floating `latest`;
- provider execution uses local `qemu:///system` on the AX41 because remote libvirt connections are not yet supported by the provider's 0.9 line;
- the reviewed Git revision is copied/checked out on the host through the management path; plans contain no secrets and a human performs `tofu apply`;
- separate OpenTofu states for platform, dev and prod;
- `prevent_destroy` on the prod VM and every prod disk;
- no passwords, private keys or API tokens in `.tf`, `.tfvars`, plan artifacts or Git.

The steady-state design stores state in an independent S3-compatible bucket with TLS, server-side encryption, versioning and native S3 lock files. Backend credentials are supplied at runtime from protected environment variables. The Hetzner Storage Box is not the OpenTofu state backend.

For the accelerated first `honey.school` cutover, absence of Object Storage is explicitly not a blocker. A temporary single-operator exception stores separate `platform`, `dev` and `prod` local states on the AX41 under `/var/lib/playsay-opentofu-state`, owned by the named `playsay` operator with mode `0700`. OpenTofu runs only on the AX41 against local `qemu:///system`; Jenkins apply, parallel apply and a second operator are prohibited. An encrypted snapshot of every state is copied off the AX41 before and after each apply and tied to the applied Git commit/plan checksum. The exception ends immediately after the first production stabilization window: migrate all three states with `tofu init -migrate-state`, prove versioning/locking and delete the local plaintext copies only after the remote copies are verified.

Both VMs use libvirt autostart, but neither environment may depend on guest startup order. The host remains manageable if either guest fails, and prod keeps the higher CPU/I/O priority when both start concurrently.

### 4.2 Visual operations with Git as the source of truth

OpenTofu remains the authoritative way to create or change libvirt networks, VM CPU/RAM, disks and lifecycle protection. The normal change flow is: edit a reviewed Git branch, run `tofu fmt`/`validate` and a read-only `tofu plan`, inspect the plan summary in the pull request or Jenkins job, merge, then perform an explicitly approved apply. Production apply is never triggered automatically by a merge.

The AX41 host also exposes Cockpit with its Machines/libvirt view only through the management VPN. It provides a visual inventory, VM state, CPU/memory graphs, storage overview and guest console. Routine start, graceful shutdown and reboot are allowed from Cockpit because they do not redefine the infrastructure. Creating/deleting VMs or changing CPU, RAM, disks, networks or autostart through Cockpit/`virsh` is prohibited except during break-glass recovery; every break-glass mutation must be reconciled immediately through an OpenTofu plan and committed configuration.

The visual operating surfaces are intentionally separated by layer:

| Layer | Primary visual surface | Authoritative change path |
|---|---|---|
| Physical host and VMs | Cockpit + Machines, VPN-only | OpenTofu/Ansible pull request and reviewed apply |
| Kubernetes clusters and workloads | Headlamp, VPN-only | Helm/ArgoCD manifests in Git |
| Delivery state | ArgoCD and Jenkins | Git promotion and pipeline jobs |
| Metrics and alerts | Grafana/monitoring UI | versioned monitoring configuration |

No visual panel is a second source of desired configuration. A scheduled read-only `tofu plan -detailed-exitcode` detects drift; any non-empty plan is investigated before the next infrastructure change. Cockpit must use named individual administrator accounts where supported, retain audit logs, require VPN access and must not be published on the public Internet.

## 5. Cluster and delivery separation

Dev:

- create a clean Ubuntu VM, install the pinned k3s release through Ansible and bootstrap Sealed Secrets plus ArgoCD from the reviewed Git commit;
- do not copy `/var/lib/rancher/k3s/server`, the old Kubernetes API state or local-path PVC directories as the migration mechanism;
- let ArgoCD recreate namespaces, operators and workloads from `argocd-apps/dev` and the Helm values in Git;
- restore a full encrypted dev data bundle: application PostgreSQL, the complete dev Keycloak realm/users with credentials, and the complete MinIO teaching-content bucket;
- recreate Jenkins from its Helm/JCasC/job definitions in Git; do not restore Jenkins controller state, build history, agent cache or ArgoCD runtime state;
- restore or rotate the dev Sealed Secrets key deliberately, then verify every committed SealedSecret can decrypt; the private key remains outside Git;
- keep current pod/service CIDRs `10.42.0.0/16` and `10.43.0.0/16`;
- use the new private node address and certificate SANs from Ansible; no legacy local-path node affinity remains after data import;
- retain Jenkins only in dev;
- keep ArgoCD auto-sync from `develop`.

Prod:

- bootstrap a new cluster; never clone the complete dev application database, Keycloak database or secrets;
- seed only the explicitly approved teacher/student cohort and Maria Mednova's materials described in section 5.1;
- use pod/service CIDRs `10.44.0.0/16` and `10.45.0.0/16`;
- use a separate Sealed Secrets private key, ArgoCD instance, PostgreSQL, Keycloak, MinIO, LiveKit, coturn secret and external-provider credentials;
- read images from GHCR using a prod-only pull credential;
- deploy only immutable image digests already verified in dev;
- track the matching protected `release/<version>.<subversion>.<patch>` branch; production sync is manual after the release promotion gate. Neither `main` nor `develop` is a direct production build source.

Changing an image tag is not a production promotion. A release starts from a protected numeric three-part branch such as `release/1.001.00` in `playsay-platform`; Jenkins labels its candidates `rel_1.001.00-N` and publishes immutable digests. After release tests, an explicitly approved promotion records the selected digest in the matching protected `playsay-infra` release branch and manually syncs prod. The deployed release branch remains available while that version is running. `main`, `develop`, free-form `release/*` names and direct `hotfix/*` builds cannot deploy prod; a hotfix must become a new three-part release branch. A prod rollback points the matching release values back to the previous known-good digest or previous retained release branch; images are not rebuilt during rollback.

### 5.1 Selective production seed from dev

The first production seed is an allowlist migration, not a dev database clone. The approved identity cohort is:

- Maria Mednova's active Keycloak account and matching `app_user`, preserving both the Keycloak subject and application UUID;
- the six active students whose `app_user.managed_by_teacher_user_id` points to Maria at the migration cutoff: Anton, Friend, Evgeniy Mednov, Irina Goryunova, Nikita and Sasha;
- their existing `student_profile` rows when present; an absent optional profile is not synthesized during migration;
- a separately bootstrapped production break-glass administrator, whose credentials are created directly in prod and are not copied from dev.

The protected migration manifest contains the seven exact Keycloak subjects and application UUIDs. Email addresses, subjects, password hashes and other identifiers are never committed to Git or written into this document. Display-name or email pattern matching is allowed only to prepare the manifest; execution must select by the reviewed immutable IDs. Any user outside that manifest is rejected by the import.

Material scope observed on 2026-07-20:

- select every `lesson_material` owned by Maria's application UUID except the explicitly identified test material `hello`;
- expected result: 22 materials: 8 `PUBLISHED` and 14 `DRAFT`; no Maria-owned `ARCHIVED` material is currently in scope;
- copy the 51 corresponding `material_asset` rows and every referenced MinIO object without changing storage keys;
- copy the 11 corresponding `material_html_game_enrichment` rows;
- retain original material UUIDs, timestamps, JSON documents, source metadata, scoring rubrics, visibility and status;
- verify object checksum/size before import and again from prod; a database row without its referenced object fails the migration.

The following dev history is deliberately not part of the initial seed: lessons and participants, assignments and recipients, submissions/scores, chats, collaboration documents, AI tutor sessions, pending registrations/invites, email delivery attempts, audit records, sessions and revoked tokens. At the observed cutoff this excludes 14 Maria lessons, 15 linked participant rows, 4 Maria assignments, 3 linked assignment recipients, 12 linked submissions and one empty cohort chat. Migrating any of this history requires a separate explicit decision because it may contain test activity.

Keycloak transfer uses a consistent offline CLI export while the source Keycloak pod is stopped for a short maintenance window. The exported user set is filtered to the seven reviewed subjects while retaining their IDs, realm roles and password credentials. Dev client secrets, redirect URIs, SMTP settings, sessions, events and operational tokens are not imported; prod receives independently generated secrets and `honey.school` redirect/origin settings. The filtered export is validated for exactly seven users before import. Users keep their passwords but must sign in again because sessions are not migrated.

Migration order is fixed:

1. deploy the clean prod schema and independent Keycloak/MinIO instances;
2. generate and review the protected seven-user/material manifest from a read-only source snapshot;
3. export and filter Keycloak during the maintenance window, restore the source pod, then import the seven users into prod;
4. import Maria and the six students into `app_user` with original IDs, then optional student profiles;
5. import the 22 materials, 51 assets and 11 enrichments, then copy their referenced MinIO objects;
6. validate foreign keys, exact counts, object checksums, Maria login, one student login and material rendering before any DNS cutover;
7. repeat the export from the final cutoff if source records changed after the rehearsal; never merge by title, email or display name.

### 5.2 Dev state bundle

Dev and prod use different artifacts. The dev bundle preserves the current development environment for continued work, while the prod bundle is the filtered seed from section 5.1.

The dev export scripts in Git create:

- a consistent logical dump of every application-owned PostgreSQL schema after write-producing jobs and application writes are frozen;
- a full offline Keycloak `playsay` realm export including all dev users and credentials, but excluding sessions/events that Keycloak does not export;
- a complete MinIO bucket copy with object version/checksum inventory;
- a sanitized Kubernetes inventory report used only to prove that Git/ArgoCD recreated the expected workloads; Kubernetes objects themselves are not restored from this report;
- a machine-readable manifest containing schema versions, counts, object checksums, source/destination commits and restore order.

The export is streamed into an encrypted restic repository; plaintext dumps exist only in a permission-restricted temporary directory on the source host and are removed after upload plus restore verification. The import scripts refuse a bundle whose manifest schema, source commit, checksum or target environment does not match.

Dev restore order is PostgreSQL/Keycloak/MinIO operators and empty services, Keycloak realm, PostgreSQL data, MinIO objects, application workloads, then Jenkins. ArgoCD auto-sync and Jenkins builds remain paused until the restored application passes schema, login, material-rendering and object checks.

## 6. Backup and recovery

Use a Hetzner Storage Box outside the AX41 as the backup destination:

- prod PostgreSQL logical dump every 6 hours;
- prod MinIO, k3s recovery material and application data daily through separate encrypted restic repositories over SFTP;
- dev application-data backups retained for 7 days;
- weekly VM-level backup uses a QEMU guest-agent quiesced external snapshot, copies the consistent qcow2 chain off-host, validates it and merges the temporary snapshot; guest-agent failure aborts rather than silently creating a crash-inconsistent prod backup;
- VM backup retention: 7 daily-equivalent restore points, 4 weekly and 6 monthly for prod; 4 weekly for dev;
- OpenTofu state is protected by S3 object versioning, not copied into VM backups;
- backup credentials are not shared between dev and prod workloads.

Once per month, restore the latest prod backup into an isolated VM with public networking disabled. The drill validates PostgreSQL, MinIO objects, Kubernetes secrets, Keycloak login and application startup. A backup is not valid until a restore succeeds.

## 7. OpenSpec-style change package and implementation tasks

### 7.1 Proposal

**Change ID:** `migrate-ax41-dev-prod`
**Status:** implementation in progress; encrypted source evacuation and physical-host/VPN baseline completed, VM creation not started
**Why:** the current 4-vCPU/8-GB VPS has persistent memory and I/O pressure and cannot safely host an isolated production environment.
**What changes:** the AX41 becomes an Ubuntu/KVM host with separate dev and prod VMs, Git/OpenTofu-managed infrastructure, VPN-only visual administration, independent GitOps clusters, encrypted off-host backup and a selective first production seed.
**Out of scope:** public root-site content, mail configuration, moving Russian-citizen production data to Finland, hardware HA and migration of Amnezia. The old VPS has only a three-day paid lifetime remaining and is intentionally deleted by the owner afterward; the plan must evacuate and verify all required data before that deadline.

Required capabilities:

1. `virtualized-dev-prod`: separate KVM guests and resource boundaries for dev and prod.
2. `git-managed-infrastructure`: reproducible OpenTofu/Ansible/ArgoCD/Jenkins configuration and reviewed plans.
3. `visual-operations`: VPN-only Cockpit, Headlamp, ArgoCD, Jenkins and monitoring without creating a second configuration authority.
4. `selective-production-seed`: exactly Maria, her six approved students and 22 approved materials excluding `hello`.
5. `recoverable-cutover`: immediate encrypted source evacuation, tested restore, DNS rollback during the remaining three-day old-server window and off-host recovery after deletion.

### 7.2 Design invariants and gates

- Dev and prod are separate VMs and separate k3s clusters; they never share Kubernetes control-plane state, databases, buckets, Keycloak or Sealed Secrets keys.
- The effective VM/network/storage configuration must be reproducible from a clean `playsay-infra` commit plus protected state/artifacts; no undocumented shell history is accepted.
- OpenTofu is authoritative. Cockpit may perform routine power operations, but configuration mutations require Git and a reviewed plan.
- Production apply, production ArgoCD sync and DNS cutover each require a separate human approval.
- Public SSH is not closed until VPN access is proven in a second independent session. Required source data must exist in a verified encrypted off-host bundle before the old VPS is deleted no later than the end of its remaining three-day paid period.
- Prod artifacts are built only from branches matching `release/<numeric>.<numeric>.<numeric>`; the same versioned branch identifies the reviewed product source and prod GitOps values. Production never builds directly from `main`, `develop` or `hotfix/*`.
- Any failed integrity, login, object-checksum, backup/restore, LiveKit/TURN or rollback gate stops progression to the next phase.
- Secrets, private keys, state, plans with sensitive values and migration data never enter Git.

### 7.3 Today-first execution order

This is the critical path for the first `honey.school` move. Object Storage is deliberately deferred and does not block these tasks:

- [x] **T1** Apply the Ansible local-state directories, check out the reviewed infra commit on AX41 and make an encrypted off-host copy around every OpenTofu apply. Latest platform/dev/prod bundles were copied off-host and decrypted/verified successfully; evidence: `migrations/ax41/evidence/20260720-opentofu-vms.md`.
- [x] **T2** Plan and apply `platform`, creating NAT-backed `playsay-workloads`/`virbr60` and the libvirt pool; verify no public administrative port is opened. Evidence: `migrations/ax41/evidence/20260720-opentofu-vms.md`.
- [x] **T3** Plan and create `playsay-prod` (`10.60.0.20`, 8 vCPU, 42 GB, 200 GB) and `playsay-dev` (`10.60.0.30`, 2 vCPU, 12 GB, 120 GB); verify guest agent, autostart and destroy protection. Evidence: `migrations/ax41/evidence/20260720-opentofu-vms.md`.
- [x] **T4** Bootstrap independent Ubuntu/k3s/ArgoCD environments from Git; dev and prod receive separate CIDRs, secrets, databases, MinIO and Keycloak. Both controllers and the prod PostgreSQL/Keycloak/MinIO data plane are Synced/Healthy from the matching release branch; evidence: `migrations/ax41/evidence/20260720-prod-seed-and-edge.md`.
- [ ] **T5** Create/protect `release/1.001.00`, build immutable release images and promote only their digests through the matching infra release branch. Do not deploy prod from `develop`, `main` or `hotfix/*`. Both release branches exist; successful web, AI tutor, vocabulary, media, payment, registration and keyboard-backend candidates are digest-pinned. Keyboard frontend is still building; API and collaboration require addressable retries, and email is rebuilding after a deterministic test-only fix.
- [ ] **T6** Configure the host edge and TLS for `online.honey.school`/`key.honey.school` to prod and `dev.online.honey.school`/`dev.key.honey.school` to dev. Keep Cockpit and future ops interfaces VPN-only; do not overwrite separately owned root-site/mail configuration. Exact-host nginx routes and a valid four-name Let's Encrypt certificate are active; prod online remains deliberately unaccepted until the release web/API rollout completes.
- [ ] **T7** Restore the full verified bundle into dev and run login, application, material, MinIO and Jenkins/ArgoCD smoke tests. Safety-v3 restore is complete and basic web/Keycloak/runtime checks pass; authenticated login and material-rendering checks remain.
- [x] **T8** Build the immutable-ID prod allowlist and import only Maria Mednova, her six approved students and 22 materials/51 assets/11 enrichments; refuse `hello`, other dev users and dev history. The protected allowlist is encrypted off Git; prod counts are `7/22/51/11`, `hello=0`, and 51 selected MinIO objects were streamed. Evidence: `migrations/ax41/evidence/20260720-prod-seed-and-edge.md`.
- [ ] **T9** Verify exact prod counts, Maria and one student login, every material/object, Keycloak redirects, API/WebSocket and LiveKit/TURN before accepting user traffic.
- [ ] **T10** Enable the already-resolving new hostnames at the AX41 edge, observe errors/latency/resources continuously and retain the old VPS unchanged as rollback through its paid lifetime.
- [ ] **T11** After stabilization, provision Object Storage, migrate the three OpenTofu states with locking/versioning and configure permanent encrypted off-site dev/prod backups before deleting the old VPS.

### 7.4 Task checklist

All unchecked tasks are pending. A phase is complete only when its exit check is recorded with the exact Git commit and non-secret evidence location.

#### Phase 0 — approve scope and establish change control

- [x] **0.1** Record the AX41 inventory, Ubuntu/mdadm/ext4 decision and initial `dev 2 vCPU/12 GB`, `prod 8 vCPU/42 GB`, host approximately 8 GiB allocation.
- [x] **0.2** Record the hostname split, one-public-IP/NAT design, VPN-only ops access and OpenTofu + Cockpit operating model.
- [x] **0.3** Freeze the initial prod allowlist contract: Maria, six named linked students, 22 materials excluding `hello`, 51 assets and 11 enrichments; exclude dev history.
- [x] **0.4** Create dedicated branch `codex/migrate-ax41-dev-prod`, rebase it onto current `origin/develop`, inventory unrelated working-tree changes and isolate migration work without discarding them. Foundation commit: `d0697fc`; the branch is pushed without `graphify-out`, private inventory, VPN profiles, keys, dumps or state.
- [ ] **0.5** Choose owners for infrastructure review, prod apply, DNS cutover and rollback; record the exact old-VPS deletion deadline within the remaining three-day paid period, maintenance windows and communication channel.
- [ ] **0.6** Record the exact current `playsay-platform` and `playsay-infra` revisions, image digests and current DNS answers as the pre-change baseline.
- [ ] **0.7** Create a migration decision log and evidence directory containing no credentials or personal identifiers.

**Exit check:** scope, owners, repositories, source revisions, expected data counts and rollback authority are unambiguous.

#### Phase 1 — evacuate the expiring VPS, then make AX41 recoverable

- [ ] **1.1** Record the exact provider cutoff/deletion time for the old VPS and treat the remaining three-day period as the hard rollback deadline.
- [x] **1.2** Create an encrypted safety bundle of current application PostgreSQL, full Keycloak PostgreSQL state including identities/credentials, MinIO objects, required Sealed Secrets recovery material and non-secret Git/runtime inventory. The initial safety capture uses consistent PostgreSQL 17 logical dumps without service interruption; the final selective prod transfer still requires the planned offline Keycloak export.
- [x] **1.3** Copy the corrected safety bundle off the old VPS, verify transport and payload checksums, require non-empty PostgreSQL 17 table-data catalogs and test decrypt/archive restoration; do not rely on the old VPS as the only copy. Safety-v2 is superseded for application recovery; authoritative evidence: `migrations/ax41/evidence/20260720-safety-v3.md`.
- [ ] **1.4** Confirm that public site/mail data owned outside this migration is separately preserved; record that Amnezia is intentionally not migrated and will end when the VPS is deleted.
- [ ] **1.5** Verify Hetzner Robot/rescue access and the authorized AX41 SSH key in two independent sessions; store recovery credentials outside Git.
- [x] **1.6** Wait for AX41 mdadm RAID1 synchronization to finish and save non-secret `/proc/mdstat`, array-detail and filesystem-capacity evidence. Evidence: `migrations/ax41/evidence/20260720-ax41-host-vpn.md`.
- [x] **1.7** Run SMART/NVMe health checks for both AX41 drives; stop if either drive or RAID member is degraded. Both drives passed with zero media/integrity errors; evidence: `migrations/ax41/evidence/20260720-ax41-host-vpn.md`.
- [ ] **1.8** Capture the current AX41 Ubuntu packages, network, firewall, mounts and boot configuration before automation changes.
- [x] **1.9** Patch AX41 Ubuntu to kernel `6.8.0-136-generic` and complete the reboot gate; RAID, network, SSH, libvirt, WireGuard, UFW and VPN-only Cockpit recovered. Evidence: `migrations/ax41/evidence/20260720-ax41-host-vpn.md`.
- [ ] **1.10** Configure AX41 health alerts for RAID degradation, NVMe errors, filesystem thresholds and `MemAvailable < 4 GiB for 15 minutes`.

**Depends on:** Phase 0.
**Exit check:** the old VPS data has a verified encrypted off-host restore path, and the AX41 host is healthy, recoverable and monitored; no VM has been created yet.

#### Phase 2 — build the Git/OpenTofu control plane

- [x] **2.1** Create the versioned `terraform/modules/libvirt-vm` module with cloud-init, CPU/RAM, qcow2, network, autostart and QEMU guest-agent support; local backend-disabled initialization and validation passed.
- [x] **2.2** Create separate `platform`, `dev` and `prod` OpenTofu roots and separate states; pin OpenTofu 1.12.x and `dmacvicar/libvirt` 0.9.8 and generate each provider lock file. The accelerated cutover uses the documented local-state exception and does not wait for task 2.3.
- [ ] **2.3** After the first production stabilization window, provision an independent versioned/locked encrypted S3-compatible state backend, inject credentials only at runtime and migrate all three temporary local states with verification.
- [x] **2.3a** Before VM creation, apply the `0700` local-state directories on AX41, enforce a single named operator/no Jenkins apply and test encrypted off-host state capture and restore. All three current bundles verified; evidence: `migrations/ax41/evidence/20260720-opentofu-vms.md`.
- [x] **2.4** Add `prevent_destroy` to managed VM domains and disks so a destroy/replacement plan is rejected before apply; the provider's tainted cloud-init replacement was refused by this lifecycle gate during bootstrap and was reconciled through a new Git plan.
- [ ] **2.5** Add format, validate and read-only plan jobs with human-readable plan summaries; ensure plan artifacts cannot expose secrets.
- [ ] **2.6** Require a separate manual approval for every apply and an additional prod approval; merging a pull request must not auto-apply prod.
- [ ] **2.7** Add a scheduled read-only drift plan and alert on exit code `2`; document reconciliation of Cockpit/`virsh` break-glass changes.
- [ ] **2.8** Write the Git workflow for change, review, plan checksum, apply record and rollback commit/digest.

**Depends on:** Phase 1 for live provider validation; code can be drafted after Phase 0.
**Exit check for first cutover:** validation is green, the temporary local-state controls and encrypted off-host copy are proven, and a reviewed plan contains no unexpected destroy/replace action. **Steady-state exit check:** remote-state migration, versioning and locking are proven after stabilization.

#### Phase 3 — automate and secure the AX41 host

- [x] **3.1** Implement idempotent Ansible roles/playbook for KVM/QEMU/libvirt, storage pool, QEMU tooling and hardware-acceleration checks without repartitioning or replacing mdadm/ext4. Applied to AX41 and re-run with `changed=0`; evidence: `migrations/ax41/evidence/20260720-ax41-host-vpn.md`.
- [ ] **3.2** Implement the `10.60.0.0/24` bridge, nftables default-deny policy, NAT and the explicit prod/dev LiveKit/TURN port split. The libvirt bridge and NAT are active; the prod-only `3478`, `7881` and `50000-50020` UFW/DNAT rules are committed and require apply plus forced-relay verification. The non-overlapping dev public range remains a later change.
- [ ] **3.3** Deploy WireGuard management networking on `10.250.0.0/24`, add computer and phone peers and verify both work behind carrier/private IPv4 NAT.
- [ ] **3.4** Verify host SSH, guest SSH, libvirt administration and ops interfaces over VPN in a second session; only then remove public administrative access.
- [x] **3.5** Install Cockpit + Machines through Ansible, bind it only to `10.250.0.1:9090`, use the named `playsay` administrator and system journal audit trail. Public access timed out and a temporary external VPN peer received HTTP 200; evidence: `migrations/ax41/evidence/20260720-ax41-host-vpn.md`.
- [ ] **3.6** Implement the minimal edge proxy for prod/dev hostnames without overwriting the separately owned public root site or mail configuration.
- [ ] **3.7** Reboot the host and verify VPN, firewall, bridge, Cockpit, RAID and monitoring return automatically.

Reboot note: host-level VPN, firewall, Cockpit, RAID, libvirt and SMART monitoring recovery passed after correcting Cockpit startup ordering. Task 3.7 remains open only because the managed `virbr60` bridge does not exist until Phase 4 platform apply.

**Depends on:** Phases 1 and 2.
**Exit check:** the public Internet cannot reach administrative interfaces; VPN clients can visually inspect the host and libvirt without configuration drift.

Implementation note: the server tunnel and both permanent peer definitions are active, and ready-to-import profiles exist outside Git. Task 3.3 remains open until the real MacBook and phone each establish a handshake from their normal private/carrier-NAT networks. Public SSH therefore remains enabled.

#### Phase 4 — create the isolated VMs from Git

- [x] **4.1** Produce clean reviewed `platform` plans and apply the libvirt pool plus NAT network. The NAT addition deliberately replaced only the still-empty network with both guests shut down; evidence: `migrations/ax41/evidence/20260720-opentofu-vms.md`.
- [x] **4.2** Create `playsay-dev` at `10.60.0.30`, Ubuntu 24.04, 2 vCPU, 12 GB RAM and maximum 120-GB qcow2; SSH, cloud-init, guest agent and autostart pass.
- [x] **4.3** Create `playsay-prod` at `10.60.0.20`, Ubuntu 24.04, 8 vCPU, 42 GB RAM and maximum 200-GB qcow2; SSH, cloud-init, guest agent, autostart and lifecycle protection pass.
- [x] **4.4** Apply CPU/I/O priorities so prod wins contention (I/O weights 900 versus 300); keep dev CI serialized.
- [ ] **4.5** Reboot the host with both guests enabled and verify independent recovery, correct addresses and no startup-order dependency.
- [ ] **4.6** Run a controlled dev CPU/memory/disk stress test and confirm host reserve, prod responsiveness and storage thresholds.

**Depends on:** Phase 3.
**Exit check:** both empty guests are reproducible from Git, recover after reboot and honor resource/security boundaries.

#### Phase 5 — bootstrap independent Kubernetes and delivery environments

- [ ] **5.1** Implement guest Ansible for Ubuntu hardening, pinned k3s, backup agent and node monitoring.
- [ ] **5.2** Bootstrap dev k3s with pod/service CIDRs `10.42.0.0/16` and `10.43.0.0/16`; install new or deliberately restored dev Sealed Secrets keys and dev ArgoCD.
- [ ] **5.3** Recreate dev namespaces, operators, applications, Headlamp and Jenkins only from the pinned Git commit; do not restore Kubernetes or Jenkins controller state.
- [ ] **5.4** Add complete `argocd-apps/prod` and prod Helm values using independent credentials, storage, Keycloak, LiveKit/TURN and external integrations. Data-plane apps and digest-pinned values for completed release candidates are present; email/payment deployment remains disabled until separate prod provider credentials are supplied.
- [ ] **5.5** Bootstrap prod k3s with pod/service CIDRs `10.44.0.0/16` and `10.45.0.0/16`, a new prod Sealed Secrets key and independent ArgoCD.
- [ ] **5.6** Enforce dev auto-sync from `develop`; accept prod candidates only from protected branches matching `release/<numeric>.<numeric>.<numeric>`, use the matching `playsay-infra` release branch with manual ArgoCD sync, and promote immutable digests rather than mutable tags.
- [ ] **5.7** Add branch validation so free-form `release/*`, `main`, `develop` and `hotfix/*` cannot update prod values; a hotfix must be released as a new three-part release branch.
- [ ] **5.8** Verify no network path from dev workloads to prod private services except explicitly approved shared egress.

**Depends on:** Phase 4.
**Exit check:** clean dev/prod clusters reach `Synced/Healthy` with independent control planes and empty stateful services.

#### Phase 6 — implement migration and verification tooling in Git

- [ ] **6.1** Add a manifest schema, target-environment guard, source commit/image digests, expected counts and SHA-256 checksums.
- [ ] **6.2** Implement a full dev exporter/importer for PostgreSQL, offline Keycloak realm/users and complete MinIO content, streamed to encrypted off-host storage.
- [ ] **6.3** Implement the prod allowlist generator using immutable Keycloak subjects, application/material UUIDs and object keys; names are preparation aids only.
- [ ] **6.4** Implement filtered Keycloak export/import retaining exactly seven approved identities and credentials but excluding sessions, events, dev clients, secrets, redirect URIs and SMTP configuration.
- [ ] **6.5** Implement ordered prod import for users/profiles, 22 materials, 51 assets, 11 enrichments and referenced MinIO objects while preserving IDs and timestamps.
- [ ] **6.6** Add refusal checks for `hello`, any unapproved user, any history table row, a missing object, mismatched checksum/count or wrong target environment.
- [ ] **6.7** Add automated verification for referential integrity, exact counts, logins, object retrieval/checksums, material rendering and absence of excluded history.
- [ ] **6.8** Prove plaintext temporary exports are permission-restricted and removed after encrypted upload and verified restore.

**Depends on:** Phase 0 data contract; execute tests against Phase 5 clusters.
**Exit check:** migration scripts are reviewed, repeatable and fail closed on every scope/integrity violation.

#### Phase 7 — establish backup and restore before cutover

- [ ] **7.1** Provision separate encrypted Storage Box/restic repositories and credentials for dev and prod.
- [ ] **7.2** Configure prod PostgreSQL dumps every 6 hours, daily application/MinIO recovery material and documented retention.
- [ ] **7.3** Implement QEMU guest-agent-quiesced VM backup; abort when quiescing fails and safely merge external snapshots after off-host verification.
- [ ] **7.4** Restore the latest dev and empty-prod backups into isolated no-public-network guests.
- [ ] **7.5** Measure restore time and record RPO/RTO evidence; fix the process before any live migration if restore fails.

**Depends on:** Phases 4–6.
**Exit check:** both configuration and data have a verified off-host restore path.

#### Phase 8 — rehearse and cut over dev

- [ ] **8.1** Rehearse a complete dev export/restore into the new dev cluster without changing DNS; run login, material, MinIO and application smoke tests.
- [ ] **8.2** Verify one full Jenkins → GHCR → Git tag/value update → ArgoCD delivery on the new dev environment.
- [ ] **8.3** Baseline build time, lesson CPU excluding iowait, working set, disk latency and LiveKit quality; keep dev at 2 vCPU unless the documented scale trigger is reproduced.
- [ ] **8.4** Announce final dev freeze, pause Jenkins/ArgoCD and write-producing workloads, and capture the final encrypted bundle.
- [ ] **8.5** Restore and verify the final bundle, switch `dev.online`, `dev.key` and `dev.ops` routing, then resume delivery.
- [ ] **8.6** Keep the former dev source untouched only until the hard three-day VPS deletion deadline and prove reverse routing during that window; after deletion, rollback relies on the verified encrypted bundle rather than the VPS.

**Depends on:** Phases 5–7.
**Exit check:** development and CI operate on AX41 from Git with complete restored dev state and a tested rollback.

#### Phase 9 — rehearse and seed prod

- [ ] **9.1** Generate the protected immutable-ID allowlist from a read-only source snapshot and obtain a two-person review of the seven users/material/object scope.
- [ ] **9.2** Rehearse the filtered seed into a disposable clean prod database/realm/bucket and run every Phase 6 verification without DNS changes.
- [ ] **9.3** Create the independent break-glass prod administrator and prod-only secrets/integrations; do not copy dev secrets.
- [ ] **9.4** Build from a protected `release/<version>.<subversion>.<patch>` branch, promote its tested `rel_<version>.<subversion>.<patch>-N` immutable digest through the matching infra release branch, manually sync prod and verify rollback to the previous digest/release.
- [ ] **9.5** At final cutoff, briefly stop source Keycloak for the offline export, create the final protected bundle, restore the source service and import only into clean prod.
- [ ] **9.6** Verify exactly seven migrated users plus the independent administrator, exactly 22 Maria materials, 51 assets and 11 enrichments; verify `hello` and all excluded history are absent.
- [ ] **9.7** Verify Maria and one reviewed student can sign in with existing credentials, render materials and retrieve every referenced object.

**Depends on:** Phases 6–8.
**Exit check:** prod contains only the approved seed, is independently secured and can roll back by application digest.

#### Phase 10 — routing, TLS and controlled production cutover

- [ ] **10.1** Confirm Dynadot records for `online.honey.school`, `dev.online.honey.school`, `key`, `dev.key`, `ops`, `dev.ops` and optional `www`; preserve mail records and root-site ownership.
- [ ] **10.2** Issue/verify certificates only after DNS resolves and configure exact host routing; keep all ops routes VPN-only despite public DNS names.
- [ ] **10.3** Run pre-cutover smoke through explicit host resolution without changing user traffic: web, API, Keycloak redirect/origin, WebSocket, MinIO, LiveKit and forced TURN relay.
- [ ] **10.4** Record current DNS answers, switch production routing in the approved window and continuously watch HTTP errors, latency, CPU/RAM/I/O and LiveKit quality.
- [ ] **10.5** If any critical acceptance gate fails, restore the previous DNS/routing immediately; do not repair production data in place during the cutover window.

**Depends on:** Phase 9.
**Exit check:** public product routes use AX41 with valid TLS and healthy application/media flows; old routing still works as rollback.

#### Phase 11 — prove clean reconstruction and close the migration

- [ ] **11.1** Run every acceptance item in section 8 and attach non-secret evidence to the recorded infrastructure commit.
- [ ] **11.2** Recreate both VMs/clusters in an isolated drill from the recorded Git commit plus encrypted artifacts; demonstrate no dependency on shell history or copied k3s/PVC state.
- [ ] **11.3** Run the scheduled drift plan and require an empty result; reconcile any emergency/manual differences before sign-off.
- [ ] **11.4** Use only the remaining portion of the three-day paid period as the old-VPS rollback bridge while confirming zero residual product traffic and successful final off-host backup.
- [ ] **11.5** Before the provider cutoff, create and verify one final encrypted source bundle and confirm the AX41 or an isolated restore can read it; this gate is mandatory even if production cutover is not yet complete.
- [ ] **11.6** Let the owner delete the old VPS at the end of the paid period after explicit confirmation that required site/mail data is separately preserved; Amnezia terminates with that VPS and is not migrated.
- [ ] **11.7** After deletion, verify DNS has no required route to the retired address, backups remain readable and no operational procedure depends on old Amnezia or the old host.
- [ ] **11.8** Mark this change implemented only when AX41 acceptance passes, update runtime addresses/status in `spec.md` and the runbook, and archive the final migration/rollback report without secrets. If only data evacuation completed by the deadline, keep the change open and continue from the off-host bundle.

**Depends on:** Phase 10 for normal cutover, but tasks 11.5–11.7 are bounded by the hard three-day VPS deadline even if earlier implementation work is incomplete.
**Exit check:** the AX41 topology is reproducible, monitored and recoverable; the old VPS and Amnezia are retired, and verified off-host bundles—not the deleted VPS—provide the remaining recovery path.

## 8. Acceptance and exit triggers

Acceptance requires:

- mdadm RAID1 healthy and both NVMe devices pass SMART checks before and after reboot;
- KVM hardware acceleration is active and both VMs recover through libvirt autostart;
- host/libvirt/guest administration is unreachable outside the management VPN;
- OpenTofu plan contains no unapproved replacement or destroy;
- a clean-room run from the recorded Git commit creates the host-managed network, both VMs, k3s, ArgoCD applications and Jenkins without undocumented manual configuration;
- no raw dump, Keycloak credential export, private key, kubeconfig, OpenTofu state or MinIO teaching object exists in Git history;
- encrypted dev/prod bundles match the checksums and source commits recorded by the migration manifests;
- a verified encrypted source safety bundle exists off the old VPS before its three-day paid period ends and remains restorable after that VPS is deleted;
- at least 70 GB physical storage remains free after initial provisioning;
- no route from dev workloads to prod private services except explicitly approved shared egress;
- independent ArgoCD, Sealed Secrets, databases, buckets and Keycloak identities;
- the running prod images were built from a protected `release/<numeric>.<numeric>.<numeric>` branch, match the recorded `rel_<version>.<subversion>.<patch>-N` digests and were manually synced through the matching infra release branch;
- prod seed contains exactly the reviewed seven migrated Keycloak users plus the independently created break-glass administrator, with no other dev account;
- prod contains exactly 22 Maria-owned migrated materials; the test material `hello` is absent;
- all 51 migrated asset rows and 11 HTML-game enrichments resolve successfully, and every referenced MinIO object matches its source checksum;
- Maria and a reviewed student can sign in with their existing credentials and retain the original Keycloak/application identity mapping;
- no dev lesson, assignment, submission, chat or pending-registration history is present in prod;
- the restored dev environment retains its complete PostgreSQL, Keycloak and MinIO state while Kubernetes/ArgoCD/Jenkins configuration is demonstrably recreated from Git;
- a saturated dev Jenkins build does not violate prod API/LiveKit thresholds;
- prod and dev LiveKit/TURN pass forced-relay tests concurrently;
- monthly-style restore succeeds from the Storage Box;
- old-server rollback works during the remaining three-day bridge, and off-host-bundle recovery works after the old VPS and its non-migrated Amnezia service are removed.

The single-server topology must be replaced or split when any of these becomes true:

- production needs hardware HA or an RTO that one AX41 cannot meet;
- dev load measurably degrades prod despite VM limits;
- prod remains above 70% CPU or 80% memory during normal peak windows;
- physical storage free space falls below 15%;
- Russian citizens' personal data enters scope, requiring the Russian production topology defined in `spec.md`.
