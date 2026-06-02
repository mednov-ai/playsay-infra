# Play&Say Dev Runbook

## Sprint 0 Status

Sprint 0 is complete. This runbook now describes the working dev baseline for Sprint 2.

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
  --ip 146.103.126.15 \
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
- `wss://online.play-and-say.ru/collab/ws` (Sprint 5 collaboration websocket)

The existing `play-and-say.ru` site server block is not overwritten.

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
  --ip 146.103.126.15 \
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
  --ip 146.103.126.15 \
  --domain play-and-say.ru \
  --ops-host ops.play-and-say.ru \
  --ops-port 18443 \
  --ops-tls-mode existing \
  --online-host online.play-and-say.ru \
  --online-tls-mode existing \
  --email admin@example.com
```

If you know the Amnezia VPN CIDR or a fixed admin IP, restrict the ops UI:

```bash
./scripts/bootstrap-dev.sh \
  --ip 146.103.126.15 \
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
  --ip 146.103.126.15 \
  --domain play-and-say.ru \
  --email admin@example.com \
  --no-host-nginx
```

## Public Site and Online App Hostnames

Current DNS/nginx split:

- `play-and-say.ru` stays the public marketing/site host.
- `online.play-and-say.ru` serves the React product SPA from k3s service `web-app`.
- `online.play-and-say.ru/collab/ws` proxies directly to the `collaboration-service` NodePort for Yjs websocket rooms.
- `ops.play-and-say.ru:18443` is reserved for dev infrastructure UI.
- `ops.play-and-say.ru:18443/keycloak/` serves the Sprint 1 Keycloak dev instance.

The login redirect is not only an nginx setting. When Keycloak is added, `online.play-and-say.ru` must also be added to the frontend app config and Keycloak client's allowed redirect URIs. The future `play-and-say.ru` login button should start Keycloak auth and return users to `online.play-and-say.ru`.

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

`api-gateway` streams private material assets through `/api/materials/{materialId}/assets/{assetId}/content`; browsers never need direct MinIO access. Legacy `data:image` material assets are intentionally not supported after the MinIO migration.

Check object storage state:

```bash
kubectl -n argocd get application minio
kubectl -n storage get pods,pvc,svc
kubectl -n playsay-dev get secret playsay-object-storage
```

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

Expected extra steady-state footprint is roughly `300-600Mi` RAM, depending on series count and scrape load. If memory pressure appears during Jenkins builds or group video tests, first reduce `monitoring-lite` retention/scrape targets before increasing VPS size.

Telegram alerts are optional at boot. Alertmanager starts with a null receiver when the secret is missing, so ArgoCD remains healthy. To enable Telegram notifications, create the secret manually without printing values:

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

## Post-Install Verification

Check the public site still works:

```bash
curl -I https://play-and-say.ru
```

Expected: `HTTP/1.1 200 OK`.

Check cluster health:

```bash
ssh root@146.103.126.15 "kubectl get nodes -o wide && kubectl get pods -A"
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
curl -k -I --resolve ops.play-and-say.ru:18443:146.103.126.15 https://ops.play-and-say.ru:18443/headlamp/
curl -k -I --resolve ops.play-and-say.ru:18443:146.103.126.15 https://ops.play-and-say.ru:18443/argocd/
curl -k -I --resolve ops.play-and-say.ru:18443:146.103.126.15 https://ops.play-and-say.ru:18443/jenkins/
curl -k -I --resolve ops.play-and-say.ru:18443:146.103.126.15 https://ops.play-and-say.ru:18443/keycloak/
curl -k -I --resolve ops.play-and-say.ru:18443:146.103.126.15 https://ops.play-and-say.ru:18443/victoria-metrics/vmui/
curl -k -I --resolve online.play-and-say.ru:443:146.103.126.15 https://online.play-and-say.ru/
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
ssh root@146.103.126.15 "docker ps --format '{{.Names}} {{.Ports}}' && systemctl is-active nginx k3s docker && nginx -t"
```

Expected: Amnezia containers are present, nginx/k3s/docker are active, nginx syntax is successful.

Check public port hardening:

```bash
nc -vz -w 5 146.103.126.15 18443
nc -vz -w 5 146.103.126.15 6443
nc -vz -w 5 146.103.126.15 10250
nc -vz -w 5 146.103.126.15 9100
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

The Jenkins job `playsay-platform-develop` is configured by:

```bash
./scripts/configure-jenkins-jobs.sh
```

The bootstrap/add-ons script runs it automatically after Jenkins is installed. The job has a `BRANCH_NAME` parameter:

