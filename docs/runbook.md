# Play&Say Dev Runbook

## Sprint 0 Status

Sprint 0 is complete. This runbook now describes the working dev baseline for Sprint 2.

## Planned AX41 Dev/Prod Topology

AX41 at `65.109.55.110` now serves the first `honey.school` production candidate: the Ubuntu 24.04 physical host, healthy mdadm RAID1/ext4, KVM/QEMU/libvirt, OpenTofu, firewall, WireGuard and VPN-only Cockpit baseline are active. The NAT-backed `playsay-prod` (`10.60.0.20`, 8 vCPU/42 GiB) and `playsay-dev` (`10.60.0.30`, 2 vCPU/12 GiB) Ubuntu VMs run independent k3s, ArgoCD and Sealed Secrets controllers. Prod has exactly seven human identities, 22 materials, 51 verified objects and 11 enrichments, with `hello` and dev history absent. All deployed prod ArgoCD apps are `Synced/Healthy`; `online.honey.school`, API, `key.honey.school`, collaboration signaling, LiveKit signaling and forced TURN reach the AX41 successfully. Human Maria/student login and rendered-material acceptance remain, so the old VPS stays unchanged as rollback through its paid lifetime. Email/payment provider workloads remain disabled until independent prod credentials are supplied. Object Storage remains a post-stabilization state/backup task, not a blocker to this cutover.

The full architecture, OpenSpec-style phased task checklist, rollback contract and acceptance gates are defined in [hetzner-ax41-dev-prod-plan.md](hetzner-ax41-dev-prod-plan.md), section 7. Execute phases in dependency order and mark a task complete only after recording its exact Git commit and non-secret evidence location. Do not treat that document as current runtime state, do not change current DNS/IP examples ahead of cutover, and do not sync new public-IP values through the current ArgoCD controller before it is frozen for migration.

The old VPS has only three paid days remaining. Immediately create and test an encrypted off-host PostgreSQL/Keycloak/MinIO recovery bundle; deletion must not leave the VPS as the only copy even if the full AX41 cutover is still incomplete. Amnezia is not migrated: leave its current containers untouched during the overlap, then accept that the service ends when the owner deletes the old VPS. AX41 administration uses its independent WireGuard management VPN.

The Jenkins controller is not yet present on the AX41 dev cluster; the active controller and its credential store remain on the retiring VPS. Do not delete the VPS until a clean Jenkins controller is installed from this repository on `playsay-dev`, fresh/re-authorized GitHub credentials and webhooks are configured, one affected-target build reaches GHCR/Git/ArgoCD successfully, and the old webhook/controller is disabled. Do not cold-copy the old Jenkins PVC or expose the replacement publicly; use the management VPN for its UI.

Authoritative safety capture `playsay-safety-v3-20260720T220404Z` completed on 2026-07-20. It explicitly dumps `playsay`, `keyboard` and full Keycloak PostgreSQL, includes the MinIO archive, Sealed Secrets recovery keys and sanitized inventories, and requires non-empty PostgreSQL 17 table-data catalogs. Transport/payload checksums and a local decrypt/archive verification passed. It was restored into new dev as 47 application tables, 10 keyboard tables, 88 Keycloak public tables and 815 MinIO filesystem entries. The earlier safety-v2 is checksum-valid but is superseded for application recovery because it selected the empty maintenance database. The encrypted files are off-host at `/Users/evgeniymednov/Backups/PlayAndSay/ax41-migration-20260720`; the RSA private key is stored separately at `/Users/evgeniymednov/.ssh/play_and_say_migration_backup_rsa.pem`. Do not delete the private key, place it in Git or copy it next to the bundle. This is a full-dev disaster-recovery capture, not the selective prod seed or final cutoff bundle. Evidence: `migrations/ax41/evidence/20260720-safety-v3.md`.

AX41 host automation is run from the `playsay-infra/ansible` directory so its configured role path is applied:

```bash
ansible-playbook \
  -i inventories/hetzner-ax41/hosts.yaml \
  playbooks/ax41-host.yaml
```

On 2026-07-20 Ubuntu was updated to kernel `6.8.0-136-generic`; the corrected reboot gate restored RAID, SSH, libvirt, WireGuard, UFW and VPN-only Cockpit automatically. Cockpit uses the `playsay-cockpit-vpn.service` late starter so its address-bound socket starts only after `wg0`; do not directly add an `After=wg-quick@wg0` dependency to `cockpit.socket`, because socket units are ordered before `sockets.target` and that creates a boot ordering cycle. The final complete Ansible run reported `changed=0`. RAID/SMART, firewall, reboot and VPN evidence is recorded at `migrations/ax41/evidence/20260720-ax41-host-vpn.md`.

The MacBook and phone WireGuard profiles are stored outside Git at `/Users/evgeniymednov/Backups/PlayAndSay/wireguard/macbook.conf` and `phone.conf`. Import each profile into a WireGuard-compatible client and activate it; gray/private client IP addresses are expected because `PersistentKeepalive=25` lets both clients initiate the tunnel to public endpoint `65.109.55.110:51820`. After activation, open `https://10.250.0.1:9090`, sign in as `playsay`, and retrieve its generated password from the macOS Keychain item `PlayAndSay AX41 Cockpit`. The Cockpit certificate is initially self-signed. Confirm a server-side handshake for both peers before disabling public SSH. Do not publish port 9090 in DNS or the public firewall.

Production is built only from protected numeric three-part branches named `release/<version>.<subversion>.<patch>`, for example `release/1.001.00`. Jenkins produces immutable `rel_1.001.00-N` candidates; after release verification, the selected digest is recorded in the matching `playsay-infra` release branch and manually synced by prod ArgoCD. Never deploy prod directly from `main`, `develop`, a free-form release name or `hotfix/*`; publish a hotfix through a new versioned release branch.

The `release/1.001.04` frontend release removes render-blocking Google Fonts traffic from both public SPAs and bundles Manrope/Roboto Flex in their images. Production promotion is limited to `web-app` (`web-release-1.001.04-6`, digest `sha256:8a8eaf71c7fbca52553e39ce32572532213201b94fe6462afcf991af0ba9f71b`) and `keyboard-app` (`key-frontend-release-1.001.04-6`, digest `sha256:598b52ba9327142903dcfd44c49c801c2f076895f4d607805cc9c50f7d0734ca`); the other production applications remain pinned to the accepted `release/1.001.03`. Both candidates passed Jenkins tests, dev rollout and browser smoke, then production ArgoCD sync and rollout reached `Synced/Healthy`. Cache-disabled production reloads loaded only local `.woff2` resources over TLS 1.2 and made no request to `fonts.googleapis.com` or `fonts.gstatic.com`; the temporary AX41 edge substitution was removed after that verification.

The approved initial prod seed is selective: Maria Mednova, the six students attached to her at cutoff, 22 Maria-owned materials excluding the test material `hello`, 51 referenced assets/MinIO objects and 11 HTML-game enrichments. Execute imports only from a reviewed protected manifest of immutable Keycloak subjects, application UUIDs, material UUIDs and object checksums; never select by names during the write step. Do not copy other dev users or dev lesson/assignment/submission/chat history. The source remains authoritative until the final cutoff and the detailed plan's count, login, referential-integrity and object-restore gates pass.

Migration is Git-first. Do not cold-copy k3s server state or local-path PVC directories to the AX41. Recreate the clean dev/prod VMs, k3s, ArgoCD applications and Jenkins from one recorded `playsay-infra` commit, then restore state through the committed export/import scripts. Dev receives a full encrypted PostgreSQL/Keycloak/MinIO bundle; prod receives only the filtered seed above. Raw dumps, Keycloak exports, plaintext secrets, private keys, OpenTofu state and MinIO objects stay outside Git in the encrypted off-host repository. Git contains their manifest schema, expected non-personal counts, bundle checksum and verification code.

Object Storage is not a prerequisite for the accelerated first `honey.school` cutover. Until the S3 backend is provisioned, run OpenTofu only on AX41 as `playsay`, never from Jenkins or a second session, with separate `0700` local states in `/var/lib/playsay-opentofu-state/{platform,dev,prod}`. Capture an encrypted off-host copy before and after every apply. Do not copy plaintext state to the workstation or Git. After the first production stabilization window, migrate each state with `tofu init -migrate-state`, verify remote versioning/locking, then remove local plaintext state only after a tested pull/restore.

The AX41 edge is generated by the `edge-proxy` Ansible role. It owns only `online.honey.school`, `key.honey.school`, `dev.online.honey.school` and `dev.key.honey.school`; it must not claim the root domain, mail or VPN-only ops names. One certbot certificate named `online.honey.school` covers all four names and renews automatically. Prod routes `/collab/ws` directly to collaboration NodePort `32086` and strips `/livekit/` before proxying signaling to prod VM port `7880`; the generic route continues to web NodePort `32083`. Keep these explicit realtime locations before the generic SPA location.

The planned AX41 split is dev 2 vCPU/12 GB and prod 8 vCPU/42 GB, leaving approximately 8 GiB of the host's 62 GiB usable RAM for Ubuntu, KVM/libvirt, edge routing, VPN and filesystem cache. On 2026-07-20 08:50-09:40 Europe/Moscow the current VPS used `0.87` compute cores on average (p95 `0.95`, max `0.98`) while `43.9%` average iowait, `0.53 GiB` available memory and active swap made headline CPU/load look much worse. Kubernetes working set was at most `5.95 GiB` in that lesson window and `6.24 GiB` across 2026-07-13 through 2026-07-20, so 12 GB gives dev material headroom without permanently reserving 16 GB. Keep Jenkins serialized. Increase dev to 3 vCPU through a reviewed OpenTofu commit only after post-migration evidence of sustained compute saturation, more than 30% CI-duration regression, or CPU-bound LiveKit/API failure; diagnose I/O and memory pressure separately. Do not enable memory ballooning; alert if host `MemAvailable` remains below 4 GiB for 15 minutes and do not increase either VM until sustained swap or memory pressure is ruled out.

OpenTofu remains the source of truth even though day-to-day operations are visual. Cockpit with the Machines/libvirt view is available only through the management VPN for host/VM status, graphs, storage, console and routine start/stop/reboot; Headlamp shows Kubernetes, and ArgoCD/Jenkins show delivery state. Do not create/delete VMs or change CPU, RAM, disks, networks or autostart in Cockpit: submit the change to Git, inspect the OpenTofu plan and apply it after review. Production apply is always a separate manual approval. If an emergency requires a direct Cockpit/`virsh` change, reconcile it into Git immediately and require a clean drift plan afterward.

## Vocabulary service

`vocabulary-service` разворачивается ArgoCD в `playsay-dev`, использует общий `playsay-app-db`, порт `8088` и secret `playsay-openai` только с чувствительным `api-key`. Модель и reasoning effort являются проверяемой Git-конфигурацией: dev/prod используют `gpt-5.6-sol` и `low` для словарных подсказок. Jenkins job `playsay-vocabulary-service-develop` выполняет идемпотентные `liquibase status/update` на каждом deployable build, собирает `playsay-vocabulary-service` и обновляет `helm-charts/vocabulary-service/values-dev.yaml`. Не добавляйте для vocabulary оптимизацию skip-by-changelog-diff: она может оставить новый namespace/database без таблиц, если первый webhook build не запускал migration. Web и keyboard nginx направляют `/api/vocabulary/**` на ClusterIP `vocabulary-service`; отсутствие OpenAI key не блокирует ручное сохранение карточек. Web UI автоматически запрашивает до трёх уверенных вариантов после ввода слова и позволяет перегенерировать их с пользовательским уточнением и исключением уже показанных переводов.

Dev pod `vocabulary-service` использует ограниченный профиль `25m / 96Mi` requests и `500m / 384Mi` limits; JVM работает с `InitialRAMPercentage=25` и `MaxRAMPercentage=55`. RollingUpdate использует `maxSurge=0`/`maxUnavailable=1`, чтобы single-node dev не запускал две JVM словаря одновременно. Health probes используют `timeoutSeconds=5`, а liveness допускает шесть последовательных сбоев: это не увеличивает память pod, но предотвращает ложный restart Spring JVM при кратковременной перегрузке single-node VPS во время Jenkins build.

## Sprint 0 Goal

Create a reproducible dev environment:

- Ubuntu 24.04 VPS
- k3s
- Sealed Secrets
- ArgoCD
- Headlamp Kubernetes UI
- Jenkins
- api-gateway backend and React SPA deployed by ArgoCD

In coexist mode on the current VPS, `ingress-nginx` and `cert-manager` are not installed by default. The existing host nginx remains the public entry point for the site, ops UI, and product SPA, and proxies k3s services to local Kubernetes NodePorts.

## Human-Owned Prerequisites

1. Create or choose a VDSina VPS manually:
   - Ubuntu 24.04
   - Amsterdam
   - 2 vCPU / 4 GB RAM / 80 GB NVMe for Sprint 0
   - current dev shape after the 2026-05-24 upgrade: 4 vCPU / 8 GB RAM / 160 GB NVMe / 32 TB traffic
   - key-based `root` SSH access
2. Create GitHub organization or user namespace.
3. Create repositories:
   - `playsay-platform`
   - `playsay-infra`
4. Point DNS records to the VPS:
   - `ops.play-and-say.ru`
   - `online.play-and-say.ru`
   - `key.play-and-say.ru`
5. Create GitHub credentials for Jenkins (see below).

## One-Command Bootstrap

Run from the local `playsay-infra` directory:

```bash
./scripts/bootstrap-dev.sh \
  --ip <server-ip> \
  --domain dev.example.com \
  --email admin@example.com
```

The script:

1. Uses normal SSH config/agent, or a specific key passed by `--ssh-key`.
2. Verifies key-based access to `root@<server-ip>`.
3. Writes `ansible/inventories/dev/hosts.yaml`.
4. Runs Ansible to configure baseline Ubuntu packages, swap, k3s, and node exporter.
5. Copies the infrastructure scripts to `/tmp/playsay-infra-bootstrap` on the VPS.
6. Installs Sealed Secrets, ArgoCD, Headlamp, and Jenkins directly on the VPS using `/etc/rancher/k3s/k3s.yaml`.

By default the script runs in `coexist` mode:

- does not change SSH hardening;
- does not manage UFW/firewall rules;
- does not install Docker;
- does not install ingress-nginx or cert-manager;
- does not bind Kubernetes services to ports 80/443 directly;
- restricts NodePort services to `127.0.0.0/8` during k3s install;
- installs `playsay-public-port-guard.service` to block public access to k3s API/kubelet/flannel technical ports on the public interface;
- binds node exporter to `127.0.0.1:9100`;
- writes only one host nginx file: `/etc/nginx/conf.d/playsay-k8s-dev.conf`.

Use separate subdomains such as `argocd.dev.example.com` and `headlamp.dev.example.com`. Do not pass the existing production site hostname as `--domain`, otherwise nginx server names may overlap.

For ArgoCD to sync the api-gateway application, `playsay-infra` must be pushed to the GitHub URL referenced in `argocd-apps/dev/root-app.yaml`.

For a server that already has Amnezia VPN and a public nginx site, keep the default `coexist` mode:

```bash
./scripts/bootstrap-dev.sh \
  --ip 89.124.113.223 \
  --domain play-and-say.ru \
  --ops-host ops.play-and-say.ru \
  --ops-port 18443 \
  --email admin@example.com
```

This creates nginx server blocks for infrastructure UI and the product SPA:

- `https://ops.play-and-say.ru:18443/headlamp/`
- `https://ops.play-and-say.ru:18443/argocd/`
- `https://ops.play-and-say.ru:18443/jenkins/`
- `https://ops.play-and-say.ru:18443/keycloak/` (Sprint 1 auth)
- `https://ops.play-and-say.ru:18443/victoria-metrics/vmui/` (dev monitoring)
- `https://online.play-and-say.ru`
- `https://key.play-and-say.ru`
- `wss://online.play-and-say.ru/collab/ws` (Sprint 5 collaboration websocket)

The existing `play-and-say.ru` site server block is not overwritten.
The auxiliary `profit-kuban.play-and-say.ru` static vhost is managed separately in `/etc/nginx/conf.d/profit-kuban.conf`; it is not generated by `bootstrap-dev.sh`.

Current dev TLS policy, since 2026-06-03: keep host nginx restricted to TLS 1.2 only for the public site, product SPA, keyboard trainer, auxiliary static vhosts, and ops route. TLS/SNI handshake failures were reported from Russian consumer networks MTS, t2, and MGTS; after disabling TLS 1.3, access recovered from the affected networks. The change was made manually in `/etc/nginx/nginx.conf` and `/etc/letsencrypt/options-ssl-nginx.conf`; backups are `/etc/nginx/nginx.conf.bak.tls12-test-20260603164526` and `/etc/letsencrypt/options-ssl-nginx.conf.bak.tls12-test-20260603164526`. Current validation expects `openssl s_client -tls1_2` to succeed and `openssl s_client -tls1_3` to fail with `protocol version alert`. Do not re-enable TLS 1.3 on dev without a dedicated retest from MTS, t2, and MGTS. Rollback command if TLS 1.3 must be restored for a controlled experiment:

```bash
ssh root@89.124.113.223 '
set -e
cp /etc/nginx/nginx.conf.bak.tls12-test-20260603164526 /etc/nginx/nginx.conf
cp /etc/letsencrypt/options-ssl-nginx.conf.bak.tls12-test-20260603164526 /etc/letsencrypt/options-ssl-nginx.conf
nginx -t
systemctl reload nginx
'
```

TLS mode defaults to `auto`: if `/etc/letsencrypt/live/ops.play-and-say.ru/` exists, nginx uses that certificate; otherwise the script creates a self-signed certificate under `/etc/nginx/playsay-ops/`. Browsers will warn on self-signed certificates, but traffic is encrypted. After DNS is ready, replace it with a Let's Encrypt certificate and rerun the script:

```bash
mkdir -p /var/www/letsencrypt/.well-known/acme-challenge
cat >/etc/nginx/conf.d/playsay-ops-acme.conf <<'EOF'
server {
    listen 80;
    listen [::]:80;
    server_name ops.play-and-say.ru;

    location ^~ /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
        default_type "text/plain";
        try_files $uri =404;
    }

    location / {
        return 301 https://$host:18443$request_uri;
    }
}
EOF
nginx -t && systemctl reload nginx

certbot certonly \
  --webroot \
  -w /var/www/letsencrypt \
  -d ops.play-and-say.ru \
  --non-interactive \
  --agree-tos \
  --email admin@play-and-say.ru

mkdir -p /etc/letsencrypt/renewal-hooks/deploy
cat >/etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
nginx -t
systemctl reload nginx
EOF
chmod 0755 /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh

./scripts/bootstrap-dev.sh \
  --ip 89.124.113.223 \
  --domain play-and-say.ru \
  --ops-host ops.play-and-say.ru \
  --ops-port 18443 \
  --ops-tls-mode existing \
  --email admin@example.com
```

