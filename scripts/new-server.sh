#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-dev}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANSIBLE_DIR="$ROOT_DIR/ansible"
INVENTORY="$ANSIBLE_DIR/inventories/$ENVIRONMENT/hosts.yaml"
PLAYBOOK="$ANSIBLE_DIR/playbooks/bootstrap.yaml"

usage() {
  cat <<USAGE
Usage: $0 <environment>

Bootstraps an already-created VPS into a Play&Say k3s environment.

Expected files:
  $INVENTORY

The VPS account, IP address, SSH key, DNS, and provider billing are managed by a human.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -f "$INVENTORY" ]]; then
  echo "Inventory not found: $INVENTORY" >&2
  echo "Copy ansible/inventories/$ENVIRONMENT/hosts.yaml.example to hosts.yaml and fill it in." >&2
  exit 1
fi

command -v ansible-playbook >/dev/null || { echo "ansible-playbook is required" >&2; exit 1; }

cd "$ANSIBLE_DIR"
ansible-playbook -i "$INVENTORY" "$PLAYBOOK" --extra-vars "@$ANSIBLE_DIR/group_vars/$ENVIRONMENT.yaml"

cat <<NEXT

Server bootstrap is complete.

Next:
1. Copy kubeconfig from the server:
   scp <admin-user>@<server-ip>:/home/<admin-user>/.kube/config ~/.kube/configs/playsay-$ENVIRONMENT

2. Export it locally:
   export KUBECONFIG=~/.kube/configs/playsay-$ENVIRONMENT

3. Install cluster add-ons:
   $ROOT_DIR/scripts/deploy-cluster-addons.sh $ENVIRONMENT
NEXT
