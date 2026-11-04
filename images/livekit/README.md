# Temporary LiveKit 1.13.11 build

This image rebuilds upstream commit `385aa40f9292fe1db8caad87301e4b285b7c198a`
with the checked-in dependency patch. The source archive, Go builder and
Alpine base are pinned; Go modules are verified against `go.sum`. The patch
upgrades `golang.org/x/net` past the HTTP/2 fix for CVE-2026-78669 and aligns
its related Go modules. The build records the binary hash, Go build metadata
and Linux package graph, and refuses a binary containing the unrelated
`golang.org/x/crypto/openpgp` package or its symbols.

Alpine packages are refreshed at build time, so the exact final image needs a
fresh full security scan and retained report before publication. The package
graph and symbols apply only to the exact built binary; they do not waive any
other finding. Validate the image through the reviewed CI build/scan/publish
workflow and real DEV signaling, TURN and group media before delivery. The
Dockerfile alone does not authorize publication or deployment.

Replace this temporary build with a verified compatible upstream stable image
once it contains the HTTP/2 dependency fix and passes the same security and
media checks. See the stack-upgrade security evidence in
`migrations/ax41/evidence/security/20261103-stack-upgrade/README.md`.