- `develop` creates build labels such as `dev-11`;
- `codex/task-1` creates labels such as `codex_task-1-12`;
- `feature/task-1` creates labels such as `f_task-1-12`;
- `release/1.001.00` creates labels such as `rel_1.001.00-13`;
- `hotfix/fix-login` creates labels such as `hotfix_fix-login-14`.

Deployable dev branches are `develop`, `codex/*`, `feature/*`, `release/*`, and `hotfix/*`. Other branches still run build/test stages but skip image publishing, source tagging, DB migrations, and dev image tag updates.

The job uses Generic Webhook Trigger to run automatically for GitHub push events on `develop` and `release/*`. In practice this means a merge commit pushed to `develop` or any `release/*` branch starts Jenkins automatically. The trigger extracts `ref` into `BRANCH_NAME`, strips the `refs/heads/` prefix, rejects `refs/tags/*`, and ignores branch deletion events where `after` is forty zeroes. This keeps Jenkins Git tags from recursively starting new builds while allowing merge commits into `develop` and `release/*` to build automatically. Trigger `codex/*`, `feature/*`, and `hotfix/*` branches manually through Jenkins UI/API with an explicit `BRANCH_NAME` when a dev deploy of that branch is needed.

The build label is written to:

- Jenkins build display name;
- GHCR image tags for `playsay-api-gateway`, `playsay-web-app`, and `playsay-collaboration-service`;
- Git tags in `playsay-platform` and `playsay-infra`;
- Helm `values-dev.yaml` build metadata;
- Kubernetes pod labels and annotations under `playsay.io/*`.

Check what is deployed:

```bash
kubectl -n playsay-dev get pods --show-labels
kubectl -n playsay-dev get pod -l app.kubernetes.io/name=api-gateway -o jsonpath='{.items[0].metadata.annotations}'
```

Backend image builds are intentionally runtime-only. Jenkins runs `gradle :api-gateway:bootJar` once in the `Backend package` stage, then Kaniko builds `backend/api-gateway/Dockerfile` by copying the already-built jar from `api-gateway/build/libs`. Do not add a Gradle build stage back into the backend Dockerfile unless the pipeline is redesigned.

Frontend image builds are intentionally runtime-only too. Jenkins runs `npm --workspace web-app run build` once in the `Frontend build` stage, then Kaniko builds `frontend/web-app/Dockerfile` by copying the already-built `web-app/dist` into nginx. Do not add `npm install`, `npm ci`, or `npm run build` back into the frontend Dockerfile unless the pipeline is redesigned.

Jenkins agent requests are kept moderate so the build pod can schedule on the dev VPS while Keycloak and application PostgreSQL are running. Current Jenkinsfile requests are `500m / 1Gi` for Gradle, `300m / 512Mi` for the frontend Node lane, `200m / 384Mi` for the collaboration Node lane, `250m / 256Mi` for each Kaniko container, and `300m / 512Mi` for the Sprint 5 Playwright smoke container; Jenkins also injects a small `jnlp` container. The pipeline now has separate Node lanes for frontend and collaboration validation, plus separate Kaniko containers for api-gateway, web-app, and collaboration-service images. Limits remain intentionally conservative after the upgrade to 4 vCPU / 8 GB RAM: Gradle `2 CPU / 3Gi`, frontend Node `1500m / 1Gi`, collaboration Node `1 CPU / 768Mi`, each Kaniko container `1 CPU / 1Gi`, and smoke `1 CPU / 1536Mi`. Gradle stages use `--max-workers=2` with the Kotlin compiler in-process; frontend/collaboration validation lanes run in parallel with backend validation, and the three image builds run in parallel after `DB migrate`. Jenkins agent pods explicitly use serviceAccount `jenkins`; `deploy-cluster-addons.sh` grants it read-only access to ArgoCD Applications and `playsay-dev` deployments/pods so `Wait for dev rollout` can verify `Synced/Healthy`, `playsay.io/build-name`, ready replicas, and ready pods before smoke. The agent pod mounts the `jenkins-agent-cache` PVC for Gradle and npm caches; `deploy-cluster-addons.sh` creates this `4Gi` PVC before installing Jenkins. If a build shows no Stage View progress and the console says `Insufficient memory`, the pod is unscheduled before `Checkout`; abort that stuck build after pushing lower requests or free memory before retrying. If a running build shows OOM/restarts or strong swap growth, first revert Gradle/Node resources, Gradle `--max-workers=1`, or the new parallel stages.

