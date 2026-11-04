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

The current `scripts/ci/run-kaniko-image-build.sh` publishes directly; the
deployable Jenkins stages subsequently update GitOps references and contain
no final-image scan gate. It therefore cannot establish the required
pre-publication container evidence for this candidate as written. The four
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

Game adapter #46 passed build and the unpublished full-image scan at platform
commit `874f7527bf1ec552b7bb4f35016b8317a35a5ef7`, with no
High/Critical/Unknown matches. Its report and archive hash are retained as
`playsay-game-adapter-service-develop-46*`; publication and DEV stages did
not run. Real deployed Chromium, application integration and DEV lesson
acceptance remain outstanding.

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
is in `images/livekit/` and still needs a complete CI build and final-image
security disposition.
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
