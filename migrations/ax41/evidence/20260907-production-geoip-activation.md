# Production GeoIP activation

The owner explicitly requested enabling the production redirect after release 01.007.00. Applied infra source: `b40b3f8`, published to develop and codex/enable-production-geoip. The separate exact-ref production play changes only `/etc/nginx/conf.d/playsay-honey.conf` (six production root-location includes) and `/etc/nginx/conf.d/01-honey-school-browser-entry-policy.conf` (production flag). It requires the existing MMDB/snippet, retains dev flags, validates complete nginx configuration and performs a graceful reload. Failure restores both prior files; disabling the production flag and reapplying is the operational rollback.

Verification:

- Initial live inspection found exactly six matching HTTP/HTTPS vhosts without GeoIP includes.
- Reconciler tests passed preservation of all other bytes, protected vhosts, idempotency and rejection of unexpected topology.
- Thirty-one isolated real-nginx policy cases passed with production enabled: production host mappings, RU/non-RU, IPv6, spoofed forwarding headers, API/auth/ops and protocol exclusions, cache policy and loop prevention. Country values in that matrix are synthetic, not a live RF last-mile probe.
- Actual AX41 IPinfo MMDB independently classified known public fixtures as RU and US.
- Syntax/check/apply passed without rescue; repeat check reported changed=0.
- Live policy has production and dev flags enabled; six production includes each occur once.
- nginx master PID remained 1245751 across the graceful reload; application VMs, services, TURN and secrets were not changed.
- Public root/online/key .school and online .ru navigation returned 200 without redirection from this workstation's current external source. This is not evidence of a real RF client redirect. RU behavior is supported by the policy matrix plus actual database classification and active configuration.
- Initial API/OIDC probes deliberately sent Accept:text/html and returned 406 without a redirect. Rechecking with application/json returned healthy API responses and the canonical issuer.

Production mappings: honey.school → honeyschool.ru, online.honey.school → online.honeyschool.ru, key.honey.school → key.honeyschool.ru. Only RU browser GET/HEAD navigation qualifies. Path/query are preserved; API, callback/auth, WebSocket, signaling, collaboration, ACME, ops, unknown/non-RU and trusted Selectel peer remain excluded. No reverse .ru redirect is introduced.
