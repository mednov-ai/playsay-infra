# Host maintenance hotfix .21: protected fallback delivered

The owner explicitly authorized publication, AX41/Selectel deployment and develop
integration on 2026-10-23, with no restarts during lessons. Only infra is affected.
Fresh remote develop baseline was b97dddecfa79105d93cc0544af752d17ebb8b30d; .21 was
unused. No adjacent application change was included. The dirty primary platform
and infra checkouts were preserved; implementation/delivery used an isolated checkout.

Production root and monitoring overlay now select release/01.007.21. All seventeen
other ArgoCD children remain on release/01.007.19 at the accepted application source;
current-release.txt and release-candidate.yaml stay .19. DEV desired state, product
images and digests, DNS, certificate lifecycle and shared-host ingress remain unchanged.
Runtime acceptance found 17 product/data/auth/media containers ready, all with
immutable image IDs, and none started after policy installation. The 19 production
Applications are Synced/Healthy. No product rollout or build was performed.

## Inventory and gate evidence

Both hosts use Ubuntu apt 2.8.3 and unattended-upgrades 2.9.1+nmu4ubuntu1. AX41 has
needrestart 3.6-7ubuntu4.5; Selectel has no inspector. The actual DEV TURN service
is honey-school-dev-turn, independent of coturn. Native apt-daily-upgrade used
06:00 UTC plus 60 minutes random delay, Persistent=true. Cron apt-compat yields
to systemd on these hosts. No per-user cron installer was present. Root-local
cron/systemd/apt/needrestart inventory was reviewed as paths/checksums only. The
shutdown service waits for a signal; InstallOnShutdown is now explicitly false.
Known package post-install paths can call service helpers directly, so they are
contained by deferring installation, not by assuming needrestart catches them.
Unknown installation paths or future policy changes require renewed review.

Two separated fresh PROD/DEV observations showed zero LiveKit rooms/participants,
collaboration/game connections and snapshot queue. Authoritative lesson-window
queries including access extension, ten-minute grace, unknown fields and conservative
22-minute start lookahead showed zero protected windows. Expired historical rows
were not modified. PROD/DEV relay UDP and TCP port ranges had zero sockets. This
was repeated before monitoring promotion; it does not install an admission lease.

All seven exact .19 source Liquibase status gates passed with zero pending changes;
no schema update occurred. Four fresh database dumps (playsay, keyboard,
worksheet_import, Keycloak) passed SHA256 and pg_restore-list checks. Protected guest
backups: /var/backups/playsay/host-maintenance-01.007.21-20261023T084217Z.
No new isolated Keycloak restore was claimed: authentication/schema are unchanged.

Protected policy archives/manifests are root-only under:
- AX41: /var/backups/honeyschool/host-maintenance/20261023T084909Z
- Selectel: /var/backups/honeyschool/host-maintenance/20261023T084940Z

## Delivery and nondisruptive acceptance

Published implementation f032a8fe2ef5ca2f426eadf78169c61112f8e28a was delivered with
only the reviewed policy owner on AX41 then Selectel, followed by the dedicated RF
NIC owner. No common/bootstrap/media/guest provisioning role ran. Suppression was
installed before scheduler replacement. Perl and systemd candidates validated;
the final owner also validates APT syntax before replacing its candidate file.
Checks after delivery show changed=0 for both policy owners and the counter owner.

Actual configuration on both hosts: Update-Package-Lists=1,
Download-Upgradeable-Packages=1, Unattended-Upgrade=0, Automatic-Reboot=false,
InstallOnShutdown=false. The existing upgrade service executes the non-disruptive
observer, with 03:00/04:00 Europe/Moscow OnCalendar, zero random delay, Persistent=yes.
At acceptance the next firing was 2026-10-24 00:00 UTC (03:00 MSK). Five-minute
observation publishes via existing private/authenticated imports; no new credentials
or cross-host authority was provisioned. Existing crash recovery and certificate
owners were untouched. The effective installed AX41 needrestart policy selects
zero for nginx, libvirtd and honey-production-logs without blacklisting inspection.