For `online.play-and-say.ru`, issue a matching Let's Encrypt certificate after the web-app upstream is available:

```bash
mkdir -p /var/www/letsencrypt/.well-known/acme-challenge
certbot certonly \
  --webroot \
  -w /var/www/letsencrypt \
  -d online.play-and-say.ru \
  --non-interactive \
  --agree-tos \
  --email admin@play-and-say.ru

./scripts/bootstrap-dev.sh \
  --ip 89.124.113.223 \
  --domain play-and-say.ru \
  --ops-host ops.play-and-say.ru \
  --ops-port 18443 \
  --ops-tls-mode existing \
  --online-host online.play-and-say.ru \
  --online-tls-mode existing \
  --email admin@example.com
```

For `key.play-and-say.ru`, issue a matching Let's Encrypt certificate after `keyboard-app` has a healthy upstream:

```bash
mkdir -p /var/www/letsencrypt/.well-known/acme-challenge
certbot certonly \
  --webroot \
  -w /var/www/letsencrypt \
  -d key.play-and-say.ru \
  --non-interactive \
  --agree-tos \
  --email admin@play-and-say.ru

./scripts/bootstrap-dev.sh \
  --ip 89.124.113.223 \
  --domain play-and-say.ru \
  --ops-host ops.play-and-say.ru \
  --ops-port 18443 \
  --ops-tls-mode existing \
  --online-host online.play-and-say.ru \
  --online-tls-mode existing \
  --key-host key.play-and-say.ru \
  --key-tls-mode existing \
  --email admin@example.com
```

If you know the Amnezia VPN CIDR or a fixed admin IP, restrict the ops UI:

```bash
./scripts/bootstrap-dev.sh \
  --ip 89.124.113.223 \
  --domain play-and-say.ru \
  --ops-host ops.play-and-say.ru \
  --ops-port 18443 \
  --ops-allow-cidrs 10.8.0.0/24,203.0.113.5/32 \
  --email admin@example.com
```

Current dev decision for Sprint 1: keep `ops.play-and-say.ru:18443` reachable from the network, but protected by Jenkins/ArgoCD/Headlamp logins. Later, after Keycloak is available, evaluate a shared SSO flow through the Play&Say Keycloak realm for a more convenient ops login.

If you want to avoid any nginx changes too:

```bash
./scripts/bootstrap-dev.sh \
  --ip 89.124.113.223 \
  --domain play-and-say.ru \
  --email admin@example.com \
  --no-host-nginx
```

## Public Site and Online App Hostnames

Current DNS/nginx split:

- `play-and-say.ru` stays the public marketing/site host.
- `online.play-and-say.ru` serves the React product SPA from k3s service `web-app`.
- `online.play-and-say.ru/collab/ws` proxies directly to the `collaboration-service` NodePort for Yjs websocket rooms.
- `key.play-and-say.ru` serves the anonymous keyboard trainer with authenticated saved progress from k3s service `keyboard-app`.
- `profit-kuban.play-and-say.ru` serves the one-off static Profit-kuban snapshot from `/var/www/profit-kuban/current` through host nginx only.
- `ops.play-and-say.ru:18443` is reserved for dev infrastructure UI.
- `ops.play-and-say.ru:18443/keycloak/` serves the Sprint 1 Keycloak dev instance.

The login redirect is not only an nginx setting. `online.play-and-say.ru` and `key.play-and-say.ru` must both be present in the Keycloak `playsay-web` client allowed redirect URIs, web origins, and post-logout redirects. The future `play-and-say.ru` login button should start Keycloak auth and return users to `online.play-and-say.ru`.

## Auxiliary Static Site: Profit-kuban

`https://profit-kuban.play-and-say.ru` is an auxiliary static snapshot for ООО «ПРОФИТ». It is intentionally outside k3s, ArgoCD and Play&Say CI/CD, and must not replace or edit the root `play-and-say.ru` server block.

Runtime state on the VPS:

- document root symlink: `/var/www/profit-kuban/current`
- immutable releases: `/var/www/profit-kuban/releases/<timestamp>`
- nginx vhost: `/etc/nginx/conf.d/profit-kuban.conf`
- certificate: `/etc/letsencrypt/live/profit-kuban.play-and-say.ru/`

Redeploy the current local snapshot from the Mac:

```bash
RELEASE="$(date -u +%Y%m%dT%H%M%SZ)"
SSH_KEY="$HOME/.ssh/play_and_say_vps_ed25519"

ssh -i "$SSH_KEY" -o IdentitiesOnly=yes root@89.124.113.223 \
  "mkdir -p /var/www/profit-kuban/releases/$RELEASE"

rsync -az --delete \
  --exclude '.DS_Store' \
  --exclude '.server.pid' \
  --exclude '.server.log' \
  --exclude '.check/' \
  -e "ssh -i $SSH_KEY -o IdentitiesOnly=yes" \
  /Users/evgeniymednov/Documents/Projects/Profit-kuban/ \
  root@89.124.113.223:/var/www/profit-kuban/releases/$RELEASE/

ssh -i "$SSH_KEY" -o IdentitiesOnly=yes root@89.124.113.223 "
set -euo pipefail
chown -R root:www-data /var/www/profit-kuban/releases/$RELEASE
find /var/www/profit-kuban/releases/$RELEASE -type d -exec chmod 0755 {} +
find /var/www/profit-kuban/releases/$RELEASE -type f -exec chmod 0644 {} +
ln -sfn releases/$RELEASE /var/www/profit-kuban/current
nginx -t
systemctl reload nginx
"
```

If the certificate is missing, issue it with webroot challenge after the HTTP exact vhost exists:

```bash
mkdir -p /var/www/letsencrypt/.well-known/acme-challenge
certbot certonly \
  --webroot \
  -w /var/www/letsencrypt \
  -d profit-kuban.play-and-say.ru \
  --non-interactive \
  --agree-tos \
  --email admin@play-and-say.ru
```

Verify after each deploy:

```bash
curl -I http://profit-kuban.play-and-say.ru/
curl -I https://profit-kuban.play-and-say.ru/
curl -I https://profit-kuban.play-and-say.ru/styles.css
curl -I https://profit-kuban.play-and-say.ru/assets/site/logo-full.png
openssl s_client -connect profit-kuban.play-and-say.ru:443 -servername profit-kuban.play-and-say.ru -tls1_2 </dev/null
openssl s_client -connect profit-kuban.play-and-say.ru:443 -servername profit-kuban.play-and-say.ru -tls1_3 </dev/null
```

## Keyboard Trainer

`Play&Say Key` runs as a separate anonymous trainer with authenticated saved progress at `https://key.play-and-say.ru`.

Runtime objects:

- frontend ArgoCD app: `keyboard-app`
- backend ArgoCD app: `keyboard-service`
- frontend service: `keyboard-app.playsay-dev.svc.cluster.local`, dev NodePort `32087`
- backend service: `keyboard-service.playsay-dev.svc.cluster.local`
- backend database: `keyboard`
- backend role/user: `keyboard_app`
- runtime/migration secret: `playsay-keyboard-db`

Bootstrap and secret sync:

```bash
./scripts/sync-keyboard-db-secret.sh
kubectl -n playsay-data get secret playsay-postgres-keyboard
kubectl -n playsay-dev get secret playsay-keyboard-db
kubectl -n jenkins get secret playsay-keyboard-db
```

The source secret `playsay-postgres-keyboard` is used by CloudNativePG declarative role management for `keyboard_app`; the synced `playsay-keyboard-db` secret contains `jdbc-uri`, `username`, and `password` for runtime and Jenkins Liquibase. Do not print secret values.

Anonymous `Play&Say Key` practice now stores error analytics through public keyboard-service routes under `/api/anonymous/**`. The browser sends a local `playsay.key.anonymousDeviceId`; the service stores that device id plus an HMAC hash of IP/User-Agent features and never stores the raw IP as the profile key. For production-like environments, create a Kubernetes Secret such as `playsay-keyboard-anonymous` with key `fingerprint-secret` and set `anonymous.fingerprintSecret.existingSecret` / `anonymous.fingerprintSecret.key` in the keyboard-service Helm values. Do not print the secret value. Dev can run without that Secret using the application fallback, but that is not suitable for production-like privacy isolation.

Current anonymous public API hardening is limited to request validation and payload caps for map sizes/key lengths. Dedicated anti-DDoS/rate limiting for `/api/anonymous/**` remains technical debt before a wider public launch.

Keycloak client wiring is managed by:

```bash
./scripts/configure-keycloak-dev.sh
```

The `playsay-web` public client must allow `https://key.play-and-say.ru/*`, `http://localhost:5175/*`, `http://localhost:4175/*`, and the same `127.0.0.1` origins. The trainer uses Authorization Code + PKCE for saved progress and does not use local password/JWT auth. Anonymous practice uses bundled frontend chord sets and must not call protected `/api/*` endpoints without a token.

Keyboard deploys run through separate downstream Jenkins jobs. For normal `develop`/`release/*` pushes, `playsay-platform-dispatch-develop` triggers only the affected keyboard job; manual runs can still use the jobs directly with `BRANCH_NAME` and optional `GITHUB_AFTER`:

- `playsay-keyboard-backend-develop`: tests `:keyboard-service`, applies XML Liquibase to `keyboard`, builds/pushes `ghcr.io/mednov-ai/playsay-keyboard-service`, updates `helm-charts/keyboard-service/values-dev.yaml`, waits for rollout.
- `playsay-keyboard-frontend-develop`: runs `keyboard-app` lint/test/build, builds/pushes `ghcr.io/mednov-ai/playsay-keyboard-app`, updates `helm-charts/keyboard-app/values-dev.yaml`, waits for rollout, then browser-smokes `https://key.play-and-say.ru`.

Check rollout:

```bash
kubectl -n argocd get application keyboard-service keyboard-app
kubectl -n playsay-dev get deploy,svc,pods -l app.kubernetes.io/name=keyboard-service
kubectl -n playsay-dev get deploy,svc,pods -l app.kubernetes.io/name=keyboard-app
curl -k -I --resolve key.play-and-say.ru:443:89.124.113.223 https://key.play-and-say.ru/
curl -k -I --resolve key.play-and-say.ru:443:89.124.113.223 https://key.play-and-say.ru/healthz
```

Expected unauthenticated browser behavior: the trainer screen is visible without a blocking Play overlay; inline Play/Space starts a centered blocking `3 -> 2 -> 1` countdown, typing is ignored during countdown, and completed guest sessions are submitted best-effort to `/api/anonymous/training/results` while the local session continues even if that request fails. The typing strip is a visually obvious two-line focus area with natural in-chord letter spacing and visible gaps only for real spaces; its visible capacity follows measured line width and must not overflow on a 13-inch MacBook-class viewport. If typing stops for more than 3 seconds during a running session, a centered pause/resume overlay appears and Space resumes the same session; Esc exits countdown or paused session focus back to the normal non-blocking trainer interface. After 2 anonymous completions the app softly asks for a display name and stores it in the anonymous profile; after 5 anonymous completions the app shows a soft registration prompt; the sign-in action sends the user through Keycloak and callback returns to `https://key.play-and-say.ru/auth/callback`. Laptop smoke should verify that a full 13-inch class browser viewport has no document-level vertical scroll and the virtual keyboard is centered near edge-to-edge.

## Object Storage

Dev material assets use S3-compatible object storage. The ArgoCD app is `minio`, deployed to namespace `storage` from `helm-charts/minio`.

Current dev shape:

- service: `minio.storage.svc.cluster.local:9000`;
- bucket used by `api-gateway`: `playsay-material-assets`;
- credentials secret: `playsay-object-storage`, copied into namespaces `storage` and `playsay-dev`;
- MinIO is not exposed through host nginx or a public NodePort.

Create or refresh the object-storage secret without printing values:

```bash
./scripts/sync-object-storage-secret.sh
```

The script creates `playsay-object-storage` in namespace `storage` if missing, then copies it to `playsay-dev`. For staging/prod or managed S3-compatible storage, keep the backend contract and change only Helm values/secret values:

- `PLAYSAY_STORAGE_PROVIDER=s3`
- `PLAYSAY_S3_ENDPOINT`
- `PLAYSAY_S3_REGION`
- `PLAYSAY_S3_BUCKET`
- `PLAYSAY_S3_ACCESS_KEY`
- `PLAYSAY_S3_SECRET_KEY`
- `PLAYSAY_S3_PATH_STYLE_ACCESS`
- `PLAYSAY_S3_CREATE_BUCKET`

`api-gateway` streams private material assets through `/api/materials/{materialId}/assets/{assetId}/content`; browsers never need direct MinIO access. YouTube relay thumbnails are stored by `media-service` into the same bucket using the same `playsay-object-storage` secret, while `api-gateway` creates/reuses the `material_asset` row. Legacy `data:image` material assets are intentionally not supported after the MinIO migration.

Check object storage state:

```bash
kubectl -n argocd get application minio
kubectl -n storage get pods,pvc,svc
kubectl -n playsay-dev get secret playsay-object-storage
```

## Payment Service

Sprint 8 adds a separate `payment-service` Spring Boot app in namespace `playsay-dev`.

Runtime wiring:

- ArgoCD app: `payment-service`
- Kubernetes service: `payment-service.playsay-dev.svc.cluster.local`
- api-gateway env:
  - `PLAYSAY_PAYMENT_SERVICE_BASE_URL`
  - `PLAYSAY_PAYMENT_SERVICE_TOKEN`
- payment-service env:
  - `PLAYSAY_PAYMENT_SERVICE_TOKEN`
  - `PLAYSAY_PAYMENT_PROVIDER`
  - `PLAYSAY_PAYMENT_PUBLIC_BASE_URL`
  - `PLAYSAY_YOOKASSA_API_URL`
  - `PLAYSAY_YOOKASSA_SHOP_ID`
  - `PLAYSAY_YOOKASSA_SECRET_KEY`

The base Helm chart keeps `paymentService.provider: disabled` so a new environment can roll out before YooKassa credentials are created. Dev `values-dev.yaml` uses `paymentService.provider: yookassa`; the `playsay-payment` secret in `playsay-dev` must therefore contain `service-token`, `yookassa-shop-id`, and `yookassa-secret-key` before syncing `payment-service`.

For an internal-only disabled-provider smoke, create only the shared service token without printing values:

```bash
kubectl -n playsay-dev create secret generic playsay-payment \
  --from-literal=service-token="$(openssl rand -base64 32)" \
  --dry-run=client -o yaml | kubectl apply -f -
```

To enable or rotate sandbox payments, create or update the same `playsay-payment` secret with YooKassa test credentials:

```bash
kubectl -n playsay-dev create secret generic playsay-payment \
  --from-literal=service-token="$(openssl rand -base64 32)" \
  --from-literal=yookassa-shop-id="<test-shop-id>" \
  --from-literal=yookassa-secret-key="<test-secret-key>" \
  --dry-run=client -o yaml | kubectl apply -f -
```

Then set `helm-charts/payment-service/values-dev.yaml`:

```yaml
paymentService:
  provider: yookassa
```

and deploy through the normal Jenkins -> GHCR -> playsay-infra -> ArgoCD path. YooKassa does not have universal public test credentials; use the test shop credentials issued in the YooKassa merchant cabinet. Do not commit or print the secret values.

The YooKassa merchant cabinet notification URL for dev is:

```text
https://online.play-and-say.ru/api/payment-webhooks/yookassa
```

Keep this URL in YooKassa test settings when rotating credentials; Play&Say does not create YooKassa webhooks automatically.

Because `api-gateway` and `payment-service` read `playsay-payment` keys as environment variables, Kubernetes does not update already-running pods after secret creation or rotation. After creating or rotating this secret, roll both deployments so they pick up the new values:

```bash
kubectl -n playsay-dev rollout restart deployment/api-gateway deployment/payment-service
kubectl -n playsay-dev rollout status deployment/api-gateway
kubectl -n playsay-dev rollout status deployment/payment-service
```

Check payment state:

```bash
kubectl -n argocd get application payment-service
kubectl -n playsay-dev get deploy,svc,pods -l app.kubernetes.io/name=payment-service
kubectl -n playsay-dev get secret playsay-payment
```

## Registration And Email Services

Custom email registration is split into two Spring Boot apps in namespace `playsay-dev`:

- `registration-service`: public registration state machine, pending token storage, managed-student invite storage/token exchange, Keycloak user activation, and password reset email-code state machine for active Keycloak users.
- `email-service`: transactional email DB-template rendering and external delivery provider integration. Dev uses Unisender Go Web API because SMTP ports to `smtp.go2.unisender.ru` time out from the dev network; SMTP remains the default fallback/provider option for other environments. Spring Mail SMTP healthcheck is disabled by default, so readiness follows the service process rather than blocked SMTP ports.

The public registration facade is `api-gateway`; it must forward the resolved browser client address to `registration-service` so the service's per-IP rate limiter is not applied to one shared gateway/ingress IP. `registration-service` still falls back to the direct remote address for local/internal calls.

Runtime wiring:

- ArgoCD apps: `registration-service`, `email-service`
- Kubernetes services:
  - `registration-service.playsay-dev.svc.cluster.local`
  - `email-service.playsay-dev.svc.cluster.local`
- api-gateway env:
  - `PLAYSAY_REGISTRATION_SERVICE_BASE_URL`
  - `PLAYSAY_REGISTRATION_SERVICE_TOKEN`
  - `PLAYSAY_USER_DATA_SERVICE_TOKEN`
  - `PLAYSAY_AI_TUTOR_SERVICE_BASE_URL`
  - `PLAYSAY_VOCABULARY_SERVICE_BASE_URL`
  - `PLAYSAY_KEYBOARD_SERVICE_BASE_URL`
  - `PLAYSAY_EMAIL_SERVICE_BASE_URL`
  - `PLAYSAY_EMAIL_SERVICE_TOKEN`
  - `PLAYSAY_PUBLIC_APP_URL`
  - `PLAYSAY_CHAT_EMAIL_INITIAL_DELAY` (default `PT2M`)
  - `PLAYSAY_CHAT_EMAIL_COOLDOWN` (default `PT10M`)
  - `PLAYSAY_CHAT_EMAIL_POLL_DELAY_MS` (default `30000`)
  - `PLAYSAY_CHAT_EMAIL_RETRY_DELAYS` (default `PT1M,PT5M,PT15M`)
