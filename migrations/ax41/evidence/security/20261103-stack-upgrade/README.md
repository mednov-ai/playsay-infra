# Stack-upgrade container security evidence — 2026-11-03

Status: **blocked, not deployed**. Trivy 0.76.1 scanned the Linux/amd64
images with vulnerability database updated at 2026-11-03 13:13 UTC and
downloaded at 18:56 UTC. The complete original JSON reports are retained
compressed in this directory; `RAW-SHA256SUMS.txt` covers the uncompressed
bytes and `scanner-metadata.json` records the database timestamps. Counts
below are package/finding matches, not distinct vulnerabilities.

| Image | Immutable image digest | High | Critical | Result |
| --- | --- | ---: | ---: | --- |
| CNPG PostgreSQL 17.11 system/trixie | `sha256:03a1c6a62b27e8ad31cae5c085131b5ac706b09403d6fcb6c58d16c8daa257cd` | 85 | 1 | Blocked |
| CNPG PostgreSQL 17.11 system/bookworm | `sha256:b548f1bdfaff8c6a5b44646355502435be2beb28ae1bbb3520b8d6c44e6fbc5f` | 57 | 3 | Blocked |
| CNPG PostgreSQL 17.11 minimal/trixie | `sha256:7c680fc840a9ea6bd04399f1aeea06bb3180df3f0969f18833925b6df3d7dc87` | 62 | 1 | Blocked |
| Percona PostgreSQL 17.11 UBI 9 | `sha256:32a2c3ce3147ff269a5b0d56e1ae28823131b7a98a95a67d67723d4e78017a94` | 177 | 1 | Blocked; compatibility not established |
| Upstream LiveKit 1.13.11 | `sha256:25cd902de7cacbd5f1f779f6a6ac1eae20ba8f56b0935934ce6b0ab80d1e3d20` | 1 | 0 | Blocked |