After Sprint 2 app PostgreSQL was added, Jenkins `dev-25` failed in `Backend tests` because Maven Central DNS resolution temporarily failed while the node was overloaded. A retry `dev-26` pushed load above `11` on the original 2 vCPU VPS, made the Kubernetes API intermittently time out, and was stopped manually. The first conservative retry `dev-27` proved that `1Gi` is too low for Gradle on `compileKotlin`, so Gradle memory was raised to `1536Mi` while limiting CPU and workers. Build `dev-28` passed with the conservative Jenkinsfile mode: Gradle `--max-workers=1`, Kotlin compiler in-process, lower CPU for build containers, and persistent Gradle/npm cache. During Sprint 4, Jenkins `dev-53` was `OOMKilled` in the Gradle container during backend tests after the test suite and Jackson dependencies grew; the Gradle request/limit were raised to `768Mi`/`2Gi` while keeping `--max-workers=1` and Kotlin compiler in-process. The current `--max-workers=2` mode is a build-time canary for the upgraded VPS, not a reason to ignore OOM/restart/swap signals.

Jenkins chart must keep `controller.overwritePlugins=true`. In chart `jenkins-5.9.22`, the rendered `apply_config.sh` can still contain interactive `yes n | cp -i ...` plugin copying; after a controller restart this can leave the init container in `CrashLoopBackOff` and Jenkins will serve `502` through host nginx because the service has no ready endpoints. `deploy-cluster-addons.sh` patches the Jenkins ConfigMap to use non-interactive `cp -f ...` after Helm upgrade and deletes `jenkins-0` only if it is already stuck in init `CrashLoopBackOff`. If `/jenkins/` returns `502` after a VPS reboot, check `kubectl -n jenkins get pod,endpoints` first; healthy Jenkins should be `2/2 Running`, have an endpoint, and return `403 Forbidden` or a login redirect through nginx.

The `OpenAPI contract` stage runs `gradle :api-gateway:exportOpenApi`, writes `contracts/openapi.yaml`, checks that the generated file matches the committed contract, and archives it as a Jenkins artifact. If this stage fails with an out-of-sync message, regenerate the contract locally or in the same Gradle container, commit `contracts/openapi.yaml`, and rerun Jenkins. The frontend uses Orval to generate `web-app/src/generated/playsay-api.ts` from that contract before lint/build/test.

The `DB migrate` stage runs after `OpenAPI contract` and before image builds for deployable branches. It uses `liquibase/liquibase:5.0.3`, downloads the pinned PostgreSQL JDBC driver `42.7.8`, and applies `backend/api-gateway/src/main/resources/db/changelog/db.changelog-master.xml` to the dev application PostgreSQL database. The Jenkins agent reads `PLAYSAY_DB_JDBC_URL`, `PLAYSAY_DB_USERNAME`, and `PLAYSAY_DB_PASSWORD` from the Kubernetes secret `playsay-app-db` in the `jenkins` namespace. The Liquibase container must run as UID `1000` and GID `0`: UID `1000` lets Jenkins durable shell write temporary files in the shared workspace, while GID `0` lets the official image execute files under `/liquibase`; if `DB migrate` stays in progress with no console output or fails with `liquibase: Permission denied`, check this security context first. Keep `api-gateway` startup Liquibase disabled in Helm; migrations are controlled by Jenkins, not by service boot.

The `Sprint 5 UI smoke` stage runs after Jenkins updates dev image tags and `Wait for dev rollout` confirms that api-gateway, web-app, and collaboration-service are all on the current build label and ready in `playsay-dev`. It uses `mcr.microsoft.com/playwright:v1.56.1-noble`, installs only the matching `playwright` Node package into `/tmp`, reuses the browser binaries already in the image, and runs `scripts/smoke/sprint5-ui-smoke.mjs` against `https://online.play-and-say.ru`. The stage reads only the required demo passwords from the `keycloak-dev-users` secret in the `jenkins` namespace and sets `PLAY_SAY_SMOKE_FETCH_PASSWORDS=false`, so Jenkins never SSHes to the VPS or prints secret values. If this stage fails immediately with missing smoke secret env vars, refresh the Jenkins copy with `./scripts/sync-keycloak-dev-users-secret.sh`.

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
- Status: branch-aware auto-build for `develop` and `release/*` is configured through Generic Webhook Trigger. The job filter must remain `^refs/heads/(develop|release/.+) (?!0{40}$)[0-9a-f]{40}$` over `$GITHUB_REF $GITHUB_AFTER`.
- Secret: the current dev hook uses the Generic Webhook Trigger token in the URL. Before production use, replace it with a generated secret credential and configure the same secret/token in GitHub and Jenkins.

Jenkins first login:

```bash
ssh root@146.103.126.15 \
  "kubectl -n jenkins get secret jenkins -o jsonpath='{.data.jenkins-admin-password}' | base64 -d"
```

