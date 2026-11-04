# Numeric release 01.007.25 supplemental dependency evidence

Exact platform source: ac483353beb2abab8c1d076a887044b536d24c1f.
Fresh full npm lockfile audits include development, transitive and workspace
packages. Frontend reports 15 moderate and 2 high findings; collaboration
reports zero. The audit exit code 1 means findings; no audit error was returned.
Local tooling is Node 26.7.0 / npm 11.19.0. Native CI uses its declared toolchain.
Frontend lockfile SHA-256 is
8d95858c9a68d2d737c5f45f2054fff3aa1667d1a1f1521f8ff2e6ce03a2e0ff.

A clean npm installation from this exact lockfile and the normal game-sync SDK
build preceded two Vite module-graph builds. All 17 audited packages are absent
from both loaded module graphs (web 1963 modules, keyboard 1652). This is retained
outside-runtime boundary evidence under the owner's policy, not a clean audit
or a claim that vulnerabilities are fixed. The initial inventory-only build
failed because the SDK had not been built; it was corrected by the normal SDK
build, without changing candidate source. These are graph checks, not deployed
browser acceptance or byte-for-byte artifact comparison. Native exact-image
scans and candidate provenance remain separately required.
