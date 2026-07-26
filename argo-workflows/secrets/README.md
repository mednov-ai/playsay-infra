# Argo Workflows production secret contract

No plaintext production secret is stored in Git. Before activation, create these
Secrets through Sealed Secrets or an equivalent owner-operated encrypted path:

- `argo-workflows-system/playsay-release-sso`
  - `client-id`
  - `client-secret`
- `playsay-release-system/playsay-release-github`
  - `app-id`
  - `installation-id`
  - `private-key.pem`
- `playsay-data/playsay-release-backup`
- `keycloak/playsay-release-backup`
- `storage/playsay-release-backup`
  - `endpoint`
  - `region`
  - `bucket`
  - `access-key`
  - `secret-key`
  - `age-recipient`

The GitHub App is installed only on `mednov-ai/playsay-platform` and
`mednov-ai/playsay-infra`. It needs read-only metadata/checks access plus
Contents and Pull requests read/write. The backup secret carries only a public
age recipient; the age private identity stays outside the production cluster.

Activation must fail until the S3 bucket reports both versioning and Object Lock
enabled and a restore drill has decrypted and restored a test artifact.
