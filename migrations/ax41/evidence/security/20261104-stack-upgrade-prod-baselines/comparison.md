# Production baseline image comparison — 2026-11-04

Fresh immutable-image OS and library scans; raw reports and database metadata are retained alongside this file. Comparison keys are exact CVE ID and package name, not proof of exploitability. No production deployment is authorized by this evidence alone.

| Image | High/Critical/Unknown CVE-package pairs |
|---|---:|
| keycloak-prod | 6 |
| keycloak-candidate | 3 |
| postgres-prod | 338 |
| postgres-candidate | 98 |
| keycloak-postgres-prod | 142 |

## keycloak-candidate versus keycloak-prod

New pairs: 0. Shared: 3. Absent from candidate: 3.

## postgres-candidate versus postgres-prod

New pairs: 0. Shared: 98. Absent from candidate: 240.

## postgres-candidate versus keycloak-postgres-prod

New pairs: 69. Shared: 29. Absent from candidate: 113.

| CVE | Package | Severity | Candidate installed version | Fix recorded by scanner |
|---|---|---|---|---|
| CVE-2025-69720 | ncurses-bin | HIGH | 6.5+20250216-2 | — |
| CVE-2026-103484 | postgresql-17-pgvector | HIGH | 0.8.7-1.pgdg13+1 | — |
| CVE-2026-113351 | libexpat1 | HIGH | 2.9.0-1~deb13u1 | — |
| CVE-2026-115506 | libexpat1 | UNKNOWN | 2.9.0-1~deb13u1 | — |
| CVE-2026-116566 | libpython3.13-minimal | UNKNOWN | 3.13.5-2+deb13u5 | — |
| CVE-2026-116566 | libpython3.13-stdlib | UNKNOWN | 3.13.5-2+deb13u5 | — |
| CVE-2026-116566 | python3.13 | UNKNOWN | 3.13.5-2+deb13u5 | — |
| CVE-2026-116566 | python3.13-minimal | UNKNOWN | 3.13.5-2+deb13u5 | — |
| CVE-2026-117610 | libexpat1 | HIGH | 2.9.0-1~deb13u1 | — |
| CVE-2026-118370 | libexpat1 | HIGH | 2.9.0-1~deb13u1 | — |
| CVE-2026-15308 | libpython3.13-minimal | HIGH | 3.13.5-2+deb13u5 | — |
| CVE-2026-15308 | libpython3.13-stdlib | HIGH | 3.13.5-2+deb13u5 | — |
| CVE-2026-15308 | python3.13 | HIGH | 3.13.5-2+deb13u5 | — |
| CVE-2026-15308 | python3.13-minimal | HIGH | 3.13.5-2+deb13u5 | — |
| CVE-2026-19445 | libpython3.13-minimal | HIGH | 3.13.5-2+deb13u5 | — |
| CVE-2026-19445 | libpython3.13-stdlib | HIGH | 3.13.5-2+deb13u5 | — |
| CVE-2026-19445 | python3.13 | HIGH | 3.13.5-2+deb13u5 | — |
| CVE-2026-19445 | python3.13-minimal | HIGH | 3.13.5-2+deb13u5 | — |
| CVE-2026-19553 | libpython3.13-minimal | HIGH | 3.13.5-2+deb13u5 | — |
| CVE-2026-19553 | libpython3.13-stdlib | HIGH | 3.13.5-2+deb13u5 | — |
| CVE-2026-19553 | python3.13 | HIGH | 3.13.5-2+deb13u5 | — |
| CVE-2026-19553 | python3.13-minimal | HIGH | 3.13.5-2+deb13u5 | — |
| CVE-2026-24882 | dirmngr | HIGH | 2.4.7-21+deb13u1+b5 | — |
| CVE-2026-24882 | gnupg | HIGH | 2.4.7-21+deb13u1 | — |
| CVE-2026-24882 | gnupg-l10n | HIGH | 2.4.7-21+deb13u1 | — |
| CVE-2026-24882 | gpg | HIGH | 2.4.7-21+deb13u1+b5 | — |
| CVE-2026-24882 | gpg-agent | HIGH | 2.4.7-21+deb13u1+b5 | — |
| CVE-2026-24882 | gpgconf | HIGH | 2.4.7-21+deb13u1+b5 | — |
| CVE-2026-24882 | gpgsm | HIGH | 2.4.7-21+deb13u1+b5 | — |
| CVE-2026-7210 | libpython3.13-minimal | HIGH | 3.13.5-2+deb13u5 | — |
| CVE-2026-7210 | libpython3.13-stdlib | HIGH | 3.13.5-2+deb13u5 | — |
| CVE-2026-7210 | python3.13 | HIGH | 3.13.5-2+deb13u5 | — |
| CVE-2026-7210 | python3.13-minimal | HIGH | 3.13.5-2+deb13u5 | — |
| CVE-2026-76642 | bsdutils | HIGH | 1:2.41.5-0+deb13u1 | — |
| CVE-2026-76642 | libblkid1 | HIGH | 2.41.5-0+deb13u1 | — |
| CVE-2026-76642 | liblastlog2-2 | HIGH | 2.41.5-0+deb13u1 | — |
| CVE-2026-76642 | libmount1 | HIGH | 2.41.5-0+deb13u1 | — |
| CVE-2026-76642 | libsmartcols1 | HIGH | 2.41.5-0+deb13u1 | — |
| CVE-2026-76642 | libuuid1 | HIGH | 2.41.5-0+deb13u1 | — |
| CVE-2026-76642 | login | HIGH | 1:4.16.0-2+really2.41.5-0+deb13u1 | — |
| CVE-2026-76642 | mount | HIGH | 2.41.5-0+deb13u1 | — |
| CVE-2026-76642 | util-linux | HIGH | 2.41.5-0+deb13u1 | — |
| CVE-2026-78408 | bsdutils | HIGH | 1:2.41.5-0+deb13u1 | — |
| CVE-2026-78408 | libblkid1 | HIGH | 2.41.5-0+deb13u1 | — |
| CVE-2026-78408 | liblastlog2-2 | HIGH | 2.41.5-0+deb13u1 | — |
| CVE-2026-78408 | libmount1 | HIGH | 2.41.5-0+deb13u1 | — |
| CVE-2026-78408 | libsmartcols1 | HIGH | 2.41.5-0+deb13u1 | — |
| CVE-2026-78408 | libuuid1 | HIGH | 2.41.5-0+deb13u1 | — |
| CVE-2026-78408 | login | HIGH | 1:4.16.0-2+really2.41.5-0+deb13u1 | — |
| CVE-2026-78408 | mount | HIGH | 2.41.5-0+deb13u1 | — |
| CVE-2026-78408 | util-linux | HIGH | 2.41.5-0+deb13u1 | — |
| CVE-2026-78409 | bsdutils | HIGH | 1:2.41.5-0+deb13u1 | — |
| CVE-2026-78409 | libblkid1 | HIGH | 2.41.5-0+deb13u1 | — |
| CVE-2026-78409 | liblastlog2-2 | HIGH | 2.41.5-0+deb13u1 | — |
| CVE-2026-78409 | libmount1 | HIGH | 2.41.5-0+deb13u1 | — |
| CVE-2026-78409 | libsmartcols1 | HIGH | 2.41.5-0+deb13u1 | — |
| CVE-2026-78409 | libuuid1 | HIGH | 2.41.5-0+deb13u1 | — |
| CVE-2026-78409 | login | HIGH | 1:4.16.0-2+really2.41.5-0+deb13u1 | — |
| CVE-2026-78409 | mount | HIGH | 2.41.5-0+deb13u1 | — |
| CVE-2026-78409 | util-linux | HIGH | 2.41.5-0+deb13u1 | — |
| CVE-2026-78410 | liblastlog2-2 | HIGH | 2.41.5-0+deb13u1 | — |
| CVE-2026-78410 | login | HIGH | 1:4.16.0-2+really2.41.5-0+deb13u1 | — |
| CVE-2026-82049 | libpython3.13-minimal | HIGH | 3.13.5-2+deb13u5 | — |
| CVE-2026-82049 | libpython3.13-stdlib | HIGH | 3.13.5-2+deb13u5 | — |
| CVE-2026-82049 | python3.13 | HIGH | 3.13.5-2+deb13u5 | — |
| CVE-2026-82049 | python3.13-minimal | HIGH | 3.13.5-2+deb13u5 | — |
| CVE-2026-86139 | libxml2 | HIGH | 2.12.7+dfsg+really2.9.14-2.1+deb13u3 | — |
| CVE-2026-9538 | libperl5.40 | HIGH | 5.40.1-6+deb13u1 | — |
| CVE-2026-9538 | perl-modules-5.40 | HIGH | 5.40.1-6+deb13u1 | — |

The candidate PostgreSQL findings are all present in the current application PostgreSQL image, but 69 CVE-package pairs (19 unique CVEs) are absent from the current Bitnami identity database image. Presence in an image alone does not establish a reachable exploit. The recorded owner acceptance is scoped to the DEV hotfix; do not silently broaden it to this new identity database image on PROD.

The exact candidate application commit has not completed its complete CI/security and DEV acceptance. Production backup, restore, identity cutover, schema convergence and lesson admission gates are outstanding.
