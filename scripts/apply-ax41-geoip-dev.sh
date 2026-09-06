#!/bin/sh
set -eu
[ "$#" -eq 2 ] || { echo 'Usage: apply-ax41-geoip-dev.sh <40-character-commit> <syntax|check|apply>'; exit 2; }
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
[ "$1" = "$(git -C "$repo_root" rev-parse HEAD)" ] && [ "${#1}" -eq 40 ] || exit 2
[ -z "$(git -C "$repo_root" status --porcelain)" ] || { echo 'Refusing dirty checkout'; exit 2; }
export ANSIBLE_CONFIG="$repo_root/ansible/ansible.cfg"
case "$2" in
 syntax) mode=--syntax-check ;;
 check) mode=--check ;;
 apply) mode= ;;
 *) exit 2 ;;
esac
ansible-playbook -i '65.109.55.110,' -u root --private-key /Users/evgeniymednov/.ssh/play_and_say_vps_ed25519 "$repo_root/ansible/playbooks/ax41-geoip-dev.yaml" $mode --extra-vars '{"ansible_ssh_common_args":"-o IdentitiesOnly=yes"}'
