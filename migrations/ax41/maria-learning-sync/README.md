# Maria learning-data synchronization

This package has three fixed-route Python entrypoints:

- `sync_vdsina_to_dev.py` exports Maria's graph from VDSina and applies it to dev;
- `sync_student_identity_dev_to_prod.py` copies one explicitly selected missing
  student identity from dev Keycloak to prod Keycloak without changing the
  immutable subject or password credential;
- `sync_dev_to_prod.py` creates a new snapshot from the accepted dev state and
  applies that snapshot to production.

The route is recorded in the encrypted bundle manifest and cannot be overridden
on the command line. The internal shell driver is an implementation detail.

The source is authoritative only inside the selected Maria learning graph. That
graph includes Maria, her related students, materials and MinIO assets, HTML games
and game adaptations, lessons/templates/participants/reminders, assignments and
submissions, collaboration snapshots, and complete student vocabulary/practice
state. Portable snapshots keep selected participants and referenced content but
clear nullable management/creator/owner links to users outside the selected
cohort; those unrelated accounts and learning graphs are not imported. An apply
removes target-only lesson, assignment and vocabulary records
inside that graph. Target-only material/template rows and their MinIO objects are
preserved because they may be referenced outside Maria's destructive scope; source
rows with matching IDs are still updated. It never deletes target-only user
accounts. Material/template selection is transitively closed across every selected
lesson, assignment, participant override, annotation, collaboration document and
template card. YouTube caches/references and HTML-game enrichments are merged by
their database natural keys, preserving an existing target UUID while applying
accepted source data and remapping incoming references. Chats, AI Tutor,
delivery/audit data, sessions and integration outboxes
are not copied.

## Safety contract

- Run each source export only during a full write freeze. Keep the legacy contour
  read-only until production acceptance, and do not resume dev writers until its
  production snapshot is complete.
- Supply Maria's exact Keycloak subject through a protected file. Names and email
  addresses are never selectors and are never written to the manifest.
- Learning-data `apply` requires a target Keycloak subject inventory. A missing
  cohort subject blocks the import; create the one reviewed missing student first
  with `sync_student_identity_dev_to_prod.py`, then regenerate the inventory.
- Identity selection uses an exact immutable subject from a mode-`0600` file.
  The identity tool refuses username/email conflicts, unsupported group,
  federation or consent relations, a missing password credential and any source
  `UPDATE_PASSWORD` action. It never accepts a username, email or display name as
  a selector and never prints PII or credential material.
- Identity `apply` requires both dev and prod Keycloak to be stopped, performs a
  rollback-only SQL preflight, creates and decrypt-verifies an encrypted full prod
  Keycloak PostgreSQL backup, writes in one serializable transaction and compares
  the complete portable identity fingerprint afterward. Failed verification
  automatically restores the prod Keycloak database.
- Run `plan` and review its UUID/count-only report before `apply`.
- `apply` requires `--confirm-manifest-sha256` and a writable backup directory;
  the Python entrypoint fixes the target environment. Production additionally requires
  `--operator-production-approval`.
- Application, collaboration, vocabulary, reminder and media workloads must be
  stopped for `apply` and `rollback`. The tool verifies the operator-supplied
  maintenance guard command before touching data.
- No database URL or S3 credential is accepted on the command line. Configure a
  libpq service (`PGSERVICE`) and an authenticated MinIO Client alias (`mc alias`)
  in the operator environment.

## 1. VDSina to dev

```bash
python3 ./sync_vdsina_to_dev.py export \
  --pg-service legacy-playsay \
  --maria-subject-file /secure/maria.subject \
  --s3-alias legacy \
  --s3-bucket playsay-material-assets \
  --public-key /secure/migration-public.pem \
  --output-dir /secure/bundles \
  --platform-commit <sha> \
  --infra-commit <sha>

python3 ./sync_vdsina_to_dev.py verify-bundle \
  --bundle /secure/bundles/<bundle>.tar.gz.enc \
  --encrypted-key /secure/bundles/<bundle>.key.enc \
  --private-key /secure/migration-private.pem

python3 ./sync_vdsina_to_dev.py plan \
  --pg-service ax41-dev-playsay \
  --bundle ... --encrypted-key ... --private-key ... \
  --target-subjects-file /secure/dev-keycloak-subjects

python3 ./sync_vdsina_to_dev.py apply \
  --pg-service ax41-dev-playsay \
  --s3-alias ax41-dev \
  --s3-bucket playsay-material-assets \
  --bundle ... --encrypted-key ... --private-key ... \
  --target-subjects-file /secure/dev-keycloak-subjects \
  --backup-dir /secure/backups/dev \
  --backup-public-key /secure/migration-public.pem \
  --maintenance-guard-command /secure/assert-dev-maintenance \
  --confirm-manifest-sha256 <sha256>

python3 ./sync_vdsina_to_dev.py verify-target <the same target and bundle arguments>
```

## 2. Accepted dev to production

After Maria and one student accept dev, create a fresh encrypted snapshot from
dev. Do not reuse the VDSina-to-dev bundle. Configure four separate libpq
services on the trusted operator workstation: dev/prod application PostgreSQL and
dev/prod Keycloak PostgreSQL. Service names contain no credentials; the matching
passwords stay in the protected libpq service/pass files.

### One-command operator launcher

The recommended workstation path is the fail-closed launcher. It discovers the
Kubernetes service ClusterIPs read-only and owns isolated direct SSH tunnels on
ports `56432-56435` and `59100-59101`, so close any manual migration tunnel
windows first. It reads Kubernetes secret values directly into
mode-`0600` local profiles without printing them, discovers Maria and the reviewed
cohort from the already verified encrypted VDSina-to-dev bundle, and transfers
every cohort identity missing from prod before learning data. Run preflight first:

