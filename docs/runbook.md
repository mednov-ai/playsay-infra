# Play&Say Dev Runbook

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
- `https://online.play-and-say.ru`

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
- `ops.play-and-say.ru:18443` is reserved for dev infrastructure UI.

The login redirect is not only an nginx setting. When Keycloak is added, `online.play-and-say.ru` must also be added to the frontend app config and Keycloak client's allowed redirect URIs. The future `play-and-say.ru` login button should start Keycloak auth and return users to `online.play-and-say.ru`.

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
curl -k -I --resolve online.play-and-say.ru:443:146.103.126.15 https://online.play-and-say.ru/
```

Expected:

- Headlamp: `200 OK`;
- ArgoCD: `200 OK`;
- Jenkins: `403 Forbidden` or login redirect, which means Jenkins is alive and requires authentication.
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
- `github-infra-token`: username/password credential. Username is your GitHub username or org bot user; password is the GitHub token that can push to `playsay-infra`.

You may use one token for both credentials at MVP stage. Later, split them into narrower tokens.

Create credentials in Jenkins UI:

1. Open `https://ops.play-and-say.ru:18443/jenkins/`.
2. Go to `Manage Jenkins` -> `Credentials` -> `System` -> `Global credentials`.
3. Add `Username with password`.
4. For `ID`, enter `github-ghcr`; username is your GitHub username, password is the GitHub token.
5. Add the second `Username with password` credential with ID `github-infra-token`.

Do not store the token in `playsay-infra` or `playsay-platform`.

If you prefer CLI later, pass secrets only through a local untracked file such as `.env.local` or an interactive prompt.

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


Recommended GitHub webhook for `playsay-platform`:

- Payload URL: `https://ops.play-and-say.ru:18443/jenkins/github-webhook/`
- Content type: `application/json`
- Events: push and pull request
- Secret: generate a random value and configure the same secret in Jenkins GitHub settings.

Jenkins first login:

```bash
ssh root@146.103.126.15 \
  "kubectl -n jenkins get secret jenkins -o jsonpath='{.data.jenkins-admin-password}' | base64 -d"
```

Jenkins URL:

```text
https://ops.play-and-say.ru:18443/jenkins/
```

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

Use the VDSina panel:

1. Open the server configurator.
2. Increase resources:
   - Sprint 1: 4 vCPU / 8 GB / 100 GB
   - Sprint 4+: 8 vCPU / 16 GB / 150 GB if needed
3. Apply changes and let the server reboot.
4. Verify:

```bash
kubectl get nodes
kubectl get pods -A
```

## Disaster Recovery Drill

1. Create a fresh VPS.
2. Run `./scripts/bootstrap-dev.sh --ip <new-ip> --domain dev.example.com --email admin@example.com`.
3. Switch DNS to the new IP.
4. Let ArgoCD restore Git-defined applications.

Persistent databases are introduced later and must have a separate restore procedure before real data appears.

## Rollback

Application rollback is GitOps-based:

```bash
cd playsay-infra
git revert <bad-commit>
git push
```

ArgoCD will sync the reverted state.