- registration-service env:
  - `PLAYSAY_REGISTRATION_SERVICE_TOKEN`
  - `PLAYSAY_REGISTRATION_PUBLIC_BASE_URL`
  - `PLAYSAY_REGISTRATION_PASSWORD_RESET_CODE_TTL_MINUTES` (default `15`)
  - `PLAYSAY_REGISTRATION_PASSWORD_RESET_MAX_ATTEMPTS` (default `5`)
  - `PLAYSAY_KEYCLOAK_BASE_URL`
  - `PLAYSAY_KEYCLOAK_REALM`
  - `PLAYSAY_KEYCLOAK_STUDENT_TOKEN_CLIENT_ID` (default `playsay-web`)
  - `PLAYSAY_KEYCLOAK_ADMIN_CLIENT_ID`
  - `PLAYSAY_KEYCLOAK_ADMIN_CLIENT_SECRET`
  - `PLAYSAY_EMAIL_SERVICE_BASE_URL`
  - `PLAYSAY_EMAIL_SERVICE_TOKEN`
- email-service env:
  - `PLAYSAY_EMAIL_DELIVERY_PROVIDER`
  - `PLAYSAY_EMAIL_SERVICE_TOKEN`
  - `PLAYSAY_EMAIL_FROM_ADDRESS`
  - `PLAYSAY_EMAIL_FROM_NAME`
  - `PLAYSAY_EMAIL_SMTP_HOST`
  - `PLAYSAY_EMAIL_SMTP_PORT`
  - `PLAYSAY_EMAIL_SMTP_USERNAME`
  - `PLAYSAY_EMAIL_SMTP_PASSWORD`
  - `PLAYSAY_EMAIL_SMTP_AUTH`
  - `PLAYSAY_EMAIL_SMTP_STARTTLS`
  - `PLAYSAY_EMAIL_SMTP_HEALTH_ENABLED` (default `false`)
  - `PLAYSAY_EMAIL_UNISENDER_API_BASE_URL`
  - `PLAYSAY_EMAIL_UNISENDER_USER_ID`
  - `PLAYSAY_EMAIL_UNISENDER_API_KEY`
  - `PLAYSAY_EMAIL_UNISENDER_WEBHOOK_URL`
  - `PLAYSAY_EMAIL_REPLAY_ENCRYPTION_KEY` (base64-encoded 32-byte AES key; secret)
  - `PLAYSAY_EMAIL_DEFAULT_REPLAY_TTL` (default `PT72H`)
  - `PLAYSAY_EMAIL_PROVIDER_TRACKING_TTL` (default `PT72H`)
  - `PLAYSAY_EMAIL_PROVIDER_RECONCILE_WINDOW` (default `PT5M`)
  - `PLAYSAY_EMAIL_PROVIDER_RECONCILE_OVERLAP` (default `PT1M`)
  - `PLAYSAY_EMAIL_PROVIDER_RECONCILE_POLL_MS` (default `30000`; polls an active async dump, while completed reconciliation windows advance every five minutes)
  - `PLAYSAY_EMAIL_WEBHOOK_CHECK_MS` (default `3600000`)

Run or rerun Keycloak bootstrap after this change:

```bash
./scripts/configure-keycloak-dev.sh
```

It creates/updates the confidential Keycloak client `playsay-registration-service`, assigns its service account the required `realm-management` roles for user lookup/update/delete and role reads, enables direct access grants on the public `playsay-web` client for server-side managed-student invite exchange, and writes `keycloak-client-id`, `keycloak-client-secret` plus a stable randomly generated `service-token` into Kubernetes secret `playsay-registration` in namespace `playsay-dev`. Re-running the script preserves an existing service token. Secret values are not printed. The same `service-token` is mounted into `api-gateway`, `registration-service`, `ai-tutor-service`, `vocabulary-service` and `keyboard-service` for internal user-management/data-purge calls only; it must never be exposed to the SPA.

Create the `playsay-email` secret before syncing `email-service` and `registration-service`. For dev, use Unisender Go. Keep the API key outside Git and do not print it:

```bash
export UNISENDER_API_KEY="<unisender-go-api-key>"
export EMAIL_REPLAY_ENCRYPTION_KEY="$(openssl rand -base64 32)"

kubectl -n playsay-dev create secret generic playsay-email \
  --from-literal=service-token="$(openssl rand -base64 32)" \
  --from-literal=from-address="no-reply@play-and-say.ru" \
  --from-literal=smtp-host="smtp.go2.unisender.ru" \
  --from-literal=smtp-port="587" \
  --from-literal=smtp-username="8236338" \
  --from-literal=smtp-password="$UNISENDER_API_KEY" \
  --from-literal=smtp-auth="true" \
  --from-literal=smtp-starttls="true" \
  --from-literal=unisender-api-key="$UNISENDER_API_KEY" \
  --from-literal=replay-encryption-key="$EMAIL_REPLAY_ENCRYPTION_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -
```

For an existing dev secret, add the replay key only if it is absent; do not rotate it while unexpired replay snapshots may still be resent:

```bash
if ! kubectl -n playsay-dev get secret playsay-email -o jsonpath='{.data.replay-encryption-key}' | grep -q .; then
  REPLAY_SECRET_VALUE="$(openssl rand -base64 32)"
  REPLAY_SECRET_DATA="$(printf '%s' "$REPLAY_SECRET_VALUE" | base64 | tr -d '\n')"
  kubectl -n playsay-dev patch secret playsay-email --type merge -p "{\"data\":{\"replay-encryption-key\":\"$REPLAY_SECRET_DATA\"}}"
fi
```

The dev Helm values set `PLAYSAY_EMAIL_DELIVERY_PROVIDER=unisender-api`, `PLAYSAY_EMAIL_UNISENDER_API_BASE_URL=https://goapi.unisender.ru/ru/transactional/api/v1`, `PLAYSAY_EMAIL_UNISENDER_USER_ID=8236338`, and `PLAYSAY_EMAIL_UNISENDER_WEBHOOK_URL=https://online.play-and-say.ru/api/webhooks/unisender`. `unisender-api-key` and `replay-encryption-key` are secrets. SMTP keys stay in the secret as a fallback record and for parity with the generic chart. Unisender Go transactional API expects the credential field as `api_key` in the JSON body. On the Unisender Go `free_tier`, delivery may be limited to verified domains or verified recipient emails; provider error `403` / `code=903` means the recipient domain/email is not yet allowed by the provider, not that Play&Say rate limiting blocked registration.

`email-service` registers/checks the UniSender Go JSON webhook hourly and reconciles missed events with durable `event-dump/*` windows. The first window covers the previous five minutes; later windows advance by five minutes with a one-minute overlap. An active asynchronous dump is polled every 30 seconds until `ready` or `failed`, so no second dump is created concurrently. Provider `delivered` is terminal for the delivery objective; later `opened`, `clicked`, subscription, spam, or bounce webhooks may still replace the displayed factual status. `soft_bounced` remains non-terminal because UniSender Go continues delivery attempts.

After rollout, sign in as `ADMIN` and open workspace section **Письма**. Confirm that a non-admin profile has no such section and receives `403` from `/api/admin/email-deliveries`. The admin log must show local status separately from provider status, auto-refresh about every 30 seconds, show attempt history without email body/provider credentials, and enable resend only for an eligible failed/expired record. Verify webhook and reconciliation without printing payloads or credentials:

```bash
KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n playsay-dev logs deploy/email-service --since=20m | grep -E 'reconciliation|webhook|delivery'
KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n playsay-dev get pods -l app.kubernetes.io/name=email-service
```

Email texts are not hardcoded in code. `email-service` Liquibase creates and seeds app PostgreSQL table `email_templates` with active FreeMarker templates:

- `registration-confirmation` in `ru`, `en`, `de`, `fr`
- `password-reset-code` in `ru`, `en`, `de`, `fr`
- `lesson-reminder-30m` in `ru`, `en`, `de`, `fr`
- `lesson-rescheduled` in `ru`, `en`, `de`, `fr`
- `chat-unread-digest` in `ru`, `en`, `de`, `fr`

Template rows contain `subject_template`, `text_template`, `html_template`, `version`, `enabled`, timestamps. Runtime rendering falls back to `ru` only if a localized row is missing. Edit rows carefully in DB or add a new Liquibase changeset; keep required model variables (`confirmationUrl`, `code`, `expiresMinutes`) intact.

Do not commit or print email provider credentials. After creating or rotating `playsay-registration` or `playsay-email`, restart the affected deployments so env vars are refreshed:

```bash
kubectl -n playsay-dev rollout restart deployment/api-gateway deployment/registration-service deployment/email-service deployment/ai-tutor-service deployment/vocabulary-service deployment/keyboard-service
kubectl -n playsay-dev rollout status deployment/registration-service
kubectl -n playsay-dev rollout status deployment/email-service
```

Check registration/email state:

```bash
kubectl -n argocd get application registration-service email-service
kubectl -n playsay-dev get deploy,svc,pods -l app.kubernetes.io/name=registration-service
kubectl -n playsay-dev get deploy,svc,pods -l app.kubernetes.io/name=email-service
kubectl -n playsay-dev get secret playsay-registration playsay-email
```

Registration rate limits use a 1-hour window; dev currently allows 20 attempts per normalized email and 30 attempts per resolved client address. If `/api/registration/start` returns `429`, first check whether it is a real per-email/per-client limit or a proxy-address issue:

```bash
kubectl -n playsay-dev logs deploy/api-gateway --since=30m | grep 'registration-service request failed'
kubectl -n playsay-dev logs deploy/registration-service --since=30m | grep -E '429|Too Many Requests|Rate'
```

A healthy gateway forwards `X-Forwarded-For` to `registration-service`; a shared gateway/ingress IP must not be the only address used for public registration rate limits. A rollout restart clears the in-memory limiter, but treat it as a temporary dev relief only. If an earlier email-provider outage created a disabled Keycloak user without a pending registration row, retrying `/register` for that email should create a fresh pending token and send a new confirmation email instead of silently returning `CHECK_EMAIL`.

Manual auth smoke:

1. Open `https://online.play-and-say.ru/register`; verify the welcome page and Keycloak login theme both expose registration links.
2. Register with a password that passes the visible policy (`8..128` chars, 3 character classes, no email/name fragments).
3. Confirm the email and sign in through Keycloak; `/api/me` must include `STUDENT`.
4. Open `https://online.play-and-say.ru/forgot-password` and request a code for the same email. The SPA must immediately render `/reset-password?email=...` without a reload; Back/Forward must preserve public routing. The received localized email must contain the same reset-form link without the code in its URL. Enter the code and new password in that form.
5. Verify the reset code is one-time, expires after 15 minutes, and repeated bad attempts stop after 5 tries.
6. In received emails, SPF/DKIM/DMARC should pass and sender should be `no-reply@play-and-say.ru`.

Managed-student invite smoke:

1. Sign in as `teacher-demo`, create a managed student from the schedule participant picker, create a lesson with that student, then use the lesson copy-links action.
2. Open the returned `/join#ABC123` style link in a clean browser context. The fragment is a 6-character manual-entry invite code and must not be sent as a `?token=` query parameter; the SPA must read and clear it, call `/api/student-invites/consume`, store the returned Keycloak token set, and redirect to `/lessons/{lessonId}/classroom` without showing the Keycloak login form.
3. Reopen the same invite link in another clean context; it must fail as already consumed or invalid.

### Schedule reschedule and classroom/email smoke

Run this after `api-gateway`, `email-service`, and `web-app` have all rolled out. Use the existing `teacher-demo` and `student-demo` browser profiles; do not repair lesson state with SQL.

1. As `teacher-demo`, create or open a lesson more than 10 minutes in the future. The card and header must say it is planned, must not show a live/join action, and the preparation page must show the exact access-opening time while still allowing material preparation.
2. Open `/lessons/{lessonId}/classroom` directly. The SPA must return to the schedule with a localized explanation; the API `/start` must return localized `409` for the owning teacher, while an unrelated user still sees `404`.
3. From the lesson card menu choose the localized “change date and time” action. Confirm the dialog shows the assigned students and, for a recurring lesson, says only the selected occurrence changes. Save an actually different future time.
4. Confirm the card changes immediately, the other occurrences remain unchanged, and the open classroom (if one was deliberately prepared inside the window before a second transfer) closes with the reschedule explanation.
5. Confirm one `LESSON_RESCHEDULED` queue row per assigned student and rebuilt `LESSON_START_30M` rows. A student without email must become `SKIPPED`; a provider failure must become `FAILED` without reverting the lesson time. A second transfer before dispatch must cancel the older unsent reschedule row.
6. Confirm the received `lesson-rescheduled` message is in the recipient locale and contains the lesson title, old and new local times, teacher, and lesson link. Check `email-service` logs for the delivery outcome without printing provider credentials.
7. Enter a lesson during `start - 10m .. end + 10m` in Chromium and WebKit as teacher and student. After pre-join, both participants must remain connected; outside the window neither role receives a LiveKit token.

Read-only queue verification on the VPS (replace the UUID, do not paste credentials):

```bash
KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n playsay-data exec playsay-postgres-1 -c postgres -- \
  psql -d playsay -c "select reminder_type, recipient_role, status, due_at, previous_scheduled_start, previous_scheduled_end, scheduled_start_snapshot, scheduled_end_snapshot from lesson_email_reminder where lesson_id = '<lesson-uuid>' order by created_at;"
KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n playsay-dev logs deploy/email-service --since=15m | grep -E 'lesson-rescheduled|delivery|provider'
```

For the known lesson `19.07.2026 10:00–10:45 Europe/Moscow`, saving the same time through this dialog is the supported repair for an erroneous early `IN_PROGRESS`: expect `SCHEDULED`, cleared actual timestamps, and rebuilt start reminders, but no `LESSON_RESCHEDULED` email because the time did not actually change. Verify email delivery with an actual reschedule of a disposable smoke lesson instead.

### Chat delivery and offline email smoke

Deploy in the order `email-service` (template migration), `api-gateway` (chat migration/queue), then `web-app`. The current presence contract assumes one `api-gateway` replica; do not scale it horizontally until chat presence is moved to a shared broker.

1. Open the same teacher/student dialog in two authenticated browser profiles. A new outgoing message must move from one grey check after REST save to two grey checks after delivery and two orange checks after the recipient opens the dialog.
2. Close every Play&Say tab for the recipient, send several short messages within two minutes, and confirm only one `chat_email_digest` row remains `PENDING` with all message links.
3. Confirm one localized `chat-unread-digest` email arrives after the two-minute grace period. It must show the message count and sender name, contain no message body, and open `/?chat=<conversationId>` or `/?chat=open`.
4. Send more messages after the first email. No second email may be sent before `sent_at + 10 minutes`; without new messages there must be no repeat at all.
5. Repeat with the recipient returning online or reading before `due_at`: the digest becomes `SKIPPED`. A recipient without email is also `SKIPPED`; provider errors retry with the configured 1/5/15-minute backoff and eventually become `FAILED` without losing chat messages.

Read-only queue verification on the VPS:

```bash
KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n playsay-data exec playsay-postgres-1 -c postgres -- \
  psql -d playsay -c "select recipient_user_id, status, attempts, due_at, sent_at, created_at from chat_email_digest order by created_at desc limit 20;"
KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n playsay-dev logs deploy/api-gateway --since=20m | grep -E 'chat digest email failed'
KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n playsay-dev logs deploy/email-service --since=20m | grep -E 'chat-unread-digest|delivery|provider'
```

## YouTube RF Relay

The product has a risk-flagged YouTube relay path for authorized Play&Say material video blocks. It is disabled by default and must stay disabled unless the business explicitly accepts the current risk profile.

Runtime controls in the `api-gateway` chart:

- `PLAYSAY_YOUTUBE_RF_RELAY_ENABLED`: must be `"true"` to allow relay decisions. Default is `"false"`.
- `PLAYSAY_YOUTUBE_RF_RELAY_GEO_COUNTRY_HEADER`: trusted reverse-proxy header used as IP geolocation country, for example `X-PlaySay-Geo-Country`.
- `PLAYSAY_YOUTUBE_RF_RELAY_REQUIRE_GEO_COUNTRY`: must stay `"true"` outside temporary dev testing. When `"false"`, the backend skips the trusted IP country header requirement but still requires an authenticated `countryCode=RU` app profile and all material/video policy checks.
- `PLAYSAY_MEDIA_SERVICE_BASE_URL`: internal ClusterIP URL, default `http://media-service.playsay-dev.svc.cluster.local`.
- `PLAYSAY_MEDIA_SERVICE_TOKEN`: shared secret used only for gateway -> media-service internal endpoints; created by `scripts/sync-media-secret.sh` as Kubernetes secret `playsay-media`.

Runtime controls in the `media-service` chart:

- `PLAYSAY_MEDIA_SERVICE_TOKEN`: same shared secret; required for `/internal/youtube/*`.
- `PLAYSAY_MEDIA_SERVICE_SESSION_TTL_SECONDS`: short-lived playback session TTL, default `900`.
- `PLAYSAY_MEDIA_SERVICE_MAX_UPSTREAM_RANGE_BYTES`: maximum upstream Range window for relay stream requests, default `1048576`.
- `PLAYSAY_MEDIA_SERVICE_MAX_THUMBNAIL_BYTES`: thumbnail download cap, default `5242880`.
- `PLAYSAY_MEDIA_SERVICE_YTDLP_PATH`: executable used by `media-service` for YouTube metadata, format selection, thumbnail source URL, and upstream media URLs; default `/usr/local/bin/yt-dlp`.
- `PLAYSAY_MEDIA_SERVICE_YTDLP_PLUGIN_DIRECTORY`: yt-dlp plugin search root; the pinned standalone binary requires `/usr/local/lib`, which contains `yt-dlp-plugins/yt_dlp_plugins`.
- `PLAYSAY_MEDIA_SERVICE_YTDLP_JS_RUNTIME`: JS challenge runtime; the pinned image uses `deno:/usr/local/bin/deno`.
- `PLAYSAY_YOUTUBE_POT_ENABLED`: dev-only switch for automatic YouTube PO Token support; default `false`.
- `PLAYSAY_YOUTUBE_POT_PROVIDER_BASE_URL`: loopback-only bgutil sidecar endpoint, default `http://127.0.0.1:4416`.
- `PLAYSAY_YOUTUBE_POT_ALLOWED_VIDEO_IDS`: comma-separated spike allowlist; keep empty outside the controlled dev experiment.
- `PLAYSAY_YOUTUBE_POT_PLAYER_CLIENTS`: yt-dlp player client list for allowlisted videos; spike default `mweb`.
- `PLAYSAY_YOUTUBE_POT_SLEEP_REQUESTS_SECONDS`: bounded delay between yt-dlp YouTube requests; spike default `1`.
- `PLAYSAY_MEDIA_SERVICE_FFMPEG_PATH`: pinned static ffmpeg used to merge separate MP4/M4A streams; default `/usr/local/bin/ffmpeg`.
- `PLAYSAY_YOUTUBE_CACHE_ENABLED`: independent cache feature flag, default `false`; it must have the same value in `api-gateway` and `media-service`.
- `PLAYSAY_MEDIA_SERVICE_CACHE_DOWNLOAD_TIMEOUT_SECONDS`: full download/merge timeout, default `600`.
- `PLAYSAY_MEDIA_SERVICE_CACHE_MAX_VIDEO_BYTES`: final MP4 cap, default `262144000` (250 MiB).
- `PLAYSAY_MEDIA_SERVICE_CACHE_TEMP_DIRECTORY`: disk-backed working directory, mounted as a size-limited `emptyDir`, default `/tmp/playsay-media-cache` with `1Gi` limit.

