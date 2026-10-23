#!/bin/sh
set -eu
usage() {
  echo "Usage: $0 --syntax|--check|--apply --inventory PATH --owner ax41|selectel [--component policy|counters]" >&2
  exit 2
}
mode= inventory= owner= component=policy
while [ "$#" -gt 0 ]; do
  case "$1" in
    --syntax|--check|--apply) [ -z "$mode" ] || usage; mode=$1; shift ;;
    --inventory) [ "$#" -ge 2 ] || usage; inventory=$2; shift 2 ;;
    --component) [ "$#" -ge 2 ] || usage; component=$2; shift 2 ;;
    --owner) [ "$#" -ge 2 ] || usage; owner=$2; shift 2 ;;
    *) usage ;;
  esac
done
[ -n "$mode" ] || usage
case "$owner" in ax41) host_group=ax41_hosts ;; selectel) host_group=rf_edges ;; *) usage ;; esac
repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"
export ANSIBLE_CONFIG="$repo_root/ansible/ansible.cfg"
playbook="$repo_root/ansible/playbooks/host-maintenance.yaml"
case "$component" in
  policy) ;;
  counters) [ "$owner" = selectel ] || usage; playbook="$repo_root/ansible/playbooks/rf-nic-observability.yaml" ;;
  *) usage ;;
esac
if [ "$mode" = --syntax ]; then
  exec ansible-playbook -i localhost, "$playbook" --syntax-check
fi
[ -n "$inventory" ] && [ -f "$inventory" ] || usage
branch=$(git symbolic-ref --quiet --short HEAD || true)
printf '%s\n' "$branch" | grep -Eq '^release/[0-9]{2}\.[0-9]{3}\.[0-9]{2}$' || {
  echo "Host maintenance delivery requires a numeric release branch." >&2; exit 2;
}
[ -z "$(git status --porcelain)" ] || { echo "Clean release checkout required." >&2; exit 2; }
git fetch origin "refs/heads/$branch:refs/remotes/origin/$branch" >/dev/null
[ "$(git rev-parse HEAD)" = "$(git rev-parse "refs/remotes/origin/$branch")" ] || {
  echo "Published and local release must match." >&2; exit 2;
}
if [ "$mode" = --apply ]; then
  [ "${PLAYSAY_MAINTENANCE_APPROVED_RELEASE:-}" = "$branch" ] || {
    echo "Explicit host maintenance release approval required." >&2; exit 2;
  }
  exec ansible-playbook -i "$inventory" "$playbook" --limit "$host_group"
fi
exec ansible-playbook -i "$inventory" "$playbook" --limit "$host_group" --check --diff