The selected trixie PostgreSQL image contains `libxml2` affected by
[CVE-2026-6653](https://security-tracker.debian.org/tracker/CVE-2026-6653);
`ldd` on its PostgreSQL server binary confirms that the library is linked.
Debian lists both supported stable distributions as vulnerable, with no
stable fix in the scanned packages. Debian assigns a lower operational
priority than the scanner's Critical severity; that difference is not proof
that the affected code is absent. Additional High findings require their own
exact package/runtime assessment. The existing Kotlin/build-tool exception
does not cover these findings.
Debian's testing/unstable source tracks the later fixed libxml2 release, but
its newer library package is `libxml2-16` while the scanned PostgreSQL binary
links `libxml2.so.2`. The [upstream distribution migration notes](https://fedoraproject.org/wiki/Changes/Libxml215)
describe an ABI/SONAME change requiring dependent rebuilds. Installing that
newer package alongside the old one would therefore not by itself prove the
PostgreSQL process uses the fixed library; replacing or relinking it without
rebuilding and testing dependents is not a validated remedy.
This does not rule out backports to the old ABI: for example, Ubuntu reports
a [fix for CVE-2026-86138 in its 2.9.14 package](https://ubuntu.com/security/CVE-2026-86138).
Its package has not been established as compatible with this Debian image or
as resolving every match. A reviewed backport built and tested for the target
image remains a possible route, not an available candidate.

After the owner was told that this same `CVE-2026-6653` affects both the
selected 17.11 image and the checked 18.6 image, the owner directed us to
continue the rollout without treating that observation as a blocker. The
immediate authorized target is DEV for this hotfix; production still requires
the separate command already requested. This direction does not establish
that other scanner matches are absent from runtime or cover subsequently
discovered Keycloak findings, and all other delivery checks still apply.

The separately deployed CloudNativePG operator is 1.29.1 in both
[DEV](cnpg-operator-20261104-dev-inventory.json) and
[production](cnpg-operator-20261104-prod-inventory.json), using Kubernetes
1.35.5+k3s1. Upstream identifies 1.29.1 as affected by the operator
[untrusted search-path privilege escalation](https://github.com/cloudnative-pg/cloudnative-pg/security/advisories/GHSA-x8c2-3p4r-v9r6)
and [password exposure](https://github.com/cloudnative-pg/cloudnative-pg/security/advisories/GHSA-w3gf-xc94-wvmj);
neither advisory proves an attack path through this application. The observed
application clusters explicitly disable superuser access and specify no shared
preloaded libraries; the full configuration, role access and effective runtime
settings must still be checked before assessing exploitability. Upstream also
documents a distinct [operator control-port hardening issue](https://github.com/cloudnative-pg/cloudnative-pg/security/advisories/GHSA-7qwx-x8ff-3px9)
addressed in 1.30.0. The read-only inventory found no Kubernetes NetworkPolicy
objects in the `playsay-data` namespace in either environment. It does not
establish effective host/network restrictions, access from another pod, or
exposure from the internet; those boundaries still require review.
Each environment's read-only cluster inventory had one CNPG cluster, no
configured in-tree Barman object-store backup or backup plugin, and no
`ScheduledBackup` objects. This is not a claim that no other backups exist:
the DEV four-database custom archives and restore checks are documented
separately. The [1.30 release notes](https://cloudnative-pg.io/docs/1.30/release_notes/v1.30/)
retain in-tree Barman for 1.30 and introduce a primary-election Lease; both
the actual backup workflow and new election behavior require isolated tests.

A DEV-only 1.30.1 operator overlay is staged outside all reconciled ArgoCD
trees. Its upstream source is pinned to `2a35abb4628f209d149825ef3c38011e0701ff2f`
and its image index to `sha256:923c267ec29636db3bee20f993d0ec4973fa22998e1adad37da79e4d32b5bc07`.
Kustomize rendered its 26 objects, preserving the project resource limits,
reconciliation count and probes. Comparing resource identities with the 1.29.1
render showed the new `DatabaseRole` CRD and no removed objects; it did not
verify changes within existing CRD schemas or perform an upgrade. The exact
upstream Linux/amd64 image's [full scan](cnpg-operator-1301-trivy.json.gz)
reports ten High and five Unknown package/finding matches. These include
unpatched Go/toolchain and `x/net` matches in both shipped manager binaries,
and a CA-package advisory. Matching both binaries is not evidence of fifteen
independent attack paths. The scan database metadata and uncompressed report
checksum are retained. The staged operator must not be selected until its
actual runtime findings, image scan, isolated upgrade and recovery checks pass;
the shared active DEV/production operator overlay is unchanged.
The newer `static-debian13:nonroot` base index
`sha256:25ac8f0c3b2334a9eb05452266bd4697864a8c8ef0ef71e5e6480d7f92868329`
had zero vulnerability matches in a [separate scan](cnpg-distroless-base-trivy.json.gz)
with the same scanner database. It is a potential build input, not a scan of
a rebuilt operator or evidence that the Go findings are fixed.

An exploratory `security-check/` build then rebuilt both 1.30.1 manager
binaries from the pinned upstream source using Go 1.27.3, `x/net` 0.62.0 and
that newer base. Jenkins image-only build #2 passed the full-image scan with
zero High/Critical/Unknown matches in both binaries and the base. The raw and
blocking reports, scanner metadata, exact source revisions and image archive
hash are retained as `playsay-cnpg-fixture-2-*`. Its build ran `go get` during
the build and has not retained a reviewed dependency patch or proven
reproducibility; no image was published. Treat it as remediation evidence,
not an operator candidate. Lock its full dependency graph, scan the final
CI-built archive, and test upgrades, backup/restore and failover before use.

On 2026-11-04 the same immutable Linux/amd64 PostgreSQL image was scanned
again with Trivy 0.76.1 and a database downloaded at 2026-11-03 23:55 UTC.
The [complete report](postgres-1711-system-trixie-20261104.json.gz),
[database metadata](scanner-database-20261104.json), and the checksum of the
uncompressed report are retained. It reports 85 High, one Critical and 11
Unknown package/finding matches; these counts do not establish 97 reachable
attack paths. The linked `libxml2` finding remains present.

One High match is a likely scanner false positive: the image's installed
`postgresql-17-pgvector` package is `0.8.7-1.pgdg13+1` and its
`vector.control` declares `0.8.7`, while the [pgvector 0.8.7 changelog](https://github.com/pgvector/pgvector/blob/master/CHANGELOG.md)
and [CVE-2026-103484 record](https://nvd.nist.gov/vuln/detail/CVE-2026-103484)
state that this IVFFlat defect affects versions before 0.8.7. Keep the raw
match and verify package provenance before a final disposition; this does not
resolve the other findings. A read-only DEV inventory on 2026-11-04 found only
`plpgsql` installed in each of `playsay`, `keyboard`, and `worksheet_import`;
this did not inspect the separate identity database and does not prove which
extensions may be installed later.

The same scan associates CVE-2026-16742 with `libsystemd0` and `libudev1`.
The [upstream advisory](https://github.com/systemd/systemd/security/advisories/GHSA-jm29-p7hh-vjhv)
identifies the affected code as `systemd-homed` and `systemd-homework`, not
those shared libraries. In the exact 17.11 image the inspected executables
and package are absent; the retained
[`postgres-1711-linked-libraries-homed-inventory.txt`](postgres-1711-linked-libraries-homed-inventory.txt)
also shows that PostgreSQL links `libsystemd0` and `libxml2`. This is a
candidate-specific outside-server-runtime assessment of that one homed
finding, not a statement about the host or the other library findings. The
raw matches remain in the complete scan.

An exploratory scan of Percona's PostgreSQL 17.11 UBI 9 image found 153
distinct High/Critical CVEs (177 High and one Critical package/finding
matches), including Critical CVE-2026-114406 in `ca-certificates`. These are
raw scanner findings, not claims that every reported package is reachable in
the server runtime. The candidate has not been proven compatible with the
operator, existing data, extensions or locale, and is not a drop-in remedy.
The raw report is retained; no finding was waived by the comparison.

Additional base-image checks found that `nginx:1.27-alpine`, used by both
frontend Dockerfiles, is based on end-of-support Alpine 3.21 and reported 59
High and three Critical package/finding matches. Trivy also warned of missing
details for two vulnerability IDs and insufficient coverage for the EOL OS;
these counts are preliminary and not a security clearance. The upstream
`nginx:1.30.6-alpine` manifest
`sha256:0e52bd054126cdc040b1276c0af347aeb02a41b9cfe305d6094767ac30e97949`
initially reported four High and one Critical matches. A local image using
that pinned base and a fresh `apk upgrade` updated the affected Alpine
packages; the complete local web and keyboard images then had zero
High/Critical/Unknown matches. Their local image IDs were respectively
`sha256:786016d13736dcc8bf3c0519aaa3d3bf6ce9a2c752039c21c57a7ca899540067`
and `sha256:e1208d18ef1aa5b5c57fc7b682e8658c08f977a6de820c5a0bdbce2d67fa3b6c`.
An isolated upstream fixture verified nginx startup, both health endpoints,
SPA fallbacks, API routing, WebSocket forwarding headers and web `.mjs`
worker MIME/404 handling. It did not prove actual DEV routes or deployed
artifacts. Package upgrades are resolved at build time: scan and retain the
exact final CI images and their digests before any delivery.

The baseline `scripts/ci/run-kaniko-image-build.sh` published directly; the
baseline deployable Jenkins stages subsequently updated GitOps references
without a final-image scan gate. That baseline could not establish the required
pre-publication container evidence. The four
successful exact-source Jenkins checks used a non-deploying branch and did
not execute image build/push or environment update stages. A reviewed
build/scan/publish sequence must fail closed before any deployable build.

On 2026-11-04 a revised sequence was prepared in the local platform hotfix
worktree. Kaniko emits an unpublished archive; Trivy retains a full report
and blocks High/Critical/Unknown findings, end-of-life OS and scan errors;
the publisher verifies the archive and the registry digest before deployment
tags or GitOps updates. DEV migrations run after the scan and a branch-head
check. A `security-check/` branch is scan-only and cannot publish or deploy.
Local tests covered scan errors, findings, archive tampering, digest mismatch,
release/dev tag separation, valid pod YAML and Groovy compilation. Real Trivy
blocked a known vulnerable fixture, and a clean fixture was published only to
an isolated local registry with the scanned and published digests equal. This
is local evidence. Jenkins `playsay-collaboration-service-develop` #64 then
built platform commit `a13451caee016ed4d7bb8ddbd8cf29136060924b` on the
`security-check/stack-upgrade-20261104` branch and passed its full Trivy scan
with no High/Critical/Unknown findings. Its full scan, database metadata and
archive SHA-256 are retained as `collaboration-ci-64-*`. Jenkins recorded
the publish, source-tag, GitOps update and rollout stages as not executed.
This validates the scan-only path for that unpublished CI archive, not the
real-registry publication path, other images or DEV acceptance.

Jenkins web #418 passed the same scan-only path at platform commit
`a13451caee016ed4d7bb8ddbd8cf29136060924b`. Keyboard frontend #115 was
aborted when its 1 GiB Node container exceeded its cgroup memory limit during
`npm install`; the CI kernel identified the memory cgroup OOM. Platform commit
`874f7527bf1ec552b7bb4f35016b8317a35a5ef7` reserves 3 GiB with a 5 GiB limit
and a 3 GiB Node heap. Keyboard frontend #116 then passed its build and full
scan, with no High/Critical/Unknown findings. The web and keyboard raw CI
reports, database metadata and archive hashes are retained as
`playsay-web-app-develop-418*` and `playsay-keyboard-frontend-develop-116*`.
Both jobs skipped publication and environment updates. The web result is for
the previous platform commit; the only later changes are the keyboard CI
resource settings and their contract test, so it is useful comparison evidence
but not an exact-current-commit run. A later web #419 run passed the same
scan-only checks at commit `874f7527bf1ec552b7bb4f35016b8317a35a5ef7`; its
report and archive hash are retained as `playsay-web-app-develop-419*`.

After restoring the previous Vite 6 browser compilation targets, web #420
passed its generate/lint/test/build stages and final-image scan on platform
commit `8a6e6deaaa6aeda59472b85470f9c793b65efaeb`, with zero blocking
matches. Raw and blocking reports, scanner metadata and the image archive
hash are retained as `playsay-web-app-develop-420*`. Publication, GitOps and
DEV/UI smoke stages were not executed; the mounted local nginx/browser
fixture is documented separately in the platform security notes.

Keyboard frontend #117 passed its lint, tests, build and final-image scan for
the same platform commit, also with zero blocking matches. Its raw and
blocking reports, scanner metadata and image archive hash are retained as
`playsay-keyboard-frontend-develop-117*`. Publication, GitOps and DEV browser
smoke did not execute.

Keyboard backend #55 passed its dependency-security gate, tests, package build
and final-image scan for the same platform commit, with zero blocking image
matches. Full and blocking reports, their uncompressed checksums, database
metadata and the image archive hash are retained as
`playsay-keyboard-backend-develop-55-*`. Publication and DEV stages did not run.

Media service #51 passed its dependency-security gate, tests, package build
and final-image scan for platform commit `a8ca83154b9ffea9220a631112657438eed60c58`,
with zero blocking image matches. Reports, checksums, database metadata and
the image archive hash are retained as `playsay-media-service-develop-51-*`.
Publication and DEV stages did not run.

Registration service #80 passed its dependency-security gate, tests, package
build and final-image scan for the same `a8ca8315` platform commit, with zero
blocking image matches. Reports, checksums, database metadata and the image
archive hash are retained as `playsay-registration-service-develop-80-*`.
Publication and DEV stages did not run.

Email service #54 passed its dependency-security gate, tests, package build
and final-image scan at the same platform commit, with zero blocking image
matches. Its reports, checksums, database metadata and image archive hash are
retained as `playsay-email-service-develop-54-*`. Publication, migration and
DEV stages did not run.

Payment service #39 passed its dependency-security gate, tests, package build
and final-image scan at the same platform commit, with zero blocking image
matches. Its reports, checksums, database metadata and image archive hash are
retained as `playsay-payment-service-develop-39-*`. Publication, migration and
DEV stages did not run.

Collaboration service #67 passed its tests, build and final-image scan at the
same platform commit, with zero blocking image matches. Its reports, checksums,
database metadata and image archive hash are retained as
`playsay-collaboration-service-develop-67-*`; publication and DEV stages did
not run.

Worksheet import #37 passed its dependency-security gate, tests, package build
and final-image scan at the same platform commit, with zero blocking image
matches. Its reports, checksums, database metadata and image archive hash are
retained as `playsay-worksheet-import-service-develop-37-*`. Publication,
migration and DEV stages did not run.

AI tutor #63 passed the dependency gate, tests, packaging and final-image scan
at platform commit `f1f5a414767e33b707ba48528162f60decaddd8c`, with zero
blocking image matches. Its raw and blocking reports, scanner and Java DB
metadata and archive hash are retained as `playsay-ai-tutor-service-develop-63*`.
The subsequent platform changes affect the frontend Vite targets and security
notes, not that service. Publication, migration and DEV stages did not run.

Vocabulary #77 and game adapter #47 passed their tests/builds and full image
scans at `8a6e6deaaa6aeda59472b85470f9c793b65efaeb`, each with zero blocking
image matches. Vocabulary also passed its JVM dependency gate. The raw and
blocking reports, relevant database metadata and image archive hashes are
retained as `playsay-vocabulary-service-develop-77*` and
`playsay-game-adapter-service-develop-47*`. These scan-only jobs did not
publish, migrate or update DEV.

Game adapter #46 passed build and the unpublished full-image scan at platform
commit `874f7527bf1ec552b7bb4f35016b8317a35a5ef7`, with no
High/Critical/Unknown matches. Its report and archive hash are retained as
`playsay-game-adapter-service-develop-46*`; publication and DEV stages did
not run. Real deployed Chromium, application integration and DEV lesson
acceptance remain outstanding.

The unpublished API gateway image from Jenkins #217, platform commit
`a13451caee016ed4d7bb8ddbd8cf29136060924b`, failed its final-image scan
after its JVM dependency gate had passed. It contained five blocking matches
in `async-http-client:2.15.0` and one in `jsoup:1.18.3`; the retained full
and blocking reports are `playsay-api-gateway-develop-217*.json.gz` with
their database metadata. Publication, migrations and GitOps updates did not
run. In platform commit `f393a19b878249dcd4c4787395cbf2bb17111296` the
unused async client and its web-push transitive dependency are removed, and
jsoup is updated to 1.24.1. A local packaged JAR and Gradle runtime graph
contain no async-http-client. A real local HTTP receiver accepted an encrypted
VAPID push, and the expired-subscription response was handled; HTML metadata
tests passed. Jenkins API #218 then passed the dependency gate, full API tests,
OpenAPI contract check and the final-image scan for that commit, with zero
High/Critical/Unknown matches. The full and blocking reports, scanner and
Java-database metadata, and archive hash are retained as
`playsay-api-gateway-develop-218-*`. Publication, migration and DEV stages
did not run. The later platform commit changes only the Keycloak build and
its security documentation; repeat final candidate gates before delivery.

The unpublished Keycloak image from Jenkins #28, platform commit
`f393a19b878249dcd4c4787395cbf2bb17111296`, passed its dependency and
provider tests but failed its final-image scan on six matches: the CA bundle,
two OpenJDK findings, two SQLite findings and Guava. The full and blocking
reports and database metadata are retained as `playsay-keycloak-develop-28*`;
publication and DEV stages did not run. Platform commit
`f1f5a414767e33b707ba48528162f60decaddd8c` pins a newer official 26.8.1
rebuild and updates Guava to 33.7.2-jre in both the packaged server and the
security inventory. Local provider tests and runtime verifiers passed.
Jenkins Keycloak #29 then passed the dependency gate, provider tests and image
build, but the final image scan still blocked on CVE-2026-91403 in OpenJDK
and CVE-2026-119373/CVE-2026-119586 in `sqlite-libs`. The previous CA bundle,
OpenJDK font-rendering and Guava matches no longer appeared. The new raw
reports and database metadata are retained as `playsay-keycloak-develop-29*`.
Publication and DEV stages were not executed; the three remaining matches
require candidate-specific disposition and a fresh complete gate.

Exploratory inspection of the new official Linux/amd64 base's RPM database
found `ca-certificates-2026.2.92_v9.0.319-90.3.el9_8` and
`java-21-openjdk-headless-21.0.13.0.9-1.2.el9`, the fixed package versions
listed in the previous scan. It still contains `sqlite-libs-3.34.1-11.el9_8`.
The extracted Java truststore did not list the two affected roots named in
the [Red Hat bulletin](https://access.redhat.com/security/vulnerabilities/RHSB-2026-012).
[Exact base digest, package versions, database and truststore hashes](keycloak-upstream-26.8.1-metadata-20261104.txt)
are retained. This does not establish the final image's full scan result or
its effective DEV truststore configuration.

The new base's Java `cacerts` path is a symlink to the extracted system Java
truststore. A local Java trust-manager check accepted the affected emSign G3
root with the previous base's store and rejected it with the new store;
[test source](CheckTrustStore.java) and [recorded hashes](keycloak-ca-trust-check-20261104.txt)
are retained. [Red Hat states](https://access.redhat.com/security/cve/cve-2026-91403)
that updating the system CA package addresses this OpenJDK issue for its RHEL
RPM builds. That is promising evidence, but other
Keycloak truststores and the effective deployed configuration have not been
proven, so the scanner match remains blocked rather than silently ignored.

An exploratory static inventory of that upstream base's 149 ELF binaries
found no `sqlite3` shell executable, but `libsoftokn3.so` directly requires
`libsqlite3.so.0`. The locally packaged server/provider JARs include SQLite
dialect classes but do not establish whether the native library is loaded by
Keycloak. The [inventory](keycloak-upstream-native-inspection-20261104.txt)
is not a dynamic runtime trace or an inspection of the final image; it must
not be used to classify the SQLite library as absent from server runtime.
An isolated Linux call to the exact upstream library returned SQLite 3.34.1
with `ENABLE_FTS5=1`; [the library hash and test result](keycloak-sqlite-compile-options-20261104.txt)
are retained. This confirms the affected feature is compiled in, but does not
prove Keycloak loads it or exposes the vulnerable SQL path.
The matching [Red Hat source RPM and checksum](keycloak-sqlite-source-20261104.txt)
were identified; its build enables FTS5 and includes earlier vendor security
patches. A custom rebuild with that feature disabled could eliminate this
specific vulnerable code, but remains unbuilt and must preserve the vendor
patches, ABI, NSS and Keycloak behavior before it could be considered.

Jenkins Keycloak #30 inspected its unpublished image before the full scan;
the scan blocked on the same three findings. The scan-only source commit was
`c3f170a740a8ff3d29fb4bdb8651a3bdb541c802`; compared with candidate platform
commit `a8ca83154b9ffea9220a631112657438eed60c58`, only the inspection stage
in the Jenkinsfile and a security document differ. The inspected archive hash,
complete raw and blocking reports, database metadata and file inventories are
retained as `playsay-keycloak-develop-30-*`; publication and DEV stages were
skipped. The [system Java truststore](playsay-keycloak-develop-30-java-system-cacerts)
has the same SHA-256 as the tested updated base truststore, and the retained
[symlink inventory](playsay-keycloak-develop-30-java-truststore-links.txt)
confirms the image's default Java path reaches that store. No extra file under
`/opt/keycloak/conf/truststores/` was found. The [SQLite inventory](playsay-keycloak-develop-30-sqlite-paths.txt)
has the library but no executable named `sqlite3`, `sqlite3_analyzer` or
`sqldiff`; the separate [shell-name inventory](playsay-keycloak-develop-30-sqlite-shell-paths.txt)
is empty. These checks strengthen the case for the CA package correction and
for the shell-only finding being outside this image's server runtime, but do
not establish the effective deployed configuration or resolve the FTS5 finding.
The candidate remains blocked pending its exact final scan and disposition.
The [read-only DEV configuration inventory](keycloak-dev-trust-config-20261104.txt)
found no truststore environment override, `envFrom` block or non-theme volume
mount, and the project's provider/entrypoint source has no custom trust
manager references. This is evidence about the currently deployed older image;
it neither proves every third-party library uses the default manager nor
replaces a check of the candidate's effective configuration after deployment.

The `eclipse-temurin:25.0.5_8-jre` base scan contained no
High/Critical/Unknown findings. The `node:26.13.0-alpine` base scan found
six High package/finding matches in npm's bundled `brace-expansion` and
`undici`. Removing the unused npm installation from the local collaboration
runtime left zero High/Critical/Unknown matches; the non-root service started
and its health endpoint passed. The running Node binary identifies its own
built-in Undici as 8.12.2. This is local evidence, not a classification of
uninspected images or a substitute for exact CI-image and dependency scans.

The separately scanned Node 26 bookworm-slim base intended for the game
adapter had 38 High and one Critical matches. A local exploratory game
adapter build on the pinned Node 26 Alpine base, with updated Alpine packages
and no runtime npm, scanned with zero High/Critical/Unknown matches. Its
non-root process, health, service-token enforcement and authenticated
optimization endpoint passed under the chart's 1 CPU/1 GiB limit. A
synthetic PNG/JPEG/WebP optimization was deterministic under the same limits;
an offline synthetic game passed the real Chromium/Playwright validator. All
37 game-adapter tests, including four Chromium-dependent tests, passed in a
separate offline test stage using the same runtime family. The
local image ID was
`sha256:6b9d2b274c23b7ec3ef5d35216d56eb3a46134ea11c6182c20e0dac3ebce8f5a`.
These checks do not prove real DEV integrations or the future CI-built image.

The upstream LiveKit binary contains `golang.org/x/net` v0.59.0 affected by
[CVE-2026-78669](https://pkg.go.dev/vuln/GO-2026-6611), fixed in v0.60.0.
A **local, unpublished** experiment rebuilt upstream tag v1.13.11 at commit
`385aa40f9292fe1db8caad87301e4b285b7c198a` using Go 1.27.3 and the retained
[`livekit-local-dependency.patch.gz`](livekit-local-dependency.patch.gz). It updates
`x/net` to v0.62.0 and aligns `x/crypto`, `x/sync`, `x/sys` and `x/text`.
The resulting image scan has zero High/Critical matches and one Unknown
finding, [GO-2026-5932](https://pkg.go.dev/vuln/GO-2026-5932), for the
unmaintained `golang.org/x/crypto/openpgp` package. The retained Linux/amd64
compiled package graph and binary symbol inventory contain neither that
package nor its symbols. The binary SHA-256 is
`80e59aeb06a5d8956080d11acf1a5d35bede0a81f160c0b651a045e173b86970`;
the packaged binary matched that hash. This is candidate-specific
outside-runtime evidence, not a blanket exception. The rebuilt image passed
isolated startup and required metrics checks; it has not passed actual DEV
classroom acceptance or the project's image publication pipeline.

On 2026-11-04 the pinned upstream archive and checked-in patch were used to
rebuild a Linux/amd64 binary with Go 1.27.3 and reproducible build flags.
The binary SHA-256 is
`a247e0ecbdd4cbe9491a220a58610767372e7353d89b81c0bfc464ed9496fbf0`,
identical inside the local test image. It identifies `golang.org/x/net`
v0.62.0. Trivy found zero High/Critical matches and one Unknown
`GO-2026-5932` match for `golang.org/x/crypto`; the exact binary's retained
Linux package graph and symbol inventory contain no `openpgp` packages or
symbols, the only affected packages in the [Go advisory](https://pkg.go.dev/vuln/GO-2026-5932).
This is outside-runtime evidence for this binary only, not a blanket waiver.
The local image started and served its health endpoint; this did not test
media, a CI-built image or a deployment. The candidate reproducible recipe
is in `images/livekit/`. Jenkins scan-only build #65 recreated the identical
binary SHA-256 and retained its package graph and build metadata. Its normal
unfiltered image gate correctly failed on the single Unknown OpenPGP match;
the raw report and metadata are retained as `playsay-livekit-ci-65-*`.
Jenkins scan-only build #66 then passed with the narrowly scoped classifier:
the complete raw report retained the single OpenPGP match, and the
classified report had no remaining blocking matches. The retained advisory,
binary hash, package graph, raw and classified reports, and image-archive
SHA-256 are `playsay-livekit-ci-66-*`. Publish, source-tag, GitOps update and
rollout stages did not execute. This validates the classifier against that
CI-built archive, not a real-registry publication or a deployed DEV image.
The compressed `*-build-info.txt.gz` files retain the original Go build-info
bytes; the adjacent text copies only normalize trailing whitespace.

The registered `playsay-livekit-image` job's scan-only build #1 subsequently
passed using infra `5c76122a2884c1137125a7b17f58ceef2c3f2321` and platform
`f393a19b878249dcd4c4787395cbf2bb17111296`. It produced archive SHA-256
`4922a59a5a76b81bb66732590c6dae548dcc4fb5b5274e9494a045cd52051b06`;
its raw and classified reports and both source revisions are retained as
`playsay-livekit-image-1-*`. The sole raw blocking match was the same
outside-runtime OpenPGP finding. The publish stage did not execute, and the
job cannot alter GitOps or deploy. Its tested source heads have since moved;
repeat the candidate scan when the final heads are known.

A separate local three-browser fixture used a native macOS/arm64 LiveKit
binary with Go build metadata identifying upstream commit `385aa40f9292`,
`golang.org/x/net` v0.62.0 and a modified source tree. Its SHA-256 was
`8a3bbbea283abee0b5e4ab4a824407631236d87a16ea127fbd94f8c9fedd0731`.
Three independent browser contexts exchanged synthetic camera and microphone
RTP in both directions and observed two remote participants each. This is
not the Linux container, the deployed application, a physical-device test or
an RF/TURN acceptance; no real lesson data was used.
The prepared LiveKit Helm chart can now render a validated immutable image
digest. Default DEV and production renders remained byte-for-byte unchanged;
a valid digest rendered the expected image reference and a malformed digest
failed rendering. No rebuilt image was published or selected in DEV.

DEV admission was temporarily guarded during preparation, then restored by
infra PR #62 at `966c20a4719f5e6890a79bed0a12a0590562a501`. ArgoCD and the
API returned Healthy; authenticated start/room-token requests for a random
nonexistent lesson returned 404 without the maintenance error. This verifies
that the guard was removed, not a real lesson. No stack upgrade or production
promotion was performed. Fresh admission, backup, security and release gates
must be repeated before any future rollout.