Relay eligibility is strict: the authenticated app profile must have `countryCode=RU`, the trusted IP country header must be `RU`, the user must already have normal Play&Say access to the material, the block must be a YouTube `videoEmbed`, and effective video metadata must show duration `<= 420` seconds and English language. If stored `videoMeta` is missing or incomplete, `api-gateway` calls the internal `media-service` metadata endpoint by parsed YouTube `videoId` before the policy check. If that lookup fails or returns incomplete metadata, playback stays fail-closed as `NEEDS_REVIEW/YOUTUBE_METADATA_MISSING` and no relay session is created. If profile country and IP country conflict, relay is not used and the frontend falls back to the official YouTube embed decision.

### Dev-only YouTube PO Token spike

The current pinned media image contains `yt-dlp 2026.07.04`, Deno `2.6.9`, bundled `yt_dlp_ejs`, and `bgutil-ytdlp-pot-provider 1.3.1`. The Helm chart can add the provider as a same-pod sidecar bound only to port `4416`; no Service or ingress exposes it. The media container calls it over `127.0.0.1`, and no account cookies or manually copied PO tokens are stored. The dev values enable the experiment only for the explicit test allowlist; every other video keeps the existing extractor path.

Verify the runtime before testing:

```bash
kubectl -n playsay-dev exec deploy/media-service -c media-service -- /usr/local/bin/yt-dlp -v --simulate 'https://www.youtube.com/watch?v=9r4D-D18f_g' 2>&1 \
  | grep -E 'yt-dlp version|Optional libraries|JS runtimes|Plugin directories|PO Token Providers'
kubectl -n playsay-dev get pod -l app.kubernetes.io/name=media-service \
  -o custom-columns=NAME:.metadata.name,READY:.status.containerStatuses[*].ready,RESTARTS:.status.containerStatuses[*].restartCount
```

Expected verbose signals for an allowlisted video are Deno under `JS runtimes`, the configured plugin directory, and a `bgutil:http` PO Token provider. Application logs may contain `potEnabled=true` and one of the bounded `failureKind` values (`EMBED_DISABLED`, `BOT_CHECK`, `PO_TOKEN_REQUIRED`, `RATE_LIMITED`, `FORMAT_UNAVAILABLE`, `PRIVATE_VIDEO`, `VIDEO_UNAVAILABLE`, `UNKNOWN`), but must not contain a token, visitor data, cookies, or extracted upstream URLs.

The spike matrix is `WX8HmogNyCY`, `8ChQVaEAKsk`, `BwHMMZQGFoM`, and `OsuWvoBWOnA`; `FkL8j0wIRf8` is diagnostic-only because YouTube may have removed it, and `9r4D-D18f_g` remains the non-kids control. Success requires metadata plus live relay and `MEDIUM` MinIO cache Range playback for at least three of the four matrix videos. Use temporary materials/references, archive them after evidence is captured, delete the test cache objects through the authenticated internal DELETE endpoint, and confirm two non-overlapping requests return `206` with correct `Content-Range`.

Dev acceptance on 2026-07-20 met the threshold: `WX8HmogNyCY`, `8ChQVaEAKsk`, and `OsuWvoBWOnA` passed English metadata, relay Range playback, and cached Range playback; `BwHMMZQGFoM` was transport-successful but correctly rejected by the product language policy because YouTube reports `id`. The teacher material UI also played `OsuWvoBWOnA` through the Play&Say video element even though normal owner embed is disabled (`paused=false`, `readyState=4`, timeline advanced, 720p). The first concurrent relay/cache attempt OOM-killed the main container at `896Mi`; dev therefore reserves `1280Mi` for the main container and caps JVM RAM percentages at `20/35`, leaving headroom for `yt-dlp` and `ffmpeg`. Treat a new OOM/restart during the same concurrency test as a regression.

Rollback is to set `youtubePot.enabled=false` in `values-dev.yaml` and sync ArgoCD; this removes the sidecar and makes all yt-dlp calls ignore the provider arguments. Do not delete unrelated cache objects, stop Docker/k3s/Amnezia, or change the public-site nginx configuration.

The `api-gateway` owns material authorization, policy decisions, `material_asset` rows, durable YouTube cache jobs, and material-to-cache references. The `media-service` owns `yt-dlp`, pinned static `ffmpeg`, in-memory playback sessions, quality selection, thumbnail/video bytes upload to MinIO/S3, and Range/chunked streaming. Gateway reserves/reuses a `VIDEO_THUMBNAIL` asset with provider `YOUTUBE` and metadata `{ blockId, videoId, sourceThumbnailUrl }`; if thumbnail storage fails, playback must continue and only a safe warning should be logged. Public video bytes do not pass back through gateway: playback responses return `relayUrl=/api/media/video-playback-sessions/{sessionId}/stream`, and the web-app nginx maps that path to `media-service`.

When the backend returns `BLOCKED` or `NEEDS_REVIEW` for an authorized material playback request, the web-app must show a local Play&Say unavailable state with the backend `mode/reason` instead of silently falling back to a YouTube iframe. This is intentional for RF relay testing: missing metadata, duration/language policy failures, or server decision errors must be visible without requiring the student's browser to resolve YouTube domains.

The RF relay frontend uses a custom Play&Say HTML5 player. `VIDEO_PLAYBACK_LOADING` is a neutral pending state, not an unavailable error. Before the learner presses Play, the relay `<video>` must keep `preload="none"` and must not attach the stream `src`; before that point there should be no `media-service stream response` log lines. The stream `src` must be attached imperatively from the user click handler, not rendered by React as a normal `src` prop, so the browser does not interrupt the first `play()` with a second load. After Play, the first click sets `src`, seeks to the clip start, calls `play`, retries a transient interrupted first `play()` while metadata is preparing, then normal browser Range requests may be large and may buffer client-side. The playback source is fixed when the short-lived session is created: an active relay session is never switched to a newly ready cache object.

The media stream service also bounds upstream range windows to reduce full-file upstream requests. Browser requests like `Range: bytes=0-` are forwarded upstream as a finite range capped by `PLAYSAY_MEDIA_SERVICE_MAX_UPSTREAM_RANGE_BYTES` (default `1048576` bytes), oversized explicit ranges are capped to the same window, and missing Range headers synthesize an initial bounded range. In `media-service stream response` logs compare `rangeHeader`, `upstreamRangeHeader`, and `rangeLimited=true|false`; a healthy first request should normally show `status=206`, `rangeLimited=true`, and a finite `contentRange`.

`api-gateway` logs playback decisions with material/block/session/video IDs, but must not log raw YouTube query values such as `si` or any extracted media URL. `media-service` logs metadata/session/stream/cache diagnostics with video ID, state, selected quality/height, byte size, attempt, and duration, but must not log upstream media URLs. The stream endpoint is `GET` permit-all because native HTML5 video requests cannot attach the SPA bearer token; the unguessable playback session id is the short-lived capability token, and unknown/expired sessions return `404`. Arbitrary upstream URLs remain forbidden. The only permitted video-byte cache is the controlled private object described below.

### YouTube MinIO cache

Saving a new or changed non-archived material reconciles every YouTube `videoEmbed` block in the same database transaction. References are unique by material/block and point to one shared `videoId + MEDIUM` cache row, so two materials never create two objects. Saving the material is not coupled to download success. Archiving removes its references. On startup, an idempotent reconciliation scans existing active materials once.

The single-thread gateway worker polls every 5 seconds and uses a 15-minute lease. Jobs move through `PENDING`, `IN_PROGRESS`, `READY`, `RETRY`, or `REJECTED`. An expired lease is claimable after a worker restart. Transient failures retry after 1, 5, and 30 minutes, then every 6 hours while at least one reference remains. The worker rejects metadata outside the existing English and `<=420s` policy before download. An oversized final file is also rejected; unavailable or transient download/storage failures never block material save or playback.

`media-service` implements idempotent `POST /internal/youtube/video-cache` and `DELETE /internal/youtube/video-cache/{videoId}?quality=MEDIUM` under the existing `X-PlaySay-Media-Service-Token`. It downloads the best compatible MP4 up to 720p without upscale; split video/audio streams are merged with the pinned static ffmpeg in the image. The final object is `youtube-cache/v1/{videoId}/medium.mp4`. Download uses the 1 GiB `emptyDir`, has a 10-minute timeout and 250 MiB final-file limit, then uploads from the file path so the JVM never retains the full movie.

For a new `MEDIUM` playback session, `media-service` validates the object with HEAD before selecting `MINIO_CACHE`; `LOW` and `HIGH` always use `YOUTUBE_RELAY`. The same short-lived public stream URL serves both sources. MinIO remains private, Range GET is bounded, and a missing/invalid cache automatically falls back to a freshly resolved relay stream. Playback responses expose `deliverySource=MINIO_CACHE|YOUTUBE_RELAY` and the gateway cache state. Objects with no references are retained for 30 days, then the daily cleanup calls media-service DELETE; a deletion error keeps the database row for the next attempt.

Monitor these Prometheus metrics: `playsay_youtube_cache_lookups_total`, `playsay_youtube_cache_streams_total`, `playsay_youtube_cache_downloads_total`, `playsay_youtube_cache_download_duration_seconds`, `playsay_youtube_cache_jobs_total`, `playsay_youtube_cache_job_duration_seconds`, and `playsay_youtube_cache_bytes`. Both backend images include the Prometheus Micrometer registry and expose `/actuator/prometheus`; the gateway security policy permits this scrape endpoint without a bearer token. `monitoring-lite` vmagent scrapes the cluster-internal `api-gateway` and `media-service` services every 30 seconds. Because active references have no TTL, alert on MinIO capacity and the total-ready-bytes gauge; the current dev MinIO PVC must not be treated as unlimited.

Safe rollout order:

1. Deploy the `api-gateway` migration/API with `video.youtube.cache.enabled="false"`; verify the new tables and gateway readiness.
2. Deploy the `media-service` image with yt-dlp, `/usr/local/bin/ffmpeg`, S3 access, and the 1 GiB temp volume, still with cache disabled.
3. Set `video.youtube.cache.enabled="true"` in the api-gateway dev values and `mediaService.youtubeCacheEnabled="true"` in media-service dev values, push `playsay-infra/develop`, and wait for both ArgoCD applications to become `Synced/Healthy`.
4. Save a policy-eligible YouTube block, confirm one cache row reaches `READY`, verify the MinIO key and a `MEDIUM` playback response with `deliverySource=MINIO_CACHE`, then request two ranges and expect `206` with correct `Content-Range`. Confirm `LOW`/`HIGH` return `YOUTUBE_RELAY`.
5. Check the corresponding Jenkins module builds and the final image tags recorded by ArgoCD before calling the rollout complete.

Fast cache rollback is non-destructive: set both cache flags to `"false"`, push `playsay-infra/develop`, and wait for the gateway and media-service rollouts. New sessions immediately use the existing tunnel; `READY` objects and rows remain available for a later re-enable. Do not delete MinIO objects during feature rollback. If the media-service image itself must be rolled back, disable the gateway flag first so no long internal download calls are started against the older service.

Useful RF relay log checks:

```bash
kubectl -n playsay-dev logs deploy/api-gateway --since=30m | grep 'YouTube RF relay playback decision'
kubectl -n playsay-dev logs deploy/api-gateway --since=30m | grep 'YouTube RF relay thumbnail'
kubectl -n playsay-dev logs deploy/media-service --since=30m | grep 'media-service yt-dlp'
kubectl -n playsay-dev logs deploy/media-service --since=30m | grep 'media-service stream response'
```

For a `YOUTUBE_METADATA_MISSING` report, expect fields like `urlKind=SHORT`, parsed `videoId=<id>`, and `videoMetaPresent=false` or `durationPresent=false` / `languagePresent=false`. On successful media-service recovery, expect `media-service yt-dlp resolved metadata ... durationSeconds=<n> language=en` followed by a gateway playback decision with `metadataSource=MEDIA_SERVICE_ON_DEMAND`, `effectiveDurationSeconds=<n>`, `effectiveLanguage=en`, and `mode=RF_RELAY`. If the custom Play&Say poster is visible and there are no `media-service stream response` lines before Play, that is expected. If the poster is clicked and relay starts streaming, check stream lines for upstream `status`, `contentType`, `contentLength`, `contentRange`, `acceptRanges`, `selectedQuality`, `selectedHeight`, and `rangeHeader`. If playback shows a black panel after Play but there are no stream response lines, verify that `GET /api/media/video-playback-sessions/<sessionId>/stream` reaches `media-service` and that proxy buffering is disabled.

Video relay streaming needs buffering disabled on both proxy layers. The web-app container nginx has a specific `/api/media/video-playback-sessions/` location before generic `/api/`, rewrites `/api/media/...` to `media-service`, and disables `proxy_buffering` / `proxy_request_buffering`. Host nginx must include the same specific `/api/media/video-playback-sessions/` location under `online.play-and-say.ru` with buffering off and long `proxy_read_timeout` / `proxy_send_timeout` values. After changing the host nginx generator on an existing VPS, re-render or manually verify `/etc/nginx/conf.d/playsay-k8s-dev.conf`, then run `nginx -t` and reload nginx without stopping Docker, k3s, or Amnezia.

Temporary dev test mode on 2026-06-03 enables `video.youtube.rfRelay.enabled: "true"` and `video.youtube.rfRelay.requireGeoCountry: "false"` in `values-dev.yaml` so the user can manually verify lesson playback before host nginx geolocation is wired. Do not carry this bypass into production-like environments; rollback by setting `enabled: "false"` or at least `requireGeoCountry: "true"`.

Do not trust a client-supplied geolocation header directly. Host nginx or another trusted edge proxy must strip any inbound `X-PlaySay-Geo-Country` header from the public request and set its own value before proxying to `web-app`/`api-gateway`. Outside the temporary dev test bypass above, keep `PLAYSAY_YOUTUBE_RF_RELAY_ENABLED=false` until that edge geolocation is configured and verified.

Fast rollback: set `helm-charts/api-gateway/values-dev.yaml` `video.youtube.rfRelay.enabled` back to `"false"`, commit to `playsay-infra`, push `develop`, and let ArgoCD roll out the disabled value. The relay stream endpoint accepts only short-lived playback session IDs; it must never be changed to accept arbitrary YouTube URLs. Logs must not include extracted upstream media URLs or secret values.

## Lightweight Monitoring

Dev monitoring uses a lightweight VictoriaMetrics GitOps app instead of full `kube-prometheus-stack`, because the current dev VPS has `4 vCPU / 8 GB RAM` and Jenkins + Keycloak + PostgreSQL + LiveKit already consume a meaningful baseline. The ArgoCD app is `monitoring-lite`, deployed to namespace `monitoring` from `helm-charts/monitoring-lite`.

Components:

- `victoria-metrics`: single-node time series storage, retention `3d`, PVC `5Gi`;
- `vmagent`: Prometheus-compatible scraper and remote writer to VictoriaMetrics;
- `kube-state-metrics`: pod/deployment/restart/readiness metadata;
- `blackbox-exporter`: HTTP probes for public Play&Say endpoints;
- `vmalert`: evaluates alert rules against VictoriaMetrics;
- `alertmanager`: routes alerts to Telegram if Telegram secret exists.

The Ansible-managed host `prometheus-node-exporter` remains bound to `127.0.0.1:9100`. Do not deploy a second node-exporter DaemonSet on the dev VPS. `vmagent` runs with `hostNetwork: true` and scrapes the existing host exporter through localhost. Its own HTTP listener is bound to `127.0.0.1` inside host networking and is not exposed publicly.

LiveKit metrics are enabled in the `livekit` chart with `prometheus_port: 6789`; vmagent scrapes `livekit.livekit.svc.cluster.local:6789`.

Blackbox probes cover `online.play-and-say.ru`, `key.play-and-say.ru`, ArgoCD, VictoriaMetrics UI, and Jenkins login. The Jenkins probe must target `https://ops.play-and-say.ru:18443/jenkins/login`, not `/jenkins/`, because unauthenticated `/jenkins/` is expected to return `403 Forbidden` on a healthy controller.

Expected extra steady-state footprint is roughly `300-600Mi` RAM, depending on series count and scrape load. If memory pressure appears during Jenkins builds or group video tests, first reduce `monitoring-lite` retention/scrape targets before increasing VPS size.

Telegram alerts are optional at boot. Alertmanager starts with a null receiver when the secret is missing, so ArgoCD remains healthy. During the 2026-06-27 resource incident this meant active alerts were visible in Alertmanager/VMUI but were not delivered externally. To enable Telegram notifications, create the secret manually without printing values:

```bash
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
read -rsp "Telegram bot token: " TELEGRAM_BOT_TOKEN; echo
read -rp "Telegram chat id: " TELEGRAM_CHAT_ID
kubectl -n monitoring create secret generic playsay-telegram-alerts \
  --from-literal=bot-token="$TELEGRAM_BOT_TOKEN" \
  --from-literal=chat-id="$TELEGRAM_CHAT_ID" \
  --dry-run=client -o yaml | kubectl apply -f -
unset TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID
kubectl -n monitoring rollout restart deployment/monitoring-lite-alertmanager
kubectl -n monitoring get secret playsay-telegram-alerts
kubectl -n monitoring rollout status deployment/monitoring-lite-alertmanager
```