PID evidence before and after delivery:
- AX41 nginx 328812; libvirtd 2271746.
- Selectel nginx 1269828; coturn 526088; DEV TURN 787137.

Installed guard functions on both hosts passed busy/stale/missing/two-zero-without-
exclusion and Moscow boundary/clock/catch-up checks. No destructive command was
executed. The observer has no package-install or critical restart capability.
No real disruptive acceptance was attempted outside the night window. This is the
explicit safe fallback allowed by the design, not completed autonomous maintenance.

At first observation AX41 reported 62 pending installations and nine host service
restarts; Selectel reported 36 pending installations with restart discovery unknown.
Both hosts have a reboot-required marker. First-observed debt timestamps survived
subsequent checks. These are host aggregates, not a complete owned-service runtime
acceptance or a claim that affected software is patched. Do not erase state or reset
its age while arranging separately gated runtime updates.

NIC v2 kernel components on Selectel were 0/5/0/0, exactly matching aggregate 5,
both locally and after authenticated import. Collection health=1 and central data
age was under five seconds; TCP/TLS/HTTP route probes remained 1. No unversioned
packet-derived history is used or rewritten. Incident queries require corrected
semantics and coverage of both counters and healthy observations, with reset-aware
increase; incomplete/pre-cutover intervals are unavailable, not fabricated zero.

Live monitoring evaluates seven host-maintenance rules and 27 existing certificate
rules with zero evaluation errors. Both expected owners and fresh observations are
persisted; eleven certificate health series remain healthy. The Selectel discovery
signal is deliberately zero because needrestart is absent. No fake zero restart count
is emitted. Existing external alert delivery remains unconfigured/noop; no unsolicited
notification test was sent or claimed.

## Capability matrix and remaining work

| Surface | Current evidence/access | Automatic authority |
| --- | --- | --- |
| PROD/DEV lesson windows | Reviewed aggregate SQL through existing operator access | No installed least-privilege producer |
| LiveKit rooms/participants | Fresh guest-local VM metrics | Read-only observation |
| Collaboration/game/snapshot queue | Fresh VM metrics | Read-only observation |
| External activity / lesson realtime | Complete authoritative aggregate coverage not established | Unknown; deny |
| Both TURN surfaces | One-time bounded UDP/TCP socket evidence | No complete continuous allocation producer |
| Cross-host aggregate read route | No dedicated provisioned eligibility credential | Missing; deny |
| Global new-admission/token/connection exclusion | No proven existing lease | Missing; deny |
| Selectel restart inspection | Inspector absent | Unknown; deny |

No DB/Kube credentials or another host's SSH key were copied to an edge. A new
producer requires reviewed local least-privilege access. A new product admission
mechanism is outside this hotfix's non-goals. Until these capabilities exist,
automatic side-effecting installation/restarts stay disabled at all hours, including
03:00–05:00. Metadata/download, observation and security-debt warning/escalation
continue. Full executing cross-host/package ownership, per-owned-service debt and
producer freshness acceptance remain open; host aggregates alone do not close them.

## Local regression and integration boundary

Ten scheduler/activity/debt/NIC/lock tests, 26 certificate regressions, RF DEV/media/
edge-log contracts, Ansible syntax/previews, shell syntax and production Helm lint
pass. PromQL fixtures verify 24h/72h warning/escalation and resolution, counter reset,
old-series exclusion and incomplete cutover coverage. A disposable offline Ubuntu
harness using the installed apt daily script proved the original fake zlib/needrestart
and direct package hooks execute in the unprotected control and are never reached
under the candidate policy; download-only discovery continues and invalid APT syntax
is rejected. All test containers/temporary fixtures were removed.

PR #49 carries the final .21 release head into develop. Final source/target ancestry
and refreshed live revision proof are saved after merge in task-local delivery evidence,
without creating another release commit merely to embed its own final SHA. OpenSpec
remains incomplete for the capability gaps above; no archive is claimed.
