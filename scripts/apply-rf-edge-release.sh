#!/bin/sh
set -eu

usage() {
  cat >&2 <<'EOF'
Usage: scripts/apply-rf-edge-release.sh --syntax|--check|--apply [--inventory PATH]

Runs the shared nginx/coturn Selectel RF edge playbook only from a clean,
pushed numeric release branch. --syntax is read-only and may run from a topic
branch. Review --check in a zero-allocation window;
--apply may restart coturn and also requires:
  PLAYSAY_RF_EDGE_APPROVED_RELEASE=release/NN.NNN.NN
EOF
  exit 2
}

mode=""
inventory_path="${PLAYSAY_RF_EDGE_INVENTORY:-}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --syntax|--check|--apply)
      [ -z "$mode" ] || usage
      mode="$1"
      shift
      ;;
    --inventory)
      [ "$#" -ge 2 ] || usage
      inventory_path="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

[ -n "$mode" ] || usage

repo_root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
export ANSIBLE_CONFIG="$repo_root/ansible/ansible.cfg"

for command_name in git ansible-playbook grep; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "Missing command on the trusted control node: $command_name" >&2
    exit 1
  }
done

if [ "$mode" = "--syntax" ]; then
  if [ -n "$inventory_path" ]; then
    case "$inventory_path" in
      /*) ;;
      *) inventory_path="$repo_root/$inventory_path" ;;
    esac
    [ -f "$inventory_path" ] || {
      echo "Selectel inventory does not exist: $inventory_path" >&2
      exit 2
    }
    exec ansible-playbook -i "$inventory_path" "$repo_root/ansible/playbooks/rf-edge.yaml" --syntax-check
  fi
  exec ansible-playbook "$repo_root/ansible/playbooks/rf-edge.yaml" --syntax-check
fi

release_branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
if ! printf '%s\n' "$release_branch" | grep -Eq '^release/[0-9]{2}\.[0-9]{3}\.[0-9]{2}$'; then
  echo "Selectel production may be reconciled only from a release/NN.NNN.NN branch; current branch: ${release_branch:-detached}." >&2
  exit 2
fi

if [ -n "$(git status --porcelain --untracked-files=normal)" ]; then
  echo "Selectel production requires a clean release worktree." >&2
  exit 2
fi

git fetch origin "refs/heads/${release_branch}:refs/remotes/origin/${release_branch}" >/dev/null
local_revision="$(git rev-parse HEAD)"
remote_revision="$(git rev-parse "refs/remotes/origin/${release_branch}")"
if [ "$local_revision" != "$remote_revision" ]; then
  echo "Local release HEAD does not match origin/${release_branch}." >&2
  exit 2
fi

[ -n "$inventory_path" ] || {
  echo "Set PLAYSAY_RF_EDGE_INVENTORY or pass --inventory with the ignored Selectel inventory path." >&2
  exit 2
}
case "$inventory_path" in
  /*) ;;
  *) inventory_path="$repo_root/$inventory_path" ;;
esac
[ -f "$inventory_path" ] || {
  echo "Selectel inventory does not exist: $inventory_path" >&2
  exit 2
}

if [ "$mode" = "--apply" ]; then
  if [ "${PLAYSAY_RF_EDGE_APPROVED_RELEASE:-}" != "$release_branch" ]; then
    echo "Set PLAYSAY_RF_EDGE_APPROVED_RELEASE=$release_branch for an approved production apply." >&2
    exit 2
  fi
  exec ansible-playbook \
    -i "$inventory_path" \
    "$repo_root/ansible/playbooks/rf-edge.yaml"
fi

exec ansible-playbook \
  -i "$inventory_path" \
  "$repo_root/ansible/playbooks/rf-edge.yaml" \
  --check \
  --diff