```bash
./run_dev_to_prod_operator.sh
```

If all database/MinIO checks and identity plans pass, execute the complete window:

```bash
./run_dev_to_prod_operator.sh --apply
```

The apply path requires typing `APPLY PROD`. It records exact deployment,
Keycloak and ArgoCD replicas, freezes both contours, creates encrypted identity and
learning backups, performs a fresh dev-to-prod export/plan/apply/verify, restores
the recorded replicas even on failure, closes its tunnels and checks public prod
endpoints. Its default secure directory and reviewed source-bundle directory are
under `$HOME/Backups/PlayAndSay/migrations`; use the documented `MIGRATION_*`
environment overrides from `--help` only when those artifacts were moved.
After a fail-closed interruption, rerun the same command: the launcher rebuilds
the production identity inventory, keeps already verified identities and resumes
with only the reviewed cohort identities that are still absent.
If the reviewed bundle directory contains only the RSA private key, the launcher
derives its public PEM locally and stores that non-secret key in the protected
working directory.

The explicit commands below remain the recovery/debug procedure.

Stop every dev and prod application writer, both Keycloak instances and both
ArgoCD application controllers. Guards must independently verify the stopped
source and target Keycloak states. First migrate the one missing student identity:

```bash
chmod 600 /secure/student.subject

python3 ./sync_student_identity_dev_to_prod.py plan \
  --source-pg-service ax41-dev-keycloak \
  --target-pg-service ax41-prod-keycloak \
  --student-subject-file /secure/student.subject

python3 ./sync_student_identity_dev_to_prod.py apply \
  --source-pg-service ax41-dev-keycloak \
  --target-pg-service ax41-prod-keycloak \
  --student-subject-file /secure/student.subject \
  --backup-dir /secure/backups/prod-keycloak \
  --backup-public-key /secure/migration-public.pem \
  --backup-private-key /secure/migration-private.pem \
  --source-maintenance-guard-command /secure/assert-dev-keycloak-stopped \
  --target-maintenance-guard-command /secure/assert-prod-keycloak-stopped \
  --operator-production-approval

python3 ./sync_student_identity_dev_to_prod.py verify \
  --source-pg-service ax41-dev-keycloak \
  --target-pg-service ax41-prod-keycloak \
  --student-subject-file /secure/student.subject

python3 ./sync_student_identity_dev_to_prod.py export-inventory \
  --target-pg-service ax41-prod-keycloak \
  --output /secure/prod-keycloak-subjects
```

`verify` must report `updatePasswordRequired:false`. The source password hash,
credential parameters, attributes, required actions and realm/client roles are
copied; environment-specific role IDs and realm IDs are mapped to prod. Sessions,
tokens and transient login state are not copied. Regenerate
`/secure/prod-keycloak-subjects` from prod after identity verification; the
command writes subjects only to a mode-`0600` file and prints only their count.

Then export and apply the accepted learning graph:

```bash
python3 ./sync_dev_to_prod.py export \
  --pg-service ax41-dev-playsay \
  --maria-subject-file /secure/maria.subject \
  --s3-alias ax41-dev \
  --s3-bucket playsay-material-assets \
  --public-key /secure/migration-public.pem \
  --output-dir /secure/bundles/dev-to-prod \
  --platform-commit <accepted-dev-sha> \
  --infra-commit <sha>

python3 ./sync_dev_to_prod.py plan \
  --pg-service ax41-prod-playsay \
  --bundle ... --encrypted-key ... --private-key ... \
  --target-subjects-file /secure/prod-keycloak-subjects

python3 ./sync_dev_to_prod.py apply \
  --pg-service ax41-prod-playsay \
  --s3-alias ax41-prod \
  --s3-bucket playsay-material-assets \
  --bundle ... --encrypted-key ... --private-key ... \
  --target-subjects-file /secure/prod-keycloak-subjects \
  --backup-dir /secure/backups/prod \
  --backup-public-key /secure/migration-public.pem \
  --maintenance-guard-command /secure/assert-prod-maintenance \
  --confirm-manifest-sha256 <sha256> \
  --operator-production-approval
```

Run `verify-bundle` and review `plan` for the second bundle before `apply`, then
run `verify-target`. `rollback` requires the backup directory created by the
matching apply, the same maintenance guard, and production approval for prod.
If the complete migration must be rolled back, restore learning data first and
the Keycloak identity second:

```bash
python3 ./sync_dev_to_prod.py rollback \
  --pg-service ax41-prod-playsay \
  --s3-alias ax41-prod \
  --s3-bucket playsay-material-assets \
  --backup-dir /secure/backups/prod \
  --private-key /secure/migration-private.pem \
  --maintenance-guard-command /secure/assert-prod-maintenance \
  --confirm-backup-id <learning-backup-id> \
  --operator-production-approval

python3 ./sync_student_identity_dev_to_prod.py rollback \
  --target-pg-service ax41-prod-keycloak \
  --backup-dir /secure/backups/prod-keycloak \
  --backup-private-key /secure/migration-private.pem \
  --target-maintenance-guard-command /secure/assert-prod-keycloak-stopped \
  --confirm-backup-id <keycloak-backup-id> \
  --operator-production-approval
```

The script prints only bundle IDs, UUID-based counts, hashes and operation counts.
Do not attach decrypted CSV files, subject inventories, object keys or database
backups to tickets or Git.

After dev and production acceptance, copy `evidence-template.md` into the parent
`evidence/` directory with the execution date and fill only its non-secret fields.
