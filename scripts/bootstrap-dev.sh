#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANSIBLE_DIR="$ROOT_DIR/ansible"

ENVIRONMENT="dev"
SERVER_IP=""
DOMAIN="dev.example.com"
LETSENCRYPT_EMAIL="admin@example.com"
SSH_KEY=""
HEADLAMP_HOST=""
OPS_HOST=""
OPS_PORT="18443"
OPS_ALLOW_CIDRS=""
OPS_TLS_MODE="auto"
ONLINE_HOST=""
ONLINE_NODEPORT_HTTP="32083"
ONLINE_TLS_MODE="auto"
LIVEKIT_SIGNALING_HOST_PORT="7880"
REMOTE_USER="root"
REMOTE_BOOTSTRAP_DIR="/tmp/playsay-infra-bootstrap"
INSTALL_JENKINS="true"
MODE="coexist"
CONFIGURE_HOST_NGINX="true"

usage() {
  cat <<USAGE
Usage:
  $0 --ip <server-ip> [options]

Options:
  --env <name>              Environment name. Default: dev
  --ip <server-ip>          Public IPv4 address of the already-created VPS
  --domain <domain>         Dev base domain. Default: dev.example.com
  --email <email>           Let's Encrypt email. Default: admin@example.com
  --headlamp-host <host>    Kubernetes UI host. Default: headlamp.<domain>
  --ops-host <host>         Shared ops UI host. Default: ops.<domain>
  --ops-port <port>         Shared ops UI public port. Default: 18443
  --ops-allow-cidrs <list>  Optional comma-separated allowlist CIDRs for ops UI
  --ops-tls-mode <mode>     auto, self-signed, existing, or off. Default: auto
  --online-host <host>      Product SPA host. Default: online.<domain>
  --online-nodeport <port>  Product SPA local NodePort. Default: 32083
  --online-tls-mode <mode>  auto, self-signed, existing, or off. Default: auto
  --livekit-signaling-port <port> Local LiveKit signaling port. Default: 7880
  --ssh-key <path>          Optional SSH key path. Default: use normal ssh config/agent
  --no-jenkins              Do not install Jenkins controller
  --mode <mode>             coexist or fresh. Default: coexist
  --no-host-nginx           Do not create nginx proxy config for ArgoCD/Headlamp

What it does:
  1. Uses normal ssh config/agent, or --ssh-key if provided.
  2. Verifies key-based root SSH access.
  3. Writes the dev Ansible inventory.
  4. Runs Ansible bootstrap: baseline packages, k3s, node exporter.
  5. Copies this infra repository to the VPS.
  6. Installs cluster add-ons on the VPS using /etc/rancher/k3s/k3s.yaml.

coexist mode avoids changing SSH hardening, UFW, existing nginx server blocks,
and does not install Docker unless explicitly switched to fresh mode.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      ENVIRONMENT="$2"
      shift 2
      ;;
    --ip)
      SERVER_IP="$2"
      shift 2
      ;;
    --domain)
      DOMAIN="$2"
      shift 2
      ;;
    --email)
      LETSENCRYPT_EMAIL="$2"
      shift 2
      ;;
    --headlamp-host)
      HEADLAMP_HOST="$2"
      shift 2
      ;;
    --ops-host)
      OPS_HOST="$2"
      shift 2
      ;;
    --ops-port)
      OPS_PORT="$2"
      shift 2
      ;;
    --ops-allow-cidrs)
      OPS_ALLOW_CIDRS="$2"
      shift 2
      ;;
    --ops-tls-mode)
      OPS_TLS_MODE="$2"
      shift 2
      ;;
    --online-host)
      ONLINE_HOST="$2"
      shift 2
      ;;
    --online-nodeport)
      ONLINE_NODEPORT_HTTP="$2"
      shift 2
      ;;
    --online-tls-mode)
      ONLINE_TLS_MODE="$2"
      shift 2
      ;;
    --livekit-signaling-port)
      LIVEKIT_SIGNALING_HOST_PORT="$2"
      shift 2
      ;;
    --ssh-key)
      SSH_KEY="${2/#\~/$HOME}"
      shift 2
      ;;
    --no-jenkins)
      INSTALL_JENKINS="false"
      shift
      ;;
    --mode)
      MODE="$2"
      shift 2
      ;;
    --no-host-nginx)
      CONFIGURE_HOST_NGINX="false"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$SERVER_IP" ]]; then
  echo "--ip is required" >&2
  usage
  exit 1
