# Certificate renewal hotfix: local candidate

Change: `hotfix-ax41-shared-certificate-renewal`.
Status: local implementation; delivery, live renewal, receiver/provider acceptance
and published develop integration are pending. No production recovery is claimed.

## Source and authorization

- Local infra baseline: `4fa336c0f335fb9dceeddb3c3d523e20f1b9846b`
  (2026-10-17, locally available whiteboard develop integration).
- Task checkout: `.codex-worktrees/hotfix-ax41-shared-certificate-renewal-infra`
  relative to the Honey School workspace; detached, uncommitted candidate.
- Original platform checkout had 152 dirty entries and original infra 33; neither
  was reset, cleaned, switched or used as deployment input. Platform is unaffected.
- Remote refs were not refreshed or represented as current. No commit, push, PR,
  CI, SSH operation, live Ansible execution, production issuance or notification
  was performed by this apply run. Delivery needs separate authority under AGENTS.
- Root `spec.md` received only the declarative certificate-lifecycle contract.

## Implemented scope

- Exact prod/DEV ops ACME fallback, local-first, raw token/method validation,
  fixed origin/Host, no forwarded credentials/body, bounded timeouts/no cache.
- Ingress-only production release option, isolated DEV template ownership and
  validated graceful reload/rollback. Effective TLS route rendering is unchanged.
- Eleven owned lineages: two AX41 and nine Selectel. Independent root/alias,
  public/origin, DEV and TURN dependencies are declared. Unrelated resources stay
  outside managed health/telemetry; the existing global renewal coverage is retained.
- Existing Certbot timer observed per lineage twice daily, hourly strict disk/TLS
  checks, weekly non-activating staging rehearsal and five-minute safe metrics push.
  Unknown custom package/effective service arguments fail before replacement.
- Existing nginx hooks are checked through served fingerprints; a real renewal
  activates through validation/graceful reload only if not already active. TURN
  only records pending activation; it never restarts media or copies private keys.
- Existing monitoring gets expected-inventory/missing-series checks, 30/14-day
  expiry alerts, failed/stale renewal and rehearsal, activation mismatch/failure
  and pending TURN-marker alerts. Generic insecure availability probes are unchanged.

## Local verification

- `test_certificate_acme.py`: 10 tests passed, including actual local Docker nginx
  requests, raw malformed paths, Host boundary, header stripping, HEAD/methods,
  local-file collision, missing challenge, Ansible route rejection/include resolution,
  invalid nginx candidate and unchanged HTTPS rendering for both contours.
- `test_certificate_lifecycle.py`: 15 tests passed, including a real temporary TLS
  server/chain, wrong identity, disk absence/expiry/chain and network failures,
  activation mismatch, no-op versus failed renewal, safe staging hook arguments,
  failure isolation/recovery, declared route coverage, release rejection before remote fetch
  and non-disruptive TURN markers.
- External Prometheus `promtool` 3.5.0 validated all 27 generated rules and passed
  17 controlled alert fixtures, including missing data, 30/14-day thresholds,
  stale schedules, pending activation, immediate/persistent failures and resolution.
  This is local expression verification, not notification delivery acceptance.
- Existing RF dev, RF media-relay monitoring and edge-log contract scripts passed.
- Production and DEV monitoring Helm lint/render passed; affected Ansible syntax
  checks and shell syntax passed. Syntax used a local placeholder inventory and
  did not contact hosts. The ingress-only task list contains no media role tasks.
- `git diff --check` and strict OpenSpec validation are required for final handoff.

## Unverified delivery/acceptance

Current remote source/release pointers, live inventory/renewal metadata, package
service compatibility/duplicate-scheduler preflight, protected backups and active
sessions; DEV then production ingress; staging and actual shared-certificate renewal;
all current disk/served chains; persistent schedules and real monitoring import;
authenticated application acceptance; Mailjet registration/authentication/actual
callback receipt; approved firing/resolved notification delivery; fixture absence;
released-head and semantic fix evidence in remote infra `develop`.

Do not mark the hotfix complete, archive it or treat successful local tests as a
production repair. Keep the released head and durable fix merge-back gate. Retain
new valid certificates during any configuration rollback; never restore the expired
chain or disable upstream TLS verification. Details and commands are in the runbook.

Certbot CLI arguments were checked against the [official v2.9.0 CLI source](https://github.com/certbot/certbot/blob/v2.9.0/certbot/certbot/_internal/cli/__init__.py) for
`--no-random-sleep-on-renew` and the official hook documentation. The observer
disables hidden per-command random sleep so its 300-second command budget does not
terminate an otherwise healthy eligibility check during a random delay. The actual
installed client version/behavior remains a delivery acceptance check.

## Authorized delivery preflight (2026-10-19)

Owner approved publication and DEV/PROD delivery with `Разрешаю`. Fresh remote develop
is `4fa336c0f335fb9dceeddb3c3d523e20f1b9846b`; live 19 production ArgoCD
applications remain Synced/Healthy on `release/01.007.19`. The host-only infra
release is `release/01.007.20`; no platform release or image rebuild is required.
The retained exact platform .19 HEAD is `87a9389c41afba98757ca3375399c7dd1963aced`,
confirmed against current GitHub. Runtime schema convergence is checked against that
unchanged production source, not unrelated DEV changelogs. All 11 declared lineages,
SANs and webroot authenticators match the current host inventory. Native Certbot 2.9.0
service on both hosts includes `--no-random-sleep-on-renew`; observer preconditions
now allow that exact existing package flag.

Protected pre-change nginx/Certbot archives are root-only on each host at
`/var/backups/playsay/certificate-hotfix-20261019T1045Z/nginx-certbot-before.tar.gz`.
Both archive listings verify. SHA256: AX41
`bad2bb54f8e2f641d2e945d2bcfb79dcff93862245c9ed15f2eed430517e3102`; Selectel
`d699568f8b9734b76e2a0b8f3fa764c8b45e8366b6979eb650642d20e268937a`.
No private material was copied from the hosts. Live delivery and acceptance below
remain pending until individually verified.
