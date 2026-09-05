#!/bin/sh
set -eu

usage() {
  echo "Usage: $0 <40-character-infra-commit> <syntax|check|apply|bootstrap-check|bootstrap-apply|ingress-check|ingress-apply> [inventory]" >&2
  exit 2
}

[ "$#" -ge 2 ] && [ "$#" -le 3 ] || usage
expected_ref=$1
mode=$2
case "$expected_ref" in *[!0-9a-f]*|'') usage ;; esac
[ "${#expected_ref}" -eq 40 ] || usage
case "$mode" in syntax|check|apply|bootstrap-check|bootstrap-apply|ingress-check|ingress-apply) ;; *) usage ;; esac

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
actual_ref=$(git -C "$repo_root" rev-parse HEAD)
[ "$actual_ref" = "$expected_ref" ] || {
  echo "RF dev delivery requires the exact checked-out Git commit." >&2
  exit 1
}
[ -z "$(git -C "$repo_root" status --porcelain)" ] || {
  echo "RF dev delivery refuses a dirty checkout." >&2
  exit 1
}

inventory=${3:-$repo_root/ansible/inventories/rf-edge/hosts.yaml}
[ -f "$inventory" ] || {
  echo "RF dev inventory is missing." >&2
  exit 1
}

export ANSIBLE_CONFIG="$repo_root/ansible/ansible.cfg"
playbook=$repo_root/ansible/playbooks/rf-edge-dev.yaml
case "$mode" in
  bootstrap-check) exec ansible-playbook -i "$inventory" "$playbook" --tags rf-dev-ingress -e rf_edge_dev_bootstrap=true --check --diff ;;
  bootstrap-apply) exec ansible-playbook -i "$inventory" "$playbook" --tags rf-dev-ingress -e rf_edge_dev_bootstrap=true --diff ;;
  ingress-check) exec ansible-playbook -i "$inventory" "$playbook" --tags rf-dev-ingress --check --diff ;;
  ingress-apply) exec ansible-playbook -i "$inventory" "$playbook" --tags rf-dev-ingress --diff ;;
  syntax) exec ansible-playbook -i "$inventory" "$playbook" --syntax-check ;;
  check) exec ansible-playbook -i "$inventory" "$playbook" --check --diff ;;
  apply) exec ansible-playbook -i "$inventory" "$playbook" --diff ;;
esac