fi

if [[ "$MODE" != "coexist" && "$MODE" != "fresh" ]]; then
  echo "--mode must be coexist or fresh" >&2
  exit 1
fi

if [[ -z "$HEADLAMP_HOST" ]]; then
  HEADLAMP_HOST="headlamp.$DOMAIN"
fi

if [[ -z "$OPS_HOST" ]]; then
  OPS_HOST="ops.$DOMAIN"
fi

if [[ -z "$ONLINE_HOST" ]]; then
  ONLINE_HOST="online.$DOMAIN"
fi

if [[ "$OPS_TLS_MODE" != "auto" && "$OPS_TLS_MODE" != "self-signed" && "$OPS_TLS_MODE" != "existing" && "$OPS_TLS_MODE" != "off" ]]; then
  echo "--ops-tls-mode must be auto, self-signed, existing, or off" >&2
  exit 1
fi

if [[ "$ONLINE_TLS_MODE" != "auto" && "$ONLINE_TLS_MODE" != "self-signed" && "$ONLINE_TLS_MODE" != "existing" && "$ONLINE_TLS_MODE" != "off" ]]; then
  echo "--online-tls-mode must be auto, self-signed, existing, or off" >&2
  exit 1
fi

require() {
  command -v "$1" >/dev/null || { echo "$1 is required" >&2; exit 1; }
}

require ssh
require rsync
require ansible-playbook

SSH_ARGS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new)
RSYNC_SSH="ssh -o StrictHostKeyChecking=accept-new"
ANSIBLE_KEY_LINE=""
LOCAL_PUBLIC_KEY_VAR=()

if [[ -n "$SSH_KEY" ]]; then
  require ssh-keygen
  mkdir -p "$(dirname "$SSH_KEY")"

  if [[ ! -f "$SSH_KEY" ]]; then
    ssh-keygen -t ed25519 -f "$SSH_KEY" -C "playsay-$ENVIRONMENT" -N ""
  fi

  if [[ ! -f "$SSH_KEY.pub" ]]; then
    ssh-keygen -y -f "$SSH_KEY" > "$SSH_KEY.pub"
  fi

  SSH_ARGS=(-i "$SSH_KEY" "${SSH_ARGS[@]}")
  RSYNC_SSH="ssh -i $SSH_KEY -o StrictHostKeyChecking=accept-new"
  ANSIBLE_KEY_LINE="          ansible_ssh_private_key_file: $SSH_KEY"
  LOCAL_PUBLIC_KEY_VAR=(--extra-vars "local_public_key_file=$SSH_KEY.pub")
fi

echo "Checking SSH access to $REMOTE_USER@$SERVER_IP."
ssh "${SSH_ARGS[@]}" "$REMOTE_USER@$SERVER_IP" "true"

if [[ "$MODE" == "fresh" ]]; then
  MANAGE_SSH_HARDENING="true"
  MANAGE_UFW="true"
  INSTALL_DOCKER="true"
else
  MANAGE_SSH_HARDENING="false"
  MANAGE_UFW="false"
  INSTALL_DOCKER="false"
fi

INVENTORY_DIR="$ANSIBLE_DIR/inventories/$ENVIRONMENT"
INVENTORY="$INVENTORY_DIR/hosts.yaml"
mkdir -p "$INVENTORY_DIR"

cat > "$INVENTORY" <<YAML
all:
  children:
    $ENVIRONMENT:
      hosts:
        playsay-$ENVIRONMENT-1:
          ansible_host: $SERVER_IP
          ansible_user: root
$ANSIBLE_KEY_LINE
          public_ipv4: $SERVER_IP
          dev_domain: $DOMAIN
          manage_ssh_hardening: $MANAGE_SSH_HARDENING
          manage_ufw: $MANAGE_UFW
          install_docker: $INSTALL_DOCKER
YAML

