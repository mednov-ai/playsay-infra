# AX41 migration bundles

This directory contains versioned migration and verification code only. Dumps,
private keys, OpenTofu state, MinIO objects and encrypted bundles never belong in
Git.

The immediate source-VPS safety workflow is:

1. Generate a dedicated RSA private/public key pair on the operator workstation.
2. Copy only the public key and `export-dev-safety.sh` to the source VPS.
3. Run the exporter as root with the exact platform/infra commits.
4. Download the `.tar.gz.enc`, `.key.enc`, `.transport.sha256` and non-secret
   `.manifest.json` files to protected off-host storage.
5. Run `verify-encrypted-bundle.sh` with the private key. Plaintext exists only in
   a permission-restricted temporary directory and is deleted on exit.
6. Copy the private key to a second secure offline location before deleting the
   source VPS. Never put it in this repository or the encrypted-bundle directory.

This safety bundle is a full dev disaster-recovery artifact. It is not the
selective production seed; the latter must use the reviewed immutable-ID allowlist
and refusal checks described in the AX41 migration plan.