Check monitoring state:

```bash
kubectl -n argocd get application monitoring-lite
kubectl -n monitoring get pods
kubectl -n monitoring top pods
```

Access VictoriaMetrics UI through the ops host:

```bash
curl -k -I https://ops.play-and-say.ru:18443/victoria-metrics/vmui/
```

Then open `https://ops.play-and-say.ru:18443/victoria-metrics/vmui/`.

The short `/vmui/` path redirects to `/victoria-metrics/vmui/`. The upstream is the localhost-only NodePort `127.0.0.1:32085`, backed by service `monitoring-lite-victoria-metrics`; direct public NodePort access must stay blocked by the k3s/host nginx coexist setup. Host nginx denies VictoriaMetrics admin/service endpoints under `/victoria-metrics/api/v1/admin`, `/debug`, `/flags`, and `/metrics`. Before staging/prod, protect VMUI with VPN/allowlist or shared ops auth.

Local port-forward remains useful if host nginx is being repaired:

```bash
kubectl -n monitoring port-forward svc/monitoring-lite-victoria-metrics 8428:8428
```

Then open `http://127.0.0.1:8428/victoria-metrics/vmui/`.

Useful smoke queries in VMUI:

```text
up
node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes
probe_success
kube_pod_container_status_restarts_total
```

### Cross-network classroom performance gate

The 2026-07-19 13:30–13:45 Europe/Moscow incident was not CPU or NIC saturation: host CPU stayed below 23% and traffic below 1 MiB/s, but available memory fell to `0.51–0.63 GiB`, swap and major page faults were active, and IO pressure reached about 7%. In the same two-party LiveKit room, RTT reached about `695 ms`, jitter `85 ms`, packet loss `4.6%`, NACK bursts hundreds per second, and logs contained multi-second clock-skew/DTLS reconnects. Treat browser main-thread pressure, collaboration WebSocket volume, host memory pressure, and the independent LiveKit media path as separate signals.

After changes to classroom realtime, LiveKit, TURN, or host capacity, repeat a 30-minute teacher/student run from different networks with camera/microphone, continuous drawing, and at least three shared HTML-game open/close cycles. Capture VictoriaMetrics and LiveKit metrics for that exact interval and accept the current 8 GiB node only when:

- drawing and game actions do not reset and do not cause visible media freezes longer than one second;
- there are no DTLS reconnects or multi-second media clock-skew entries;
- LiveKit RTT p95 is below `300 ms`, packet loss below `2%`, jitter p95 below `50 ms`, and NACK rate is not sustained above `50/s`;
- `node_memory_MemAvailable_bytes` remains at least `1 GiB`, with no sustained swap-in/out or major page faults;
- a 1000-point stroke produces incremental, linear Yjs traffic below `250 KiB`, and unchanged HTML-game DOM is not republished.

First fix application/TURN behavior and rerun this gate on the existing 8 GiB VPS. If memory or media criteria still fail while CPU and network throughput remain below saturation, upgrade the dev VPS to 16 GiB and repeat the same interval. Do not stop Docker, Amnezia, nginx, k3s, the public root site, or unrelated workloads during measurement or upgrade preparation.

## Post-Install Verification

Check the public site still works:

```bash
curl -I https://play-and-say.ru
```

Expected: `HTTP/1.1 200 OK`.

Check cluster health:

```bash
ssh root@89.124.113.223 "kubectl get nodes -o wide && kubectl get pods -A"
```

Expected:

- node status is `Ready`;
- ArgoCD pods are `Running`;
- Headlamp pod is `Running`;
- Jenkins pod is `2/2 Running`;
- Sealed Secrets pod is `Running`;
- kube-system pods are `Running`.

Check ops UI before DNS exists by forcing local resolution:

```bash
curl -k -I --resolve ops.play-and-say.ru:18443:89.124.113.223 https://ops.play-and-say.ru:18443/headlamp/
curl -k -I --resolve ops.play-and-say.ru:18443:89.124.113.223 https://ops.play-and-say.ru:18443/argocd/
curl -k -I --resolve ops.play-and-say.ru:18443:89.124.113.223 https://ops.play-and-say.ru:18443/jenkins/login
curl -k -I --resolve ops.play-and-say.ru:18443:89.124.113.223 https://ops.play-and-say.ru:18443/keycloak/
curl -k -I --resolve ops.play-and-say.ru:18443:89.124.113.223 https://ops.play-and-say.ru:18443/victoria-metrics/vmui/
curl -k -I --resolve online.play-and-say.ru:443:89.124.113.223 https://online.play-and-say.ru/
```

Expected:

- Headlamp: `200 OK`;
- ArgoCD: `200 OK`;
- Jenkins: `403 Forbidden` or login redirect, which means Jenkins is alive and requires authentication.
- Keycloak: `200 OK` or a redirect/login response, which means Keycloak is alive behind nginx.
- VictoriaMetrics VMUI: `200 OK`.
- Online SPA: `200 OK`.

Check existing services:

```bash
ssh root@89.124.113.223 "docker ps --format '{{.Names}} {{.Ports}}' && systemctl is-active nginx k3s docker && nginx -t"
```

Expected: Amnezia containers are present, nginx/k3s/docker are active, nginx syntax is successful.

Check public port hardening:

```bash
nc -vz -w 5 89.124.113.223 18443
nc -vz -w 5 89.124.113.223 6443
nc -vz -w 5 89.124.113.223 10250
nc -vz -w 5 89.124.113.223 9100
```

Expected: `18443` succeeds; `6443` and `10250` time out; `9100` is refused or timed out.

Known incomplete item after first bootstrap: ArgoCD root app stays `Unknown` until `https://github.com/mednov-ai/playsay-infra.git` exists, contains the pushed infra repository, and ArgoCD can read it.

## GitHub and Jenkins Credentials

Never paste GitHub tokens into chat, commits, shell history, or documentation. If a token is exposed, revoke it in GitHub immediately and create a new one.

Create these GitHub items before configuring Jenkins:

1. GitHub organization or account namespace: `mednov-ai`.
2. Repositories:
   - `playsay-platform`
   - `playsay-infra`
3. Push local folders to those repositories.
Create a GitHub token for Jenkins. The simplest MVP option is one fine-grained token with access to `playsay-platform` and `playsay-infra`:

- Repository contents: read/write
- Pull requests: read
- Metadata: read
- Webhooks: read/write if Jenkins should create webhooks automatically
- Packages: read/write for GHCR

In Jenkins, create credentials:

- `github-ghcr`: username/password credential. Username is your GitHub username or org bot user; password is the GitHub token with package write access.
- `github-infra-token`: username/password credential. Username is your GitHub username or org bot user; password is the GitHub token that can push commits and tags to `playsay-infra` and create tags in `playsay-platform`.

You may use one token for both credentials at MVP stage. Later, split them into narrower tokens.

Create credentials in Jenkins UI:

1. Open `https://ops.play-and-say.ru:18443/jenkins/`.
2. Go to `Manage Jenkins` -> `Credentials` -> `System` -> `Global credentials`.
3. Add `Username with password`.
4. For `ID`, enter `github-ghcr`; username is your GitHub username, password is the GitHub token.
5. Add the second `Username with password` credential with ID `github-infra-token`.

Do not store the token in `playsay-infra` or `playsay-platform`.

If you prefer CLI later, pass secrets only through a local untracked file such as `.env.local` or an interactive prompt.

## Jenkins Branch Builds and Build Labels

Jenkins platform jobs are configured by:

```bash
./scripts/configure-jenkins-jobs.sh
```

The bootstrap/add-ons script runs it automatically after Jenkins is installed. The configured jobs are:

- `playsay-platform-dispatch-develop`: lightweight Generic Webhook Trigger receiver for `develop` and `release/*`;
- `playsay-platform-develop`: manual full core rebuild compatibility job; the dispatcher does not call it;
- `playsay-api-gateway-develop`: tests/packages `api-gateway`, checks OpenAPI, runs owned app DB migrations when changelogs changed, builds/pushes image, updates only `helm-charts/api-gateway/values-dev.yaml`, waits for rollout;
- `playsay-ai-tutor-service-develop`: tests/packages `ai-tutor-service`, runs its app DB Liquibase changelog when changed, builds/pushes `playsay-ai-tutor-service`, updates only `helm-charts/ai-tutor-service/values-dev.yaml`, waits for rollout;
- `playsay-vocabulary-service-develop`: tests/packages `vocabulary-service`, applies its Liquibase changelog, builds/pushes `playsay-vocabulary-service`, updates only `helm-charts/vocabulary-service/values-dev.yaml`, waits for rollout;
- `playsay-web-app-develop`: generates the API client, lints/tests/builds `web-app`, builds/pushes image, updates only `helm-charts/web-app/values-dev.yaml`, waits for rollout, then runs Sprint 5/Sprint 6 browser smoke;
- `playsay-collaboration-service-develop`: tests/builds `collaboration-service`, builds/pushes image, updates only `helm-charts/collaboration-service/values-dev.yaml`, waits for rollout;
- `playsay-media-service-develop`: tests/packages `media-service`, builds/pushes image, updates only `helm-charts/media-service/values-dev.yaml`, waits for rollout;
- `playsay-payment-service-develop`: tests/packages `payment-service`, runs owned app DB migrations when changelogs changed, builds/pushes image, updates only `helm-charts/payment-service/values-dev.yaml`, waits for rollout;
- `playsay-registration-service-develop`: tests/packages `registration-service`, runs owned app DB migrations when changelogs changed, builds/pushes image, updates only `helm-charts/registration-service/values-dev.yaml`, waits for rollout;
- `playsay-email-service-develop`: tests/packages `email-service`, runs owned app DB migrations when changelogs changed, builds/pushes image, updates only `helm-charts/email-service/values-dev.yaml`, waits for rollout;
- `playsay-keyboard-backend-develop`: downstream keyboard backend job;
- `playsay-keyboard-frontend-develop`: downstream keyboard frontend job.

The dispatcher has `BRANCH_NAME`, `GITHUB_BEFORE`, `GITHUB_AFTER`, optional `FORCE_TARGETS=all|target1,target2`, and `MAX_PARALLEL_MODULE_JOBS` fixed to `1`. Its analysis stage uses a small temporary agent; the downstream stage has `agent none`, so global Kubernetes cloud `containerCap=1` does not deadlock while the dispatcher waits. Module jobs are manual/dispatcher-only and do not have GitHub webhook triggers. All module jobs checkout `GITHUB_AFTER` when it is provided, so they build the same source commit the dispatcher analyzed. `playsay-platform-develop` stays available as a manual full rebuild safety valve with `AFFECTED_TARGETS=all`, but it is no longer part of automatic dispatch.

Module jobs have a `BRANCH_NAME` parameter and module-specific build label prefixes:

- `api-gateway`: `api-dev-N` on `develop`;
- `web-app`: `web-dev-N`;
- `collaboration-service`: `collab-dev-N`;
- `media-service`: `media-dev-N`;
- `payment-service`: `payment-dev-N`;
- `registration-service`: `registration-dev-N`;
- `email-service`: `email-dev-N`;
- `keyboard-service`: `key-backend-dev-N`;
- `keyboard-app`: `key-frontend-dev-N`.

Non-`develop` labels prefix the branch with the module name, for example `web-feature-task-1-N` or `api-rel-1.001.00-N`, sanitized for Docker/Git/Kubernetes label safety.

Deployable dev branches are `develop`, `codex/*`, `feature/*`, `release/*`, and `hotfix/*`. Other branches still run build/test stages but skip image publishing, source tagging, DB migrations, and dev image tag updates.

The dispatcher uses Generic Webhook Trigger to run automatically for GitHub push events on `develop` and `release/*`. It extracts `ref` into `BRANCH_NAME`, reads GitHub `before`/`after`, rejects `refs/tags/*`, and ignores branch deletion events where `after` is forty zeroes. It runs `scripts/ci/detect-affected-targets.mjs` over `GITHUB_BEFORE..GITHUB_AFTER`, starts only the needed downstream jobs sequentially, waits for all results, and marks the dispatcher build failed if any downstream job is not `SUCCESS`. Tag events are intentionally not used for module selection, because Jenkins creates build/deployment tags itself.

Affected-target policy:

- `frontend/keyboard-app/**` -> `playsay-keyboard-frontend-develop`;
- `backend/keyboard-service/**` -> `playsay-keyboard-backend-develop`;
- `frontend/web-app/**` -> `playsay-web-app-develop`;
- `backend/api-gateway/**` -> `playsay-api-gateway-develop`;
- `contracts/openapi.yaml` -> `playsay-api-gateway-develop` and `playsay-web-app-develop`;
- `backend/ai-tutor-service/**` or `contracts/ai-tutor-openapi.yaml` -> `playsay-ai-tutor-service-develop` and `playsay-web-app-develop`;
- `backend/vocabulary-service/**` or `contracts/vocabulary-openapi.yaml` -> `playsay-vocabulary-service-develop`, `playsay-web-app-develop`, and `playsay-keyboard-frontend-develop`;
- `contracts/registration-openapi.yaml` -> `playsay-registration-service-develop` and `playsay-web-app-develop`;
- `backend/media-service/**` -> `playsay-media-service-develop`;
- `backend/payment-service/**` -> `playsay-payment-service-develop`;
- `backend/registration-service/**` -> `playsay-registration-service-develop`;
- `backend/email-service/**` -> `playsay-email-service-develop`;
- `collaboration-service/**` -> `playsay-collaboration-service-develop`;
- shared backend config/code -> all backend targets including `keyboard-service`;
- shared frontend config/lockfile -> `web-app` and `keyboard-app`;
- CI/Jenkins/smoke scripts or unknown source paths -> fail-safe `all`;
- docs-only Markdown/docs/spec changes -> no downstream jobs.

Trigger `codex/*`, `feature/*`, and `hotfix/*` branches manually through the dispatcher with an explicit `BRANCH_NAME` and `FORCE_TARGETS` when a dev deploy of that branch is needed. `MAX_PARALLEL_MODULE_JOBS` must remain `1`; any other value fails before downstream dispatch. Trigger a module job directly only for recovery/debugging; Kubernetes cloud serialization and the same capacity guard still apply.

The build label is written to:

- Jenkins build display name;
- GHCR image tags for affected images: `playsay-api-gateway`, `playsay-web-app`, `playsay-collaboration-service`, `playsay-media-service`, `playsay-payment-service`, `playsay-registration-service`, `playsay-email-service`, `playsay-keyboard-service`, and `playsay-keyboard-app`;
- Git tags in `playsay-platform` and `playsay-infra`;
- Helm `values-dev.yaml` build metadata;
- Kubernetes pod labels and annotations under `playsay.io/*`.

Check what is deployed:

```bash
kubectl -n playsay-dev get pods --show-labels
kubectl -n playsay-dev get pod -l app.kubernetes.io/name=api-gateway -o jsonpath='{.items[0].metadata.annotations}'
```

Backend service image builds are intentionally runtime-only. Each backend module job runs only its own `:service:test` and `:service:bootJar`, then Kaniko builds the matching runtime Dockerfile by copying the already-built jar from that module's `build/libs`. Because these Kaniko builds use `backend/` as the Docker context, `backend/.dockerignore` must re-include every backend image's `build/libs/*.jar` path; otherwise an image can build and push without `/app/app.jar`. Only `playsay-media-service` adds the standalone `yt-dlp_linux` release asset to `/usr/local/bin/yt-dlp` and copies `/ffmpeg` from the pinned `mwader/static-ffmpeg:7.1.1` image into `/usr/local/bin/ffmpeg`; do not reintroduce `apt-get update`, Python installation, or a Gradle build stage unless the pipeline is redesigned.

Frontend image builds are intentionally runtime-only too. `playsay-web-app-develop` runs `npm --workspace web-app run generate/lint/test/build`, then Kaniko builds `frontend/web-app/Dockerfile` by copying the already-built `web-app/dist` into nginx. `playsay-keyboard-frontend-develop` does the same for `keyboard-app`. Do not add `npm install`, `npm ci`, or `npm run build` back into frontend Dockerfiles unless the pipeline is redesigned.

The `playsay-web-app-develop` Node container sets `NODE_OPTIONS=--max-old-space-size=1024` inside its `1536Mi` memory limit and requests `768Mi`. The Vite production bundle uses about `878Mi` Node heap plus `esbuild`/native overhead, so `1Gi` cgroup memory is insufficient; keep module parallelism at `1` on the dev VPS.

The `playsay-api-gateway-develop` Gradle container caps its daemon with `-Xmx384m -XX:MaxMetaspaceSize=256m` and uses a `2Gi` container limit. Its test stage passes `-PlowMemoryTests`, which keeps one test fork, uses a `512m` test heap and restarts the worker after every 8 classes so Spring/H2 context caches are released. Do not raise the container back to `3Gi` on the single-node VPS: an uncapped API test/package run can drive available host memory below 200Mi and cause cluster-wide swap thrash. Keep `--max-workers=1` and pass `-Pkotlin.compiler.execution.strategy=in-process`; the `-D` system-property form is not consumed by the Kotlin Gradle Plugin and starts a separate compiler daemon that can exhaust the dev node.

The `playsay-ai-tutor-service-develop` Gradle container follows the same bounded pattern: request `384Mi`, limit `1536Mi`, daemon `-Xmx384m / MaxMetaspaceSize=192m`, one `384m` test fork, `--max-workers=1`, and `-Pkotlin.compiler.execution.strategy=in-process`. Build `ai-tutor-dev-8` was aborted on 2026-07-13 after the former `3Gi`/`-D` configuration drove host load to about `15`, available memory below `500Mi`, and swap above `1.7Gi`. Keep AI Tutor builds serialized and do not restore the unbounded compiler daemon.

Jenkins Kubernetes cloud permits exactly one agent pod, enables orphan pod garbage collection with a 300-second timeout, and limits the injected `jnlp` container to `50m/128Mi` request and `300m/384Mi` limit. Module pods have `activeDeadlineSeconds=2400`, a 30-minute pipeline timeout, explicit resources for build/tools containers, and one-CPU Gradle/Node limits. Backend Gradle stages use `ActiveProcessorCount=1`, `--max-workers=1`, and the Kotlin compiler in-process. Gradle containers may share the `jenkins-agent-cache` PVC, but each Gradle-based pipeline must mount a job-specific subPath. Rollout waiting stays centralized in `scripts/ci/wait-for-argocd-rollout.sh` through the scoped `dev-kubeconfig` credential.

