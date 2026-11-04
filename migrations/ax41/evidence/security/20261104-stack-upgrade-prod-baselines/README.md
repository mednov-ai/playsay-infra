# Fresh production baseline image scans — 2026-11-04

The five raw Trivy JSON reports are losslessly gzipped; `raw-sha256.txt` lists the hashes of the uncompressed files. CI `playsay-keycloak-develop` #39 scanned the exact running production Keycloak, application PostgreSQL and Bitnami identity PostgreSQL images, and the previously tested DEV Keycloak and PostgreSQL candidates, with one fresh vulnerability database. This job did not publish images or deploy. Its scanner and database metadata are retained here. The scanned Keycloak candidate is the DEV image, not a newly built image from the separate production-baseline source.

The reports list installed packages and unresolved findings; matching CVE/package identifiers do not establish identical exposure or risk acceptance. See [the comparison](comparison.md) and [preparation evidence](../../20261104-stack-upgrade-prod-preparation.md).
