# Play&Say Infrastructure

Infrastructure repository for Play&Say dev, staging, and production environments.

Sprint 0 focuses on the dev environment:

- Ubuntu 24.04 VPS prepared by Ansible
- k3s single-node cluster
- ingress-nginx, cert-manager, Sealed Secrets, ArgoCD
- Headlamp Kubernetes UI for dev cluster inspection
- Jenkins controller for CI
- hello-world deployment through Jenkins, GHCR, and ArgoCD

Real credentials, provider tokens, kubeconfigs, and sealed secret keys must not be committed.

## One-Command Dev Bootstrap

After the VPS is created manually and key-based root SSH works, run:

```bash
./scripts/bootstrap-dev.sh \
  --ip <server-ip> \
  --domain play-and-say.ru \
  --ops-host ops.play-and-say.ru \
  --ops-port 18443 \
  --email admin@example.com
```

By default the script runs in `coexist` mode for servers that already host other
services. It avoids changing SSH hardening, UFW, Docker, and existing nginx
server blocks. Kubernetes UIs are exposed through a separate nginx config file.

Infrastructure UI:

- `https://ops.play-and-say.ru:18443/headlamp/`
- `https://ops.play-and-say.ru:18443/argocd/`
- `https://ops.play-and-say.ru:18443/jenkins/`

## Manual Lower-Level Steps

If you want to run the phases separately:

1. Copy the inventory example and set the server IP:

   ```bash
   cp ansible/inventories/dev/hosts.yaml.example ansible/inventories/dev/hosts.yaml
   ```

2. Run server bootstrap:

   ```bash
   ./scripts/new-server.sh dev
   ```

3. Run cluster add-ons on a machine with kubeconfig, kubectl, and helm:

   ```bash
   ./scripts/deploy-cluster-addons.sh dev
   ```

See `docs/runbook.md` for the full procedure.