if command -v ansible-galaxy >/dev/null; then
  ansible-galaxy collection install -r "$ANSIBLE_DIR/requirements.yaml"
fi

echo "Bootstrapping server with Ansible."
(
  cd "$ANSIBLE_DIR"
  if [[ -n "$SSH_KEY" ]]; then
    ansible-playbook \
      -i "$INVENTORY" \
      "$ANSIBLE_DIR/playbooks/bootstrap.yaml" \
      --extra-vars "@$ANSIBLE_DIR/group_vars/$ENVIRONMENT.yaml" \
      --extra-vars "local_public_key_file=$SSH_KEY.pub"
  else
    ansible-playbook \
      -i "$INVENTORY" \
      "$ANSIBLE_DIR/playbooks/bootstrap.yaml" \
      --extra-vars "@$ANSIBLE_DIR/group_vars/$ENVIRONMENT.yaml"
  fi
)

echo "Copying infrastructure scripts to VPS."
rsync -az --delete \
  --exclude ".git" \
  --exclude "*.retry" \
  --exclude "*.log" \
  -e "$RSYNC_SSH" \
  "$ROOT_DIR/" "$REMOTE_USER@$SERVER_IP:$REMOTE_BOOTSTRAP_DIR/"

quote() {
  printf "%q" "$1"
}

REMOTE_CMD="cd $(quote "$REMOTE_BOOTSTRAP_DIR") && PLAYSAY_DOMAIN=$(quote "$DOMAIN") LETSENCRYPT_EMAIL=$(quote "$LETSENCRYPT_EMAIL") HEADLAMP_HOST=$(quote "$HEADLAMP_HOST") OPS_HOST=$(quote "$OPS_HOST") OPS_PORT=$(quote "$OPS_PORT") OPS_ALLOW_CIDRS=$(quote "$OPS_ALLOW_CIDRS") OPS_TLS_MODE=$(quote "$OPS_TLS_MODE") ONLINE_HOST=$(quote "$ONLINE_HOST") ONLINE_NODEPORT_HTTP=$(quote "$ONLINE_NODEPORT_HTTP") ONLINE_TLS_MODE=$(quote "$ONLINE_TLS_MODE") LIVEKIT_SIGNALING_HOST_PORT=$(quote "$LIVEKIT_SIGNALING_HOST_PORT") INSTALL_JENKINS=$(quote "$INSTALL_JENKINS") CONFIGURE_HOST_NGINX=$(quote "$CONFIGURE_HOST_NGINX") ./scripts/deploy-cluster-addons.sh $(quote "$ENVIRONMENT")"

echo "Installing Kubernetes add-ons directly on the VPS."
ssh "${SSH_ARGS[@]}" "$REMOTE_USER@$SERVER_IP" "$REMOTE_CMD"

if [[ -n "$SSH_KEY" ]]; then
  SCP_KUBECONFIG_CMD="scp -i $SSH_KEY playsay@$SERVER_IP:/home/playsay/.kube/config ~/.kube/configs/playsay-$ENVIRONMENT"
else
  SCP_KUBECONFIG_CMD="scp playsay@$SERVER_IP:/home/playsay/.kube/config ~/.kube/configs/playsay-$ENVIRONMENT"
fi

cat <<DONE

Play&Say dev infrastructure bootstrap is complete.

Server: $SERVER_IP
Domain: $DOMAIN

Optional local kubeconfig for diagnostics:
  mkdir -p ~/.kube/configs
  $SCP_KUBECONFIG_CMD
  export KUBECONFIG=~/.kube/configs/playsay-$ENVIRONMENT
  kubectl get pods -A

Ops UI, if DNS points to this server and the port is open:
  https://$OPS_HOST:$OPS_PORT
  https://$OPS_HOST:$OPS_PORT/argocd/
  https://$OPS_HOST:$OPS_PORT/headlamp/
  https://$OPS_HOST:$OPS_PORT/jenkins/

Online app, after web-app image is built and ArgoCD syncs:
  https://$ONLINE_HOST

Headlamp dev-admin token:
  ssh root@$SERVER_IP "kubectl -n headlamp get secret headlamp-admin-token -o jsonpath='{.data.token}' | base64 -d"
DONE
