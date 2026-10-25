#!/bin/sh
set -eu
usage() {
  echo "Usage: $0 --syntax|--check|--apply --inventory PATH --owner ax41|selectel|prod|dev [--component policy|counters|control|recovery] [--enable-execution]" >&2
  exit 2
}
mode= inventory= owner= component=policy execution=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --syntax|--check|--apply) [ -z "$mode" ] || usage; mode=$1; shift ;;
    --enable-execution) execution=true; shift ;;
    --inventory) [ "$#" -ge 2 ] || usage; inventory=$2; shift 2 ;;
    --component) [ "$#" -ge 2 ] || usage; component=$2; shift 2 ;;
    --owner) [ "$#" -ge 2 ] || usage; owner=$2; shift 2 ;;
    *) usage ;;
  esac
done
[ -n "$mode" ] || usage
case "$owner" in ax41) host_group=ax41_hosts ;; selectel) host_group=rf_edges ;; prod) host_group=playsay-prod ;; dev) host_group=playsay-dev ;; *) usage ;; esac
repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"
export ANSIBLE_CONFIG="$repo_root/ansible/ansible.cfg"
playbook="$repo_root/ansible/playbooks/host-maintenance.yaml"
case "$component" in
  policy) case "$owner" in ax41|selectel) ;; *) usage ;; esac ;;
  counters) [ "$owner" = selectel ] || usage; playbook="$repo_root/ansible/playbooks/rf-nic-observability.yaml" ;;
  recovery) [ "$owner" = ax41 ] || usage; host_group="ax41_hosts:rf_edges"; playbook="$repo_root/ansible/playbooks/host-maintenance-recovery.yaml" ;;
  control) playbook="$repo_root/ansible/playbooks/host-maintenance-control.yaml" ;;
  *) usage ;;
esac
[ "$execution" = false ] || [ "$component" = control ] || usage
if [ "$mode" = --syntax ]; then
  exec ansible-playbook -i localhost, "$playbook" --syntax-check
fi
[ -n "$inventory" ] && [ -f "$inventory" ] || usage
if [ "$component" = control ]; then
  [ -n "${PLAYSAY_MAINTENANCE_KEYS_DIR:-}" ] && [ -d "$PLAYSAY_MAINTENANCE_KEYS_DIR" ] || {
    echo "Protected role credential directory required." >&2; exit 2;
  }
fi
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
  exec ansible-playbook -i "$inventory" "$playbook" --limit "$host_group" -e "maintenance_execution_enabled=$execution"
fi
exec ansible-playbook -i "$inventory" "$playbook" --limit "$host_group" --check --diff -e "maintenance_execution_enabled=$execution"