After Sprint 2 app PostgreSQL was added, Jenkins `dev-25` failed in `Backend tests` because Maven Central DNS resolution temporarily failed while the node was overloaded. During Sprint 4, Jenkins `dev-53` was `OOMKilled`. On 2026-06-27, parallel module builds caused OOMs and public outages. On 2026-07-16, even serialized API builds proved unsafe at the grown idle baseline: `api-dev-44` ran for 63 minutes, repeatedly lost its agent and ended with exit `137`; observed load1 reached `142.98`. The retry reached `MemAvailable=1.86%`, swap `1883Mi`, CPU about `100%`, I/O wait `57.97%`, and NodeNotReady.

AX41 Jenkins runs on the dedicated `playsay-ci` VM. The former shared-node capacity manager, watchdog, `capacity-guard` sidecars, state ConfigMap and Lease are removed and must not be recreated on dev, prod or CI. CI never scales product Deployments to obtain build capacity; the historical overload incidents above are retained only as the reason Jenkins was isolated.

Jenkins chart must keep `controller.overwritePlugins=true`. In chart `jenkins-5.9.22`, the rendered `apply_config.sh` can still contain interactive `yes n | cp -i ...` plugin copying; after a controller restart this can leave the init container in `CrashLoopBackOff` and Jenkins will serve `502` through host nginx because the service has no ready endpoints. `deploy-cluster-addons.sh` patches the Jenkins ConfigMap to use non-interactive `cp -f ...` after Helm upgrade and deletes `jenkins-0` only if it is already stuck in init `CrashLoopBackOff`. If `/jenkins/` returns `502` after a VPS reboot, check `kubectl -n jenkins get pod,endpoints` first; healthy Jenkins should be `2/2 Running`, have an endpoint, and return `403 Forbidden` or a login redirect through nginx.

Jenkins UI on the ops route is configured through Helm and JCasC. `deploy-cluster-addons.sh` installs the `dark-theme` plugin, sets `controller.jenkinsUrl=https://ops.play-and-say.ru:18443/jenkins/`, and loads `jenkins/jcasc/playsay-appearance.yaml`, which sets the global Jenkins theme to `dark` while leaving user theme overrides enabled. The host nginx `/jenkins/` proxy must forward `Host`, `X-Forwarded-Host`, `X-Forwarded-Port`, `X-Forwarded-Proto`, and `X-Forwarded-Prefix` so Jenkins reverse-proxy diagnostics see the public ops URL instead of the internal service URL.

The `OpenAPI contract` check lives in `playsay-api-gateway-develop`. Test, `bootJar`, and `:api-gateway:exportOpenApi` run in one Gradle invocation; the following stage only verifies the committed file and archives it. Internal `backend/api-gateway/**` changes trigger API only. A commit that changes `contracts/openapi.yaml` triggers API plus web-app, so frontend generation follows actual contract changes instead of every gateway implementation edit.

The app DB migrate stages live in the module jobs. Jenkins itself does not mount DB Secrets. Through the scoped dev kubeconfig it creates a short-lived `playsay-migrate-*` Job and `playsay-migration-*` ConfigMap in `playsay-dev`; only that Job may read an approved dev DB Secret. Admission policy fixes Liquibase `5.0.3`, PostgreSQL JDBC `42.7.8`, command, volumes, security context and allowed Secret keys. The Job has no service-account token, is time-bounded, and is deleted with its ConfigMap after completion. Changelog-aware modules skip only when `GITHUB_BEFORE..GITHUB_AFTER` proves no change; vocabulary still runs idempotent migration for every deployable build. Keep service startup Liquibase disabled.

The JPA services `api-gateway`, `payment-service`, `registration-service`, and `email-service` keep `logging.level.org.hibernate.orm.connections.pooling=warn` so normal startup logs do not print Hibernate's database-info block with the secret-bearing JDBC URI. Do not lower this logger to `info` while `PLAYSAY_DB_JDBC_URL` contains credentials.

The dev `api-gateway`, `media-service`, `payment-service`, `registration-service`, and `email-service` charts give Spring Boot memory headroom while keeping CPU scheduling pressure low on the single-node dev VPS: `api-gateway` requests `50m / 384Mi`, `media-service` requests `50m / 256Mi`, `registration-service` uses the aggressive dev profile `25m / 96Mi` requests, `500m / 384Mi` limits, and `JAVA_TOOL_OPTIONS` with `InitialRAMPercentage=25` plus `MaxRAMPercentage=55`. Lower-priority `payment-service` and `email-service` are tighter: `25m / 64Mi` requests, `500m / 320Mi` limits, and `JAVA_TOOL_OPTIONS` with `InitialRAMPercentage=15`, `MaxRAMPercentage=45`, `MaxMetaspaceSize=128m`, `ReservedCodeCacheSize=32m`, and `ActiveProcessorCount=1`. If any low-priority service is `OOMKilled`, raise only that service to `128Mi` request and `512Mi` limit before deeper investigation. Dev JPA services plus `keyboard-service` set `SPRING_DATASOURCE_HIKARI_MAXIMUM_POOL_SIZE=3`; app PostgreSQL currently has `max_connections=50`, so keeping runtime pools small leaves connection headroom for Jenkins Liquibase migrations and ad-hoc diagnostics. Their dev strategy is `RollingUpdate` with `maxSurge=0/maxUnavailable=1`, accepting a short backend replacement window in dev to avoid a Jenkins `Wait for dev rollout` deadlock where the agent pod waits for a rollout that cannot schedule until the agent exits; re-check node memory/swap and PostgreSQL connection counts after Jenkins builds before raising the limits further. CloudNativePG keeps the same `50m/128Mi` requests and `500m/384Mi` limits, but its explicit liveness/readiness probes use 5-second timeouts and six failures at a 10-second period; `stopDelay=300` with `smartShutdownTimeout=60` prevents a transient Jenkins load spike from killing PostgreSQL after only three probe misses and prevents a failed smart shutdown from blocking recovery for the default 30 minutes.

The `Sprint 5 UI smoke` and `Sprint 6 Homework smoke` stages now live in `playsay-web-app-develop` after `web-app` rollout. They use `scripts/ci/run-ui-smoke.sh`, `mcr.microsoft.com/playwright:v1.56.1-noble`, install only the matching `playwright` Node package into `/tmp/playsay-ui-smoke`, reuse the browser binaries already in the image, and run `scripts/smoke/sprint5-ui-smoke.mjs` plus `scripts/smoke/sprint6-homework-smoke.mjs` against `https://online.play-and-say.ru`. The Sprint 5 classroom flow enters through `[data-testid='classroom-prejoin-join']`; when headless media checks remain incomplete, it accepts the explicit second-click warning before waiting for the live material surface, including after the classroom reload used by the reconnect check. The stages read only the required demo passwords from the Jenkins credential source and set `PLAY_SAY_SMOKE_FETCH_PASSWORDS=false`, so Jenkins never SSHes to the dev VM or prints secret values. Keyboard frontend keeps its own browser smoke against `https://key.play-and-say.ru`.

The Sprint 6 homework/progress smoke creates a temporary published private material, creates standalone group homework for `student-demo` + `student-demo-2`, creates a single-student homework, verifies teacher UI due date/instructions and `0/N scored` without an initial `10/10`, verifies the single-student assignment has no group indicator, submits wrong answers as one student and correct answers as the other, verifies teacher group progress uses score/errors rather than status labels, resubmits improved answers, then creates homework from a completed lesson and confirms the completed live lesson is not joinable while the homework remains visible. The smoke pins demo profile `locale=en` before UI assertions and opens the compact workspace switcher through `data-testid="workspace-switcher-trigger"` before selecting a role-available `data-tab-id`; it does not depend on localized tab labels or assume that collapsed section cards are mounted. If `GET /api/assignments` returns `MATERIAL_NOT_FOUND`, check for active homework rows whose material was archived during prior smoke cleanup; current `api-gateway` must skip those rows in list endpoints so one stale assignment cannot break the teacher/student homework panels. Detail endpoints for such assignments may still return `404`.

Create the dev image pull secret after the first GHCR token is available:

```bash
read -r -p "GitHub username: " GITHUB_USERNAME
read -r -s -p "GitHub token: " GITHUB_TOKEN
echo
kubectl create namespace playsay-dev --dry-run=client -o yaml | kubectl apply -f -
kubectl -n playsay-dev create secret docker-registry ghcr-pull-secret \
  --docker-server=ghcr.io \
  --docker-username="$GITHUB_USERNAME" \
  --docker-password="$GITHUB_TOKEN" \
  --docker-email=dev@play-and-say.ru \
  --dry-run=client -o yaml | kubectl apply -f -
unset GITHUB_TOKEN
```


Current GitHub webhook for `playsay-platform`:

- Payload URL: `https://ops.play-and-say.ru:18443/jenkins/generic-webhook-trigger/invoke?token=playsay-platform-develop`
- Content type: `application/json`
- Events: push
- GitHub hook id: `632315512`
- Status: branch-aware affected-target dispatch for `develop` and `release/*` is configured through Generic Webhook Trigger on `playsay-platform-dispatch-develop`. The job filter must remain `^refs/heads/(develop|release/.+) (?!0{40}$)[0-9a-f]{40}$` over `$GITHUB_REF $GITHUB_AFTER`.
- Secret: the current dev hook uses the Generic Webhook Trigger token in the URL. Before production use, replace it with a generated secret credential and configure the same secret/token in GitHub and Jenkins.

Current GitHub webhook for `playsay-infra` -> ArgoCD refresh:

- Payload URL: `https://ops.play-and-say.ru:18443/argocd/api/webhook`
- Content type: `application/json`
- Events: push
- Secret: stored only in Kubernetes as `argocd/argocd-secret` key `webhook.github.secret`. Create or refresh it without printing the value:

```bash
./scripts/configure-argocd-webhook-secret.sh
```

When you are entering the GitHub webhook secret, read the value locally and do not paste it into chat, commits, shell history, or logs:

```bash
kubectl -n argocd get secret argocd-secret -o jsonpath='{.data.webhook\.github\.secret}' | base64 -d
```

Use the decoded value only in the GitHub webhook UI/API for `mednov-ai/playsay-infra`. This webhook wakes ArgoCD after Jenkins pushes a `values-dev.yaml` deploy commit, so module jobs normally use `ARGOCD_REFRESH_MODE=webhook`. Use `ARGOCD_REFRESH_MODE=annotate` only as a manual recovery path if the GitHub webhook is broken.

Jenkins first login:

```bash
ssh -i /Users/evgeniymednov/.ssh/play_and_say_vps_ed25519 \
  -o IdentitiesOnly=yes root@146.103.126.15 \
  "KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n jenkins get secret jenkins -o jsonpath='{.data.jenkins-admin-password}' | base64 -d"
```

Jenkins URL:

```text
https://ops.play-and-say.ru:18443/jenkins/
```

Jenkins API checks require authentication. If local `kubectl` is not configured for the dev cluster, run the API check through SSH on the VPS and read the Jenkins admin credentials from the in-cluster secret without printing them:

```bash
ssh -i /Users/evgeniymednov/.ssh/play_and_say_vps_ed25519 \
  -o IdentitiesOnly=yes root@146.103.126.15 '
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
JENKINS_URL="https://ops.play-and-say.ru:18443/jenkins"
JENKINS_JOB_NAME="playsay-platform-dispatch-develop"
JENKINS_USER="$(kubectl -n jenkins get secret jenkins -o jsonpath="{.data.jenkins-admin-user}" | base64 -d)"
JENKINS_PASSWORD="$(kubectl -n jenkins get secret jenkins -o jsonpath="{.data.jenkins-admin-password}" | base64 -d)"
curl -k -g -fsS -u "$JENKINS_USER:$JENKINS_PASSWORD" \
  "$JENKINS_URL/job/$JENKINS_JOB_NAME/api/json?tree=builds[number,displayName,building,result,timestamp,url]{0,10}" |
  jq -r ".builds[] | \"#\\(.number) \\(.displayName) building=\\(.building) result=\\(.result)\""
'
```

The current agent SSH route is the explicit key and `146.103.126.15` command above. `89.124.113.223` is retired and must not be used for Jenkins or cluster diagnostics. Unauthenticated Jenkins API calls return a login redirect or `Authentication required`; that only means auth is missing, not that the job is down. For POST requests such as job reconfiguration or manual `buildWithParameters`, also request a crumb from `/crumbIssuer/api/json` and send the returned cookie plus crumb header. When a dispatcher build has several downstream results and only one module failed, retry that module job directly with the original `BRANCH_NAME`, `GITHUB_BEFORE`, and `GITHUB_AFTER` instead of rebuilding successful modules. Keep Jenkins passwords, crumbs, GitHub tokens, and kubeconfigs out of logs and chat.

## Headlamp Kubernetes UI

Headlamp is installed at:

```text
https://ops.play-and-say.ru:18443/headlamp/
```

Get the dev-admin login token:

```bash
ssh root@<server-ip> \
  "kubectl -n headlamp get secret headlamp-admin-token -o jsonpath='{.data.token}' | base64 -d"
```

This token is cluster-admin for the dev cluster. Keep Headlamp dev-only and do not reuse this pattern for staging/prod without proper OIDC/RBAC.

## Keycloak Dev Instance

Sprint 1 installed Keycloak in minimal mode. It was first deployed before the VPS upgrade and is still intentionally single-replica/non-HA in dev:

- ArgoCD app: `keycloak`;
- namespace: `keycloak`;
- chart: local wrapper `helm-charts/keycloak`, with dependency `bitnami/keycloak` `24.9.0`;
- Keycloak version: `26.3.2`;
- URL: `https://ops.play-and-say.ru:18443/keycloak/`;
- service: NodePort `32084` on localhost through host nginx;
- PostgreSQL: chart-managed standalone PostgreSQL with a `4Gi` PVC;
- images: `docker.io/bitnamilegacy/keycloak` and `docker.io/bitnamilegacy/postgresql` because the chart's `docker.io/bitnami/...` tags are not available publicly anymore; replace with supported/private images before staging/prod. Chart `25.x` was avoided because it hit a known `Incomplete line...` startup failure in this dev setup.
- login theme: `playsay`, stored in Git under `helm-charts/keycloak/themes/playsay` and mounted into Keycloak by the wrapper chart as a ConfigMap volume. Theme caches are disabled in dev. The official logo image is copied from `play-and-say.ru`, then rendered by the theme inside an SVG organic mask with a soft animated shine so the login page keeps the Play&Say mark without showing a square JPEG block. The page syncs color mode with the SPA: `playsay_theme=light|dark|system` in the authorize URL sets `data-playsay-theme` and `data-playsay-resolved-theme` on `<html>`, while direct login links and `system` follow `prefers-color-scheme`; language dropdown links preserve the current `playsay_theme` parameter. The page stays auth-first: warm Play&Say background accents, one hero heading, the login form, and a quiet localized return link to the main `https://play-and-say.ru` site, without decorative balls/handprints, marketing chips/points, extra help copy, secondary brand header, or extra decorative markers. Failed login always renders a prominent generic global error banner above the form while preserving Keycloak field-level helper text, so unknown-user and wrong-password attempts do not reveal account existence. On mobile, the login form is ordered before the brand hero so username/password are visible without scrolling. All custom visible theme texts live in Keycloak message bundles for `ru`, `en`, `de`, and `fr`; frontend `ui_locales` and the Keycloak language dropdown must change both `<html lang>` and the visible copy.
- theme rollout: `values-dev.yaml` carries `keycloak.podAnnotations.checksum/playsay-theme` in the Keycloak pod template. Update this checksum whenever files under `helm-charts/keycloak/themes/playsay/login` or the theme ConfigMap template change; ArgoCD then rolls the Keycloak pod without a manual `rollout restart`.
- secrets: `keycloak-admin` and `keycloak-postgresql`, created manually in the cluster and never committed to Git.
- initial realm: `playsay`;
- initial realm roles: `STUDENT`, `TEACHER`, `ADMIN`;
- initial clients: `playsay-web` and `playsay-api`.

Configure or repair the dev realm after Keycloak is healthy:

```bash
./scripts/configure-keycloak-dev.sh
```

The script is idempotent. It creates/updates:

- realm `playsay`;
- realm login theme `playsay`;
- realm i18n: `internationalizationEnabled=true`, supported locales `ru`, `en`, `de`, `fr`, and default locale `ru`;
- realm roles `STUDENT`, `TEACHER`, `ADMIN`;
- public web client `playsay-web` with Authorization Code + PKCE redirects for `https://online.play-and-say.ru`, local Vite dev origins `http://localhost:5173`, `http://localhost:5174`, `http://127.0.0.1:5173`, `http://127.0.0.1:5174`, local preview origins `http://localhost:4173`, `http://127.0.0.1:4173`, and direct access grants enabled for server-side managed-student invite exchange by `registration-service`;
- backend client `playsay-api`;
- dev users `student-demo`, `student-demo-2`, `student-demo-3`, `student-demo-4`, `teacher-demo`, and `admin-demo`.

Demo passwords are generated once and stored in the Kubernetes secret `keycloak-dev-users` in the `keycloak` namespace. Re-running the script adds any missing password keys without rotating existing ones. `configure-keycloak-dev.sh` also syncs the three passwords required by Jenkins Sprint 5/Sprint 6 smoke into a same-named secret in the `jenkins` namespace through `scripts/sync-keycloak-dev-users-secret.sh`; run that sync script directly if the `jenkins` namespace is recreated. Do not commit or print those values in shared logs. Retrieve a password only when needed, replacing the jsonpath key with the needed user:

```bash
ssh root@89.124.113.223 \
  "kubectl -n keycloak get secret keycloak-dev-users -o jsonpath='{.data.student-demo-password}' | base64 -d"
```

Check status:

```bash
ssh root@89.124.113.223 "kubectl -n argocd get app keycloak && kubectl -n keycloak get pods,pvc,svc"
```

Get the admin password only when needed:

```bash
ssh root@89.124.113.223 \
  "kubectl -n keycloak get secret keycloak-admin -o jsonpath='{.data.admin-password}' | base64 -d"
```

Keep the dev instance single-replica, non-HA, and resource-limited even after the dev VPS upgrade.

After the first successful install on the original 2 vCPU / 4 GB VPS, observed usage was:

- Keycloak pod: about 470 Mi memory after startup;
- Keycloak PostgreSQL pod: about 40 Mi memory;
- node memory: about 2992 Mi / 76% by `kubectl top nodes`;
- host `MemAvailable`: about 768 Mi;
- swap: about 787 Mi used;
- disk `/`: about 18 Gi used out of 79 Gi.

