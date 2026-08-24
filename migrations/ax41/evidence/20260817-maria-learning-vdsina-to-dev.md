# Maria learning synchronization — VDSina to dev — 2026-08-17

This record contains no subjects, emails, student names, object keys, credentials,
decrypted paths or private backup locations.

- Bundle ID: `maria-learning-vdsina-to-dev-20260817T135517Z`
- Manifest SHA-256: `865e1bdd550b81034a44dd09a6c494127ab2d45b37ead3e21fce12b40e32b5db`
- Source cutoff UTC: `2026-08-17T13:55:17Z`
- Source platform commit: `92406096f13b2451086d39021f8febfab855dbdc`
- Infra commit recorded by exporter: `fe3b714905c8aab87b1f71bb4ba484692617c1f3`
- Scope counts: 9 users, 80 lessons, 96 materials, 80 assignments,
  179 vocabulary entries and 0 source vocabulary practices.
- MinIO selection: 235 objects, 258,613,816 aggregate bytes.
- Compatibility rule: VDSina predates material-game-adaptation and vocabulary
  practice state. Missing newer source tables were represented as empty/defaulted
  compatibility rows. Target-only material/template/game rows and 39 associated
  objects were preserved; target-only lesson/assignment/vocabulary state remained
  authoritative-delete.
- Identity gate: one missing dev student identity was imported with the original
  immutable subject and password hash. No `UPDATE_PASSWORD` action was added.
  A full encrypted dev Keycloak database backup was verified before the import.
- Dev plan: reviewed after identity and external-reference gates passed.
- Dev application backup ID:
  `maria-learning-vdsina-to-dev-20260817T135517Z-dev-20260817T142859Z`.
- Apply result: complete.
- Independent target verification: database rows and all 235 object checksums
  verified after apply.
- Runtime verification: 12 pods running/ready with zero restarts; 19 ArgoCD
  applications Synced/Healthy; Keycloak 1/1 ready; public dev web, keyboard and
  issuer endpoints returned HTTP 200; no new error/exception matches in the API,
  vocabulary or collaboration service startup window.
- Dev Maria + student browser acceptance: pending owner verification.
- Dev-to-production snapshot/apply: not run.
- Legacy contour: application writers, Keycloak and ArgoCD controller remain
  stopped and the contour remains read-only pending acceptance.