Jenkins URL:

```text
https://ops.play-and-say.ru:18443/jenkins/
```

Jenkins API checks require authentication. If local `kubectl` is not configured for the dev cluster, run the API check through SSH on the VPS and read the Jenkins admin credentials from the in-cluster secret without printing them:

```bash
ssh root@146.103.126.15 '
set -euo pipefail
JENKINS_URL="https://ops.play-and-say.ru:18443/jenkins"
JENKINS_JOB_NAME="playsay-platform-develop"
JENKINS_USER="$(kubectl -n jenkins get secret jenkins -o jsonpath="{.data.jenkins-admin-user}" | base64 -d)"
JENKINS_PASSWORD="$(kubectl -n jenkins get secret jenkins -o jsonpath="{.data.jenkins-admin-password}" | base64 -d)"
curl -k -g -fsS -u "$JENKINS_USER:$JENKINS_PASSWORD" \
  "$JENKINS_URL/job/$JENKINS_JOB_NAME/api/json?tree=builds[number,displayName,building,result,timestamp,url]{0,10}" |
  jq -r ".builds[] | \"#\\(.number) \\(.displayName) building=\\(.building) result=\\(.result)\""
'
```

Unauthenticated Jenkins API calls return a login redirect or `Authentication required`; that only means auth is missing, not that the job is down. For POST requests such as job reconfiguration or manual `buildWithParameters`, also request a crumb from `/crumbIssuer/api/json` and send the returned cookie plus crumb header. Keep Jenkins passwords, crumbs, GitHub tokens, and kubeconfigs out of logs and chat.

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
- login theme: `playsay`, stored in Git under `helm-charts/keycloak/themes/playsay` and mounted into Keycloak by the wrapper chart as a ConfigMap volume. Theme caches are disabled in dev. The logo is copied from `play-and-say.ru`. On mobile, the login form is ordered before the brand copy so username/password are visible without scrolling. All custom visible theme texts live in Keycloak message bundles for `ru`, `en`, `de`, and `fr`; frontend `ui_locales` and the Keycloak language dropdown must change both `<html lang>` and the visible copy.
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
- public web client `playsay-web` with Authorization Code + PKCE redirects for `https://online.play-and-say.ru`, local Vite dev origins `http://localhost:5173`, `http://localhost:5174`, `http://127.0.0.1:5173`, `http://127.0.0.1:5174`, and local preview origins `http://localhost:4173`, `http://127.0.0.1:4173`;
- backend client `playsay-api`;
- dev users `student-demo`, `student-demo-2`, `student-demo-3`, `student-demo-4`, `teacher-demo`, and `admin-demo`.

Demo passwords are generated once and stored in the Kubernetes secret `keycloak-dev-users` in the `keycloak` namespace. Re-running the script adds any missing password keys without rotating existing ones. `configure-keycloak-dev.sh` also syncs the three passwords required by Jenkins Sprint 5 UI smoke into a same-named secret in the `jenkins` namespace through `scripts/sync-keycloak-dev-users-secret.sh`; run that sync script directly if the `jenkins` namespace is recreated. Do not commit or print those values in shared logs. Retrieve a password only when needed, replacing the jsonpath key with the needed user:

```bash
ssh root@146.103.126.15 \
  "kubectl -n keycloak get secret keycloak-dev-users -o jsonpath='{.data.student-demo-password}' | base64 -d"
```

Check status:

```bash
ssh root@146.103.126.15 "kubectl -n argocd get app keycloak && kubectl -n keycloak get pods,pvc,svc"
```

Get the admin password only when needed:

```bash
ssh root@146.103.126.15 \
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
- `GET/POST /schedule/lessons`, `GET/PUT/DELETE /schedule/lessons/{lessonId}` manage scheduled lessons.
- `POST /schedule/lessons/{lessonId}/room-token` returns a short-lived LiveKit join token for a teacher/admin or a student participant.

Sprint 2 moved UserProfile data out of the in-memory dev store into application PostgreSQL. Keycloak remains the source of identity and roles. `api-gateway` now stores the app-level profile fields in `app_user` and refreshes username, email, name, and roles from each JWT access.

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
    modelKey: model
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

The dev Helm values enable OpenAI through Kubernetes secret `playsay-openai` in namespace `playsay-dev`. The secret must contain exactly these data keys:

- `api-key`: OpenAI Platform API key.
- `model`: default material draft model, currently `gpt-5.4-mini`.

Create or update the secret from a local terminal without printing the key:

```bash
ssh -tt root@146.103.126.15 'bash -lc '"'"'
set -euo pipefail