This was tight but usable for Sprint 1 development. Re-check metrics after Jenkins builds and before teacher trials.

During Jenkins `dev-22` after adding UserProfile CRUD, the build completed successfully but the current VPS showed clear pressure: load average peaked around `6.6`, host `MemAvailable` dropped to about `411 Mi`, swap was about `809 Mi`, Kubernetes emitted a transient `NodeNotReady` event, and the external nginx path to `/jenkins` briefly returned `502` while Jenkins still answered through the local NodePort. Treat this as a warning signal, not yet a hard failure: no new app pods restarted and the rollout recovered cleanly.

## API Gateway Auth

`api-gateway` is a Spring Security OAuth2 Resource Server.

Public endpoints:

- `/hello`;
- `/actuator/health`;
- `/actuator/health/**`.
- `/livekit/webhook` is network-public to Spring Security but accepts only LiveKit-signed webhook payloads. It verifies the `Authorization: Bearer ...` JWT with the LiveKit API secret and the `sha256` raw body claim before recording attendance.

Protected endpoints:

- `/me` returns the current JWT profile: subject, username, email, name, and Keycloak realm roles.
- `GET /users/me/profile` returns the current app-level user profile.
- `PUT /users/me/profile` updates editable app-level fields: `displayName`, `locale`, `timezone`, and `learningGoal`.
- `DELETE /users/me/profile` resets editable app-level fields for the current user.
- `GET /admin/users` lists known app-level user profiles and requires the `ADMIN` role.
- `/admin/user-management/users|operations|students/*/teacher|delegations` provides the admin user-management facade.
- `/teacher/students|delegations` and `/teachers/directory` provide primary/delegated student management and the minimal active teacher directory.
- `GET/POST /schedule/lessons`, `GET/PUT/DELETE /schedule/lessons/{lessonId}` manage scheduled lessons.
- `POST /schedule/lessons/{lessonId}/room-token` returns a short-lived LiveKit join token for a teacher/admin or a student participant.

Sprint 2 moved UserProfile data out of the in-memory dev store into application PostgreSQL. Keycloak remains the source of identity and roles. `api-gateway` now stores the app-level profile fields in `app_user` and refreshes username, email, name, and roles from each JWT access.

### User management and delegation

No new deployment, ArgoCD application or Jenkins job is introduced. `api-gateway` owns `app_user.managed_by_teacher_user_id`, `teacher_delegation`, `teacher_delegation_student`, audit rows and background deletion operations. `registration-service` exclusively owns Keycloak Admin mutations. Deploy in this order: internal token wiring/endpoints, `api-gateway` Liquibase migration, `api-gateway`, then `web-app`.

Delegation periods are stored as instants converted from the primary teacher timezone (fallback `Europe/Moscow`); `ends_at` is exclusive at the next local day boundary. A substitute receives only student-scoped access. Schedule, classroom/collaboration, homework and AI Tutor enforce `PRIMARY_TEACHER`, `ACTIVE_DELEGATE`, `ADMIN` or `DENIED` server-side. A group lesson owned by the primary teacher can be started/completed by a substitute only when every participant is actively delegated.

Deletion is asynchronous and idempotent. `DELETE /api/admin/user-management/users/{subject}` returns `202` with an operation id; poll `/api/admin/user-management/operations/{operationId}` until `COMPLETED` or `FAILED`. Teacher deletion requires `replacementTeacherSubject` whenever dependent students/future lessons/active assignments/materials exist, and an `IN_PROGRESS` lesson blocks the request. The processor transfers ownership, revokes delegations, removes future student assignments, calls the three internal purge endpoints, deletes Keycloak invites/account through `registration-service`, and finally tombstones personal app-profile fields while historical rows remain anonymized.

Internal user-data purge endpoints are `DELETE /internal/user-data/{subject}` on `ai-tutor-service`, `vocabulary-service` and `keyboard-service`, all requiring `X-PlaySay-Service-Token`. They fail closed when the token is absent. `api-gateway` does not delete the Keycloak account until all three return `204`; a downstream failure leaves the operation `FAILED` for diagnosis/retry.

Operational checks:

```bash
kubectl -n playsay-dev get secret playsay-registration -o jsonpath='{.data.service-token}' | wc -c
kubectl -n playsay-dev get deploy api-gateway registration-service ai-tutor-service vocabulary-service keyboard-service
kubectl -n playsay-dev logs deploy/api-gateway --since=15m | grep -E 'User-data purge|USER_DELETE_FAILED'
```

Do not decode or print the token during normal verification. Role/self/last-admin protections are application checks; Keycloak console changes bypass the app audit and should remain break-glass operations only.

Dev runtime configuration is passed through the Helm chart:

```yaml
auth:
  issuerUri: https://ops.play-and-say.ru:18443/keycloak/realms/playsay
  jwkSetUri: http://keycloak.keycloak.svc.cluster.local/keycloak/realms/playsay/protocol/openid-connect/certs
ai:
  openai:
    enabled: true
    existingSecret: playsay-openai
    apiKeyKey: api-key
    model: gpt-5.4-mini
    baseUrl: https://api.openai.com/v1
database:
  existingSecret: playsay-app-db
  liquibaseEnabled: "false"
livekit:
  serverUrl: wss://online.play-and-say.ru/livekit
  existingSecret: livekit-keys
  tokenTtlSeconds: "3600"
```

The issuer stays public because Keycloak puts that value into tokens. The JWKS URI is internal so `api-gateway` can validate signatures without routing through host nginx.

## OpenAI Material Drafts

Sprint 4 material authoring can run in two modes:

- `PLAYSAY_AI_PROVIDER=stub`: deterministic local draft generator, no external API call.
- `PLAYSAY_AI_PROVIDER=openai`: `api-gateway` calls the OpenAI Responses API and requests JSON Schema / Structured Outputs for the Play&Say material draft.

The model and reasoning efforts are ordinary environment-specific Git configuration. Both dev and prod use `gpt-5.6-sol`; full material drafts use `high`, while answer suggestions, HTML-game metadata and vocabulary suggestions use `low`. Backend startup rejects any effort outside `none|low|medium|high|xhigh|max`.

The Kubernetes secret `playsay-openai` contains only `api-key`. Dev and prod use separate OpenAI Platform projects and keys; never copy the dev key into prod. The owner confirmed interactive installation of the independent prod key on 2026-07-21. Create or update the current environment's secret from an interactive terminal on its VM without printing the key:

```bash
set -euo pipefail

read -rsp "OpenAI API key: " PLAYSAY_OPENAI_API_KEY
echo

KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n "$TARGET_NAMESPACE" create secret generic playsay-openai \
  --from-literal=api-key="$PLAYSAY_OPENAI_API_KEY" \
  --dry-run=client -o yaml | KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl apply -f -

unset PLAYSAY_OPENAI_API_KEY

KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n "$TARGET_NAMESPACE" get secret playsay-openai
```

Set `TARGET_NAMESPACE=playsay-dev` on dev or `TARGET_NAMESPACE=playsay-prod` on prod. Expected `DATA` is `1`. Do not decode or paste the secret into chat, Git, logs or docs. Verify only the key name:

```bash
KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n "$TARGET_NAMESPACE" get secret playsay-openai \
  -o go-template='{{range $key, $_ := .data}}{{printf "%s\n" $key}}{{end}}'
```

After deploying the chart, verify the non-secret configuration without printing credentials:

```bash
KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n "$TARGET_NAMESPACE" get deploy api-gateway \
  -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' | grep -E 'PLAYSAY_AI_PROVIDER|OPENAI_MODEL|OPENAI_.*REASONING_EFFORT'
KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n "$TARGET_NAMESPACE" get deploy vocabulary-service \
  -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' | grep -E 'PLAYSAY_VOCABULARY_OPENAI_(MODEL|REASONING_EFFORT)'
```

Expected values are provider `openai`, model `gpt-5.6-sol`, draft effort `high` and all three lightweight efforts `low`. Run authenticated smokes for material draft, answer suggestions, HTML-game metadata and vocabulary suggestions; record no prompt, user content or secret values.

## Web App Auth

`web-app` uses Keycloak Authorization Code + PKCE with the public client `playsay-web`.

Dev defaults:

```text
VITE_AUTH_ISSUER=https://ops.play-and-say.ru:18443/keycloak/realms/playsay
VITE_AUTH_CLIENT_ID=playsay-web
VITE_AUTH_REDIRECT_PATH=/auth/callback
```

The production container serves the SPA through nginx. Requests to generic `/api/*` are proxied inside the `playsay-dev` namespace to `http://api-gateway/*`, so the browser calls the backend through the same origin `https://online.play-and-say.ru`. The specific media stream route `/api/media/video-playback-sessions/*` is handled before generic `/api/*` and proxies to `http://media-service/*` with buffering disabled. The same origin also carries WebSocket classroom sync at `/api/ws/lessons`; both the host nginx `online.play-and-say.ru` location and the web-app container nginx must pass `Upgrade` and `Connection` headers for websocket paths. The frontend calls `/api/me`, `/api/users/me/profile`, schedule endpoints, the LiveKit room-token endpoint, `/api/ws/lessons`, and media stream URLs through this same-origin route.

Current Sprint 1 UI verification points:

- login through Keycloak returns to `https://online.play-and-say.ru`;
- the user panel shows the current Keycloak identity and Play&Say roles;
- the role workspace changes between student, teacher, and admin demo users;
- the admin demo user sees the admin-only known profile list;
- logout clears local `sessionStorage` auth state and redirects through Keycloak logout.

Final Sprint 1 closure checklist:

```bash
# ArgoCD apps should be Synced / Healthy on the latest dev revision.
kubectl -n argocd get applications.argoproj.io playsay-dev-root api-gateway web-app keycloak

# Product pods should be ready and labelled with the latest Jenkins build, for example dev-24.
kubectl -n playsay-dev get pods --show-labels

# Public entrypoints should answer.
curl -k -I https://online.play-and-say.ru/
curl -k -sS https://online.play-and-say.ru/api/hello
curl -k -I https://ops.play-and-say.ru:18443/keycloak/
```

Manual auth checks:

- `student-demo`, `student-demo-2`, `student-demo-3`, and `student-demo-4` can log in, see the student workspace, `/api/me` and `/api/users/me/profile` return `200`;
- `teacher-demo` can log in, sees the teacher workspace, `/api/admin/users` returns `403`;
- `admin-demo` can log in, sees the admin workspace, `/api/admin/users` returns `200`;
- logout returns through Keycloak and clears the local browser session.

## Collaboration Service

Sprint 5 adds a Yjs websocket service for live individual and group lesson documents.

GitOps resources:

- ArgoCD app: `argocd-apps/dev/apps/collaboration-service.yaml`;
- Helm chart: `helm-charts/collaboration-service`;
- namespace: `playsay-dev`;
- image: `ghcr.io/mednov-ai/playsay-collaboration-service`;
- secret: `playsay-collaboration` in namespace `playsay-dev`.

The same `playsay-collaboration` secret is mounted into `api-gateway` and `collaboration-service`. It contains:

- `token-secret`: HS256 signing secret for backend-issued room tokens;
- `service-token`: header token used by `collaboration-service` when it persists room snapshots back to api-gateway.

Create or refresh it without printing values:

```bash
./scripts/sync-collaboration-secret.sh
```

`deploy-cluster-addons.sh` runs the sync script automatically when it exists. Do not commit or print the secret values.

Host nginx config is generated with a `/collab/ws` location under `online.play-and-say.ru`:

- public websocket URL: `wss://online.play-and-say.ru/collab/ws`;
- local NodePort target: `127.0.0.1:32086`;
- Kubernetes service: `collaboration-service` in `playsay-dev`.

The frontend receives short-lived room tokens from api-gateway, then opens `/collab/ws?room=<yjsDocumentId>&token=<token>`. The websocket service validates that the room query exactly matches token claims before joining the Yjs room. Snapshot persistence uses `PUT /schedule/lessons/{lessonId}/collaboration-documents/{documentId}/snapshot` with header `X-PlaySay-Collaboration-Service-Token`.

Smoke checks:

```bash
kubectl -n argocd get applications.argoproj.io collaboration-service api-gateway web-app
kubectl -n playsay-dev get pods -l app.kubernetes.io/name=collaboration-service
kubectl -n playsay-dev get secret playsay-collaboration
curl -k -I https://online.play-and-say.ru/collab/ws
```

Expected `curl` result is an HTTP response from the service path, not a full websocket session. Functional verification happens in the browser: teacher creates a group lesson, two students join, each student edits an individual document, everyone edits the group document, colored presence cursors appear, reconnect restores text and annotations, and finalize creates a normal material submission.

Automated Sprint 5 UI smoke and Sprint 6 homework smoke live in `playsay-platform`. Jenkins runs them automatically after updating dev image tags, using the Playwright smoke container and the `keycloak-dev-users` secret in the `jenkins` namespace. The same scripts can still be run locally with the agent Playwright install without adding Playwright to the app dependencies:

```bash
cd /Users/evgeniymednov/Documents/Projects/Play\&Say/playsay-platform
PLAYWRIGHT_PACKAGE_DIR=/Users/evgeniymednov/.codex/tools/playwright \
  ./scripts/smoke/sprint5-ui-smoke.mjs
PLAYWRIGHT_PACKAGE_DIR=/Users/evgeniymednov/.codex/tools/playwright \
  ./scripts/smoke/sprint6-homework-smoke.mjs
```

The Sprint 5 script obtains Keycloak Authorization Code + PKCE tokens as `teacher-demo`, `student-demo`, and `student-demo-2`, reads demo passwords from env vars in Jenkins or from the dev `keycloak-dev-users` Kubernetes secret over SSH during local runs without printing them, creates a temporary published private material, active group lesson, and required collaboration documents through the API for deterministic setup, then drives real browser classroom pages for teacher + two students. It verifies individual documents, teacher supervision/edit, group document sync, colored material-scoped cursors clipped to the lesson material surface, annotation sync after scroll/resize/reload, and finalize creating a normal material submission. The Sprint 6 script uses the same auth path, creates temporary homework material, standalone group/single assignments and lesson carry-over homework, then verifies homework UI, permissions, score/errors progress and resubmit. Both scripts clean up temporary lessons and archive temporary materials at the end.

## LiveKit Dev Video

Sprint 3 video work started early to make the platform demonstrable from the schedule screen.

GitOps resources:

- ArgoCD app: `argocd-apps/dev/apps/livekit.yaml`;
- Helm chart: `helm-charts/livekit`;
- namespace: `livekit`;
- image: `livekit/livekit-server:v1.11.0`;
- LiveKit secret name: `livekit-keys` in namespaces `livekit` and `playsay-dev`.
- coturn secret name: `coturn-auth-secret` in namespace `livekit`.

The dev chart runs one LiveKit pod with `hostNetwork: true` and `enableServiceLinks: false` on the current single-node VPS. `enableServiceLinks` must stay disabled because Kubernetes service env vars such as `LIVEKIT_PORT=tcp://...` conflict with LiveKit's own numeric `LIVEKIT_PORT` option. Host nginx proxies signaling through the product origin:

- public signaling URL: `wss://online.play-and-say.ru/livekit`;
- local signaling target: `127.0.0.1:7880`;
- LiveKit TCP fallback: `7881`;
- dev ICE UDP range: `50000-50020`.
- standalone TURN host: `online.play-and-say.ru:3478` over UDP/TCP;
- coturn relay UDP range: `49160-49200`.

The LiveKit API key/secret are generated or synced by:

```bash
./scripts/sync-livekit-secret.sh
```

`deploy-cluster-addons.sh` runs the sync script automatically when it exists. Do not commit or print the secret values. If the `livekit` namespace already has `livekit-keys`, the script reuses it and copies it to `playsay-dev` for `api-gateway`.

The standalone coturn shared secret is generated by the Ansible `coturn` role on the VPS:

```text
/etc/playsay/coturn-auth-secret
```

Sync the canonical 64-character hex value into Kubernetes before the LiveKit chart with TURN enabled syncs. The script removes CR/LF and rejects any other shape without printing the value:

```bash
./scripts/sync-coturn-secret.sh
```

`deploy-cluster-addons.sh` also runs the coturn sync script automatically. A changed Secret does not alter an already running pod environment, so schedule a no-room maintenance window and request the explicit restart:

```bash
./scripts/sync-coturn-secret.sh --restart-livekit
```

The LiveKit container defensively removes CR/LF and validates the secret again before writing `/tmp/livekit.yaml`. Do not print the file content or decoded Kubernetes value. If UFW or another firewall is later enabled, allow `3478/tcp`, `3478/udp`, and `49160:49200/udp`.

The LiveKit chart sends webhooks to the internal api-gateway service:

```text
http://api-gateway.playsay-dev.svc.cluster.local/livekit/webhook
```

`api-gateway` handles `participant_joined` and `participant_left` by updating `lesson_participant.joined_at`, `left_at`, `attendance_status`, and setting the lesson to `IN_PROGRESS` on first join. The controller accepts `application/json` and `application/webhook+json` as raw bytes, verifies the JWT `sha256` claim against those exact bytes, and only then decodes JSON. The endpoint is hidden from the public OpenAPI contract and must not be called manually without a valid LiveKit webhook signature.

Host nginx config is generated with a `/livekit/` location under `online.play-and-say.ru`, and the main `location /` must also pass WebSocket upgrade headers so `/api/ws/lessons` can reach the web-app container and then `api-gateway`. After changing the script on an existing server, rerun the add-ons script or manually verify the rendered host config:

```bash
nginx -t
systemctl reload nginx
```

Smoke checks:

```bash
kubectl -n argocd get applications.argoproj.io livekit api-gateway web-app
kubectl -n livekit get pods -o wide
kubectl -n playsay-dev get secret livekit-keys
kubectl -n livekit get secret coturn-auth-secret
systemctl status coturn --no-pager
ss -lntup | grep -E ':(3478|7880|7881)\b'
curl -k -I https://online.play-and-say.ru/livekit/
```

Verify TURN authentication with an actual allocation, not only an open port. Keep the secret in a transient shell variable and never enable verbose output:

```bash
set -e
COTURN_SMOKE_SECRET="$(tr -d '\r\n' </etc/playsay/coturn-auth-secret)"
turnutils_uclient -W "$COTURN_SMOKE_SECRET" -p 3478 -n 1 -c 127.0.0.1
unset COTURN_SMOKE_SECRET
```

