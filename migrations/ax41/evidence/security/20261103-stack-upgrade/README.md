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

An exploratory scan of Percona's PostgreSQL 17.11 UBI 9 image found 153
distinct High/Critical CVEs (177 High and one Critical package/finding
matches), including Critical CVE-2026-114406 in `ca-certificates`. These are
raw scanner findings, not claims that every reported package is reachable in
the server runtime. The candidate has not been proven compatible with the
operator, existing data, extensions or locale, and is not a drop-in remedy.
The raw report is retained; no finding was waived by the comparison.

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

DEV admission was temporarily guarded during preparation, then restored by
infra PR #62 at `966c20a4719f5e6890a79bed0a12a0590562a501`. ArgoCD and the
API returned Healthy; authenticated start/room-token requests for a random
nonexistent lesson returned 404 without the maintenance error. This verifies
that the guard was removed, not a real lesson. No stack upgrade or production
promotion was performed. Fresh admission, backup, security and release gates
must be repeated before any future rollout.