read -rsp "OpenAI API key: " OPENAI_API_KEY
echo

KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n playsay-dev create secret generic playsay-openai \
  --from-literal=api-key="$OPENAI_API_KEY" \
  --from-literal=model="gpt-5.4-mini" \
  --dry-run=client -o yaml | KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl apply -f -

unset OPENAI_API_KEY

KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n playsay-dev get secret playsay-openai
'"'"''
```

Expected verification output is `playsay-openai` with `DATA` equal to `2`. Do not decode or paste the secret values into chat, Git, logs, or docs. To verify only key names without decoding values:

```bash
ssh root@146.103.126.15 \
  'KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n playsay-dev get secret playsay-openai -o jsonpath="{.data}"'
```

After deploying the chart, verify that the pod references the secret without printing values:

```bash
ssh root@146.103.126.15 \
  'KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n playsay-dev get deploy api-gateway -o jsonpath="{.spec.template.spec.containers[0].env[?(@.name==\"PLAYSAY_AI_PROVIDER\")].value}"'
```

Expected value for dev with real generation enabled: `openai`.

## Web App Auth

`web-app` uses Keycloak Authorization Code + PKCE with the public client `playsay-web`.

Dev defaults:

```text
VITE_AUTH_ISSUER=https://ops.play-and-say.ru:18443/keycloak/realms/playsay
VITE_AUTH_CLIENT_ID=playsay-web
VITE_AUTH_REDIRECT_PATH=/auth/callback
```

The production container serves the SPA through nginx. Requests to `/api/*` are proxied inside the `playsay-dev` namespace to `http://api-gateway/*`, so the browser calls the backend through the same origin `https://online.play-and-say.ru`. The same path also carries WebSocket classroom sync at `/api/ws/lessons`; both the host nginx `online.play-and-say.ru` location and the web-app container nginx must pass `Upgrade` and `Connection` headers. The frontend calls `/api/me`, `/api/users/me/profile`, schedule endpoints, the LiveKit room-token endpoint, and `/api/ws/lessons` through this same-origin route.

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

Automated Sprint 5 UI smoke lives in `playsay-platform`. Jenkins runs it automatically after updating dev image tags, using the Playwright smoke container and the `keycloak-dev-users` secret in the `jenkins` namespace. The same script can still be run locally with the agent Playwright install without adding Playwright to the app dependencies:

```bash
cd /Users/evgeniymednov/Documents/Projects/Play\&Say/playsay-platform
PLAYWRIGHT_PACKAGE_DIR=/Users/evgeniymednov/.codex/tools/playwright \
  ./scripts/smoke/sprint5-ui-smoke.mjs
```

The script obtains Keycloak Authorization Code + PKCE tokens as `teacher-demo`, `student-demo`, and `student-demo-2`, reads demo passwords from env vars in Jenkins or from the dev `keycloak-dev-users` Kubernetes secret over SSH during local runs without printing them, creates a temporary published private material, active group lesson, and required collaboration documents through the API for deterministic setup, then drives real browser classroom pages for teacher + two students. It verifies individual documents, teacher supervision/edit, group document sync, colored material-scoped cursors clipped to the lesson material surface, annotation sync after scroll/resize/reload, and finalize creating a normal material submission. The script deletes the temporary lesson and archives the temporary material at the end.

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

Sync that secret into Kubernetes before the LiveKit chart with TURN enabled syncs:

```bash
./scripts/sync-coturn-secret.sh
```

`deploy-cluster-addons.sh` also runs the coturn sync script automatically. Do not print the file content. If UFW or another firewall is later enabled, allow `3478/tcp`, `3478/udp`, and `49160:49200/udp`.

The LiveKit chart sends webhooks to the internal api-gateway service:

```text
http://api-gateway.playsay-dev.svc.cluster.local/livekit/webhook
```

`api-gateway` handles `participant_joined` and `participant_left` by updating `lesson_participant.joined_at`, `left_at`, `attendance_status`, and setting the lesson to `IN_PROGRESS` on first join. The endpoint is hidden from the public OpenAPI contract and must not be called manually without a valid LiveKit webhook signature.

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

For a functional check, log in to `https://online.play-and-say.ru` as a teacher, create or reuse a scheduled lesson with `student-demo`, `student-demo-2`, and `student-demo-3` as participants, click "Войти в урок", then log in as those students in separate browser profiles and click the same button. Browser camera/microphone permissions must be allowed. The classroom URL should become `/lessons/{lessonId}/classroom`, the page should not scroll, and the LiveKit controls should expose microphone/camera only, without screen share.

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