The command must exit `0`, coturn logs must not contain `Cannot find credentials`, and a cross-network browser check must show a selected `relay` ICE candidate when relay-only policy is forced in the diagnostic client. Also confirm normal Play&Say calls prefer a healthy direct path when available.

For a functional check, log in to `https://online.play-and-say.ru` as a teacher, create or reuse a scheduled lesson with `student-demo`, `student-demo-2`, and `student-demo-3` as participants, and enter the classroom. Before students open the room, teacher/admin must see one persistent placeholder tile per assigned student with “not connected yet”; a student must never receive that presence map. Log in as each student in a separate browser profile and confirm the teacher tile changes `OFFLINE → ONLINE`. Open the classroom URL as a student: the branded pre-join must appear without creating a LiveKit participant, and the teacher tile must change to “checking connection”. Allow camera/microphone permissions, verify the camera preview and choose the intended input/output. Hold the sound button for `0.3–5` seconds, speak, release it, listen to the automatically played recording and confirm “yes, I hear”; the live meter is informational and background noise alone must not mark the microphone ready. Where supported, verify playback follows the selected output; otherwise it must use the system output. Changing either audio device must reset the check. A short/failed/skipped recording must show a warning and still allow the explicit second-click entry. Device choices survive reload, while pre-join appears before every entry.

Repeat pre-join at `1280×720`, `1440×900`, and a phone viewport. At `1280×720`, the join button must remain visible, the result area must not resize when the hearing confirmation appears, and the page must not jump upward. Only after entry confirmation may the room-token request run and LiveKit connect. The teacher’s placeholder must then be replaced by the real LiveKit participant with no duplicate; in an individual lesson the absent student is the main tile and local teacher video is PiP, while a group lesson shows every assigned student. In the room, verify microphone/camera device menus can switch inputs without leaving, the page does not scroll, and controls expose microphone/camera/screen share according to participant permissions. Finally close/reopen the student WebSocket and confirm `ONLINE` is restored; with two student tabs, one tab in pre-join keeps the aggregated state at `CHECKING_DEVICES` until it leaves.

For screen-share audio, use macOS 14.2+ and a current Chrome/Edge profile. Start sharing with audio enabled in the browser picker: the first full system-audio capture must request the macOS `Screen & System Audio Recording` permission, the remote participant must hear shared media once while microphone audio remains independent, and the remote voice must not loop back as echo. Repeat with browser audio sharing disabled and confirm the localized no-audio warning appears, then stop sharing and confirm both screen video/audio publications and the warning disappear. In Safari, confirm video-only sharing continues and shows the Safari-specific Chrome/Edge recommendation. At `1280×720` and `1440×900`, the warning must stay above the controls without resizing the classroom or covering the primary video.

## Application PostgreSQL

Sprint 2 starts the application database on the same dev VPS. It was introduced before the later VPS upgrade, and the database setup remains intentionally small until the first teacher trial proves that more capacity is needed.

GitOps applications:

- `cloudnative-pg`: CloudNativePG operator `1.29.1`, installed from a local Kustomize overlay pinned to the upstream tag `v1.29.1`;
- `app-postgres`: Play&Say application PostgreSQL cluster, rendered from `helm-charts/app-postgres`.

Dev shape:

- namespace: `playsay-data`;
- cluster name: `playsay-postgres`;
- PostgreSQL image: `ghcr.io/cloudnative-pg/postgresql:17.6-system-trixie`;
- instances: `1`;
- storage: `2Gi` PVC;
- requests/limits: `50m/128Mi` requests, `500m/384Mi` limits;
- database: `playsay`;
- owner: `playsay_app`.

Check status:

```bash
kubectl -n argocd get applications.argoproj.io cloudnative-pg app-postgres
kubectl -n cnpg-system get pods
kubectl -n playsay-data get cluster,pods,pvc,secrets
kubectl -n playsay-data get svc
```

CloudNativePG generates database credentials as Kubernetes secrets. Retrieve values only when needed for wiring an application or a manual smoke test; do not paste them into chat, Git, shell history snippets, or documentation.

Because `app-postgres` runs in `playsay-data`, while `api-gateway` runs in `playsay-dev` and Jenkins agents run in `jenkins`, copy the generated application connection secret into those namespaces after the database is healthy:

```bash
./scripts/sync-app-db-secret.sh
```

The script copies `playsay-postgres-app` from `playsay-data` into `playsay-app-db` in `playsay-dev` and `jenkins`, using the source secret's `fqdn-jdbc-uri` as the target `jdbc-uri`. It handles secret values through temporary files and does not print them. Re-run it if CloudNativePG rotates the application password or if a namespace is recreated.

`api-gateway` uses this secret through Helm env vars:

- `PLAYSAY_DB_JDBC_URL` from `playsay-app-db` key `jdbc-uri`;
- `PLAYSAY_DB_USERNAME` from key `username`;
- `PLAYSAY_DB_PASSWORD` from key `password`;
- `PLAYSAY_LIQUIBASE_ENABLED=false` in the runtime pod.

Keep the CloudNativePG operator overlay less aggressive than the upstream default: `--max-concurrent-reconciles=2`, `500m/256Mi` limits, and 5-second probe timeouts. The upstream `100m` CPU limit plus 1-second probes repeatedly lost leader election while Jenkins was building `dev-28` on the original 2 vCPU / 4 GB VPS.

Useful connection endpoints inside the cluster:

- read/write service: `playsay-postgres-rw.playsay-data.svc.cluster.local:5432`;
- read-only service: `playsay-postgres-ro.playsay-data.svc.cluster.local:5432`;
- database: `playsay`;
- app user: `playsay_app`.

Initial Sprint 2 schema is owned by `api-gateway` changelogs:

- changelog root: `backend/api-gateway/src/main/resources/db/changelog/db.changelog-master.xml`;
- first changeset: `2026-05-24-001-create-sprint2-domain-tables`;
- tables: `app_user`, `student_profile`, `teacher_profile`, `course`, `lesson_template`, `lesson`, `lesson_participant`, `assignment`, `submission`;
- `/users/me/profile` persists editable fields in `app_user` instead of memory.

Manual migration smoke path, matching Jenkins network and secrets:

1. Ensure `playsay-app-db` exists in `jenkins` by running `./scripts/sync-app-db-secret.sh`.
2. Start a temporary pod in `jenkins` with `liquibase/liquibase:5.0.3`.
3. Copy the `db/changelog` directory into the pod.
4. Download PostgreSQL JDBC driver `42.7.8`.
5. Run `liquibase status --verbose` and `liquibase update`.

On 2026-05-24 this path applied one pending changeset successfully and the expected tables appeared in `public`.

After enabling this database, re-check VPS pressure:

```bash
uptime
free -m
kubectl top nodes
kubectl top pods -A | sort -k3 -h | tail -n 20
```

## Optional Separate Server Bootstrap

Install Ansible dependencies:

```bash
cd playsay-infra/ansible
ansible-galaxy collection install -r requirements.yaml
```

Create inventory:

```bash
cp inventories/dev/hosts.yaml.example inventories/dev/hosts.yaml
```

Edit `inventories/dev/hosts.yaml`:

- `ansible_host`
- `public_ipv4`
- `ansible_ssh_private_key_file`
- `dev_domain`

Run bootstrap:

```bash
cd playsay-infra
./scripts/new-server.sh dev
```

## Optional Local kubectl

Local kubeconfig is not required for initial bootstrap. It is useful later for diagnostics:

```bash
mkdir -p ~/.kube/configs
scp playsay@<server-ip>:/home/playsay/.kube/config ~/.kube/configs/playsay-dev
export KUBECONFIG=~/.kube/configs/playsay-dev
kubectl get nodes
```

If the k3s API is not exposed publicly, create an SSH tunnel and replace the kubeconfig server URL with `https://127.0.0.1:6443`.

## Optional Separate Cluster Add-ons

```bash
export PLAYSAY_DOMAIN=dev.example.com
export LETSENCRYPT_EMAIL=admin@example.com
export ARGOCD_HOST=argocd.dev.example.com
export HEADLAMP_HOST=headlamp.dev.example.com
export OPS_HOST=ops.play-and-say.ru
export OPS_PORT=18443
export OPS_TLS_MODE=auto
# Optional CIDRs, for example Amnezia VPN subnet and/or fixed admin IP.
export OPS_ALLOW_CIDRS=
export INSTALL_JENKINS=true
export INSTALL_INGRESS_NGINX=false
export INSTALL_CERT_MANAGER=false
export CONFIGURE_HOST_NGINX=true

./scripts/deploy-cluster-addons.sh dev
```

## ArgoCD

Initial admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

Open:

```text
https://argocd.dev.example.com
```

## Upgrade VDSina VPS

Upgrade completed on 2026-05-24 after Sprint 2 CI pressure. Current dev VPS shape:

- CPU: 4 vCPU
- RAM: 8 GB
- Disk: 160 GB NVMe
- Traffic: 32 TB

The root disk still needed an in-guest online resize after the provider-side upgrade.

Baseline metrics captured before Sprint 1 on the original 2 vCPU / 4 GB / 80 GB VPS:

- CPU: about 5% from `kubectl top nodes`;
- Kubernetes memory: about 2702 Mi / 69%;
- host memory: 3.8 Gi total, 2.6 Gi used, 1.3 Gi available;
- swap: 2.0 Gi total, 754 Mi used;
- disk `/`: 79 Gi total, 16 Gi used, 61 Gi available;
- largest local dirs: `/var/lib/rancher` about 7.6 Gi, `/var/log` about 1.3 Gi, `/var/lib/docker` about 108 Mi.

Historical upgrade triggers:

- Keycloak/PostgreSQL or Jenkins builds start causing OOM kills or pod restarts;
- `MemAvailable` stays below about 500 Mi during normal idle/dev usage;
- swap stays above about 1 Gi and the UI/builds become painfully slow;
- Jenkins builds repeatedly cause transient `NodeNotReady` or external `/jenkins` `502` errors;
- the first teacher trial conference needs a more stable environment.

The VDSina panel flow was:

1. Open the server configurator.
2. Increase resources:
   - actual Sprint 2 upgrade: 4 vCPU / 8 GB / 160 GB
   - future Sprint 4+: 8 vCPU / 16 GB / 160+ GB if needed
3. Apply changes and let the server reboot.
4. Expand the root partition and filesystem on the VPS:

```bash
growpart /dev/vda 1
resize2fs /dev/vda1
```

Before the in-guest resize, the provider disk was already `160G`, but `/dev/vda1` and `/` were still about `80G`. After the resize:

- `/dev/vda1`: `160G`
- `/`: ext4 `158G`, about `23G` used and `129G` available

5. Verify:

```bash
kubectl get nodes
kubectl get pods -A
df -hT /
free -h
systemctl is-active nginx k3s docker
nginx -t
```

After the resize, `nginx`, `k3s`, and `docker` were active, `nginx -t` passed, ArgoCD apps were `Synced / Healthy`, and the deployed `api-gateway` / `web-app` pods were ready on build `dev-28`.

Also run the post-install verification checklist above after any future reboot or resize, including the public site, Amnezia Docker containers, nginx syntax, ops UI, and `online.play-and-say.ru`.

## Dev Backup Stub

Sprint 1 keeps backups intentionally simple until real production data exists.

Backup scope:

- Keycloak PostgreSQL database;
- application PostgreSQL database once the platform database is introduced.

Storage target:

- local directory on the dev VPS, for example `/var/backups/playsay`;
- files must not be committed to Git or copied into the workspace;
- external S3/restic storage for database dumps is deferred until real user data or staging/prod hardening; material assets already live in dev MinIO and must be included in the real backup plan before production data.

Expected backup shape:

```bash
mkdir -p /var/backups/playsay
pg_dump "$KEYCLOAK_DATABASE_URL" > "/var/backups/playsay/keycloak-$(date +%F-%H%M%S).sql"
pg_dump "$PLAYSAY_DATABASE_URL" > "/var/backups/playsay/playsay-$(date +%F-%H%M%S).sql"
```

Use Kubernetes secrets or pod environment variables to obtain database connection details. Do not paste database passwords into chat, Git commits, shell history snippets, or documentation.

## Disaster Recovery Drill

1. Create a fresh VPS.
2. Run `./scripts/bootstrap-dev.sh --ip <new-ip> --domain dev.example.com --email admin@example.com`.
3. Switch DNS to the new IP.
4. Let ArgoCD restore Git-defined applications.
5. Restore Keycloak and application PostgreSQL dumps from `/var/backups/playsay` when those databases exist.
6. Run the post-install verification checklist above.

Before real student/teacher data appears, replace the local-only backup target with off-server storage and test a full restore.

## Rollback

Application rollback is GitOps-based:

```bash
cd playsay-infra
git revert <bad-commit>
git push
```

ArgoCD will sync the reverted state.

## AI Tutor Service

`ai-tutor-service` разворачивается ArgoCD из `helm-charts/ai-tutor-service` в `playsay-dev`. `web-app/nginx.conf` направляет `/api/ai-tutor/` на cluster service, поэтому отдельный публичный NodePort или host-nginx route не нужен.

Возрастная политика AI-разговора определяется только backend по `student_profile.birth_date`: `<13 = CHILD`, `13–17 = TEEN`, `18+ = ADULT`; non-student роли получают `ADULT`. Параметра `agePolicy` в запросах каталога и создания сессии нет. Если у `STUDENT` дата рождения не заполнена, ожидаем `409 Conflict`; сначала сохраните дату рождения через профиль SPA/API. `ai-tutor-service` читает `app_user` и `student_profile` через JPA entity/repository и не содержит прямых SQL-вызовов.

Keep `org.hibernate.orm.connections.pooling` at `WARN` for this service: the shared dev JDBC URI can contain connection parameters and must not be printed by Hibernate's startup database-info logger.

Перед включением живого голоса проверьте Secret `playsay-openai` с ключом `api-key`; значение нельзя выводить в логи. Dev chart включает `PLAYSAY_AI_TUTOR_REALTIME_PROVIDER=openai`, модель `gpt-realtime-2.1` и выполняет Liquibase при single-replica startup. Если Secret или provider недоступен, установите `openai.enabled=false`: каталог и сохранение сессий продолжат работать в явном stub-режиме.

Проверка после rollout:

```bash
kubectl -n playsay-dev rollout status deploy/ai-tutor-service
kubectl -n playsay-dev get svc ai-tutor-service
kubectl -n playsay-dev port-forward svc/ai-tutor-service 18087:80
curl -fsS http://127.0.0.1:18087/actuator/health
```

Production-допуск детских голосовых сессий блокируется до документированного родительского согласия, сроков удаления аудио и safety-eval свободных тем. AI-тренер не выполняет pronunciation scoring: неразборчивую реплику нужно запросить повторно без сохранения `TURN_EVALUATION`.

## Individual Lesson Push-to-Talk Translation

Перевод в live classroom работает только для `INDIVIDUAL` lesson с одним teacher и одним student и выключен для каждого ученика по умолчанию. До smoke основной преподаватель, активный замещающий преподаватель или администратор должен явно включить галку голосового перевода в карточке ученика. Без галки у teacher и student отсутствуют кнопка, статусы, captions, disclosure и связанные pointer/keyboard actions; frontend не вызывает translation API. После профильного разрешения обе стороны всё равно отдельно включают функцию внутри урока. Browser listener создаёт второй WebRTC connection к OpenAI Realtime Translation; source LiveKit microphone track подключается к нему, пока remote participant удерживает push-to-talk, и отключается после capture tail до 300 мс. Переведённый звук и последние три caption существуют только в браузере, backend их не сохраняет.

`api-gateway` выдаёт короткоживущие client secrets через authenticated `POST /api/schedule/lessons/{lessonId}/translation-session`. Постоянный provider key должен оставаться в существующем Secret `playsay-openai`, key `api-key`; не выводите его через `kubectl get secret`, shell history или логи. Dev values включают:

```yaml
lessonTranslation:
  enabled: true
  provider: openai
  model: gpt-realtime-translate
  baseUrl: https://api.openai.com/v1
  existingSecret: playsay-openai
  apiKeyKey: api-key
```

Chart передаёт в `api-gateway` `PLAYSAY_LESSON_TRANSLATION_ENABLED`, `PLAYSAY_LESSON_TRANSLATION_PROVIDER`, `PLAYSAY_LESSON_TRANSLATION_MODEL`, `PLAYSAY_LESSON_TRANSLATION_BASE_URL` и secret-backed `PLAYSAY_LESSON_TRANSLATION_API_KEY`. Перед classroom smoke проверьте только наличие Secret и rollout, не значение ключа:

```bash
kubectl -n playsay-dev get secret playsay-openai
kubectl -n playsay-dev rollout status deploy/api-gateway
kubectl -n playsay-dev logs deploy/api-gateway --since=10m | rg 'Lesson translation credential request failed|Started ApiGatewayApplication'
```

Smoke выполняется двумя authenticated браузерами в одном начавшемся individual lesson:

1. Оставьте профильную галку выключенной и войдите teacher и student. У обоих не должно быть кнопки, статусов, captions, disclosure или клавиатурного управления переводом; в Network не должно быть запросов к `translation-session`.
2. Проверьте backend guard: запрос `POST /api/schedule/lessons/{lessonId}/translation-session` от участника урока возвращает `409` с `LESSON_TRANSLATION_PERMISSION_REQUIRED`, а в backend-логах нет попытки запроса credential provider.
3. Основной преподаватель, активный замещающий преподаватель или администратор включает галку в карточке ученика. Обновите страницу classroom либо войдите заново в обоих браузерах; открытый без обновления room token не обязан менять UI.
4. Teacher и student отдельно включают перевод внутри урока. Teacher удерживает кнопку и student слышит `app_user.locale` (`ru`, `de` или `fr`), затем student удерживает кнопку и teacher слышит английский. Во время translated output исходный голос должен быть приглушён, после реплики — восстановлен. После refresh captions должны исчезнуть.
5. Снимите профильную галку. UI уже открытого classroom может оставаться до refresh/повторного входа, но новая попытка получить credentials должна сразу вернуть `409`; после обновления элементы перевода снова полностью отсутствуют.

Group lesson, неподдерживаемый locale и участник вне lesson должны получать явный отказ без отправки аудио provider.

Если provider недоступен или нужно быстро отключить контур, установите `lessonTranslation.enabled=false` и синхронизируйте ArgoCD. Это отключает только credential endpoint/translation control и не мешает основному LiveKit classroom. Не заменяйте этот rollback остановкой Docker, LiveKit, Amnezia или root site на `play-and-say.ru`.
