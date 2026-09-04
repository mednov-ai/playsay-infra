# Regional routing restoration: preparation, not production acceptance

Date: 2026-09-04. Owner confirmed lessons ended and authorized checks and local apply development. No repository commit/push, CI job, deployment, persistent remote configuration change or service restart was performed. Disposable test repositories used by local CI tests are not delivery commits.

## Scope and baseline

Local platform workspace: `/tmp/honey-routing-parity.A4kcxH/platform`, based on `bc94b8b89ecd885aac36edacabd05cbe86cbcd26` (`release/01.006.07`). Infra workspace: `/tmp/honey-routing-parity.A4kcxH/infra`, based on `56278fae947b7458821a4729154e147027a7d05a`. Original dirty checkouts were preserved. Root `spec.md` was updated declaratively.

Restored the focused regional selector/binding/evidence behavior from `.04`, retained subsequent collaboration/chat/scroll changes, and prepared prod media `rf-turn-relay` locally. Added application-binding tests, a rendered Helm → application behavior check, and a finalizer guard against ignored settings and silent routing downgrade. The guard checks candidate, accepted develop and actual API image source; it does not replace API tests or live acceptance.

## Authorized infrastructure diagnostics

- Fresh aggregate LiveKit participant count before allocation probes: 0.
- Selectel validator `--configuration`: protected secret metadata, DNS, independent certificate name/chain/remaining validity, nginx/coturn health, bounded listeners, default-deny firewall, service limits and loopback metrics all passed.
- Validator `--allocations`: invalid credentials rejected; authenticated TURN UDP, TCP and TLS allocation/data probes passed.
- Selectel → AX41 LiveKit TCP connectivity passed.
- AX41 production UDP range: one DNAT rule and one forwarding ACCEPT rule observed; the production-guest allow precedes blanket rejection.

No raw logs, credentials, SDP, candidates, network identities or lesson content were retained. TURN tests are self-relay infrastructure probes, not browser-to-LiveKit media acceptance. TCP reachability and firewall inspection do not prove end-to-end UDP media flow.

## Local verification

- API focused tests: 24 passed (selector, actual application binding and scheduled-lesson LiveKit authorization/token tests); Detekt main: zero findings.
- Actual rendered prod/dev/media-only rollback settings exercised through application binding: passed. This check uses synthetic credentials only.
- Frontend: 10 focused tests passed; TypeScript/Vite build passed with existing bundle-size warning. Added probe cleanup/non-overlap tests; an initial missing-jsdom test setup was corrected and rerun successfully.
- Routing preservation negative fixtures passed; the actual legacy `.07` source is rejected by the new guard.
- Existing collaboration Helm and signaling static validators passed.
- CI contracts: 35 passed, 3 skipped in the broad default invocation; the skipped release prepare/finalize integration was rerun with explicit local tool paths and passed. Two unrelated infra-discovery tests remained skipped. New finalizer routing contract passed separately.
- Shell syntax and diff whitespace checks passed.

## Remaining gates

Explicit delivery authorization is still required. Re-resolve current production/develop state and zero active lessons before commit/push/CI/delivery. Merge the needed fixes into develop in both repositories before cutting the candidate; do not reuse an old API image. Run the rendered-config checker again against the final candidate.

After delivery, use fresh authorized API-issued credentials for real RF allocation; prove both no-VPN browsers select RF relay and coturn allocations are nonzero while camera/audio/screenshare work bidirectionally through Selectel to LiveKit. Complete the existing one-lesson 45-minute quality/resource acceptance and independent rollback gates. Until then, the original no-VPN camera incident is not closed.
