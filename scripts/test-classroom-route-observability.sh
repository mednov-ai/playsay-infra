#!/bin/sh
set -eu
repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
temporary_directory="$(mktemp -d)"
cleanup() { rm -rf -- "$temporary_directory"; }
trap cleanup EXIT HUP INT TERM

sh -n "$repo_root/scripts/collect-classroom-route-incident.sh"
sh -n "$repo_root/ansible/roles/rf-edge-media-relay/templates/probe-rf-to-ax41.sh.j2"
sh -n "$repo_root/ansible/roles/edge-proxy/templates/push-nginx-signal-metrics.sh.j2"
sh -n "$repo_root/scripts/apply-rf-edge-release.sh"
grep -q -- '--route-observability-only' "$repo_root/scripts/apply-rf-edge-release.sh"
grep -q 'classroom-route-observability' "$repo_root/ansible/roles/edge-proxy/tasks/main.yaml"
grep -q 'classroom-route-observability' "$repo_root/ansible/roles/rf-edge-proxy/tasks/main.yaml"
grep -q 'classroom-route-observability' "$repo_root/ansible/roles/rf-edge-media-relay/tasks/main.yaml"
"$repo_root/scripts/validate-rf-classroom-signaling-route.sh" --static >/dev/null
helm lint "$repo_root/helm-charts/monitoring-lite" -f "$repo_root/helm-charts/monitoring-lite/values-prod.yaml" >/dev/null
helm template monitoring-lite "$repo_root/helm-charts/monitoring-lite" -f "$repo_root/helm-charts/monitoring-lite/values-prod.yaml" >"$temporary_directory/monitoring.yaml"
grep -q 'scrape_interval: 5s' "$temporary_directory/monitoring.yaml"
grep -q 'phase="http".\+\[10s\].\+== 0' "$temporary_directory/monitoring.yaml"
grep -q 'phase="http".\+\[30s\].\+== 0' "$temporary_directory/monitoring.yaml"
grep -q 'PlaySayRfPathTelemetryStale' "$temporary_directory/monitoring.yaml"
grep -q 'PlaySayClassroomRouteFailureWithActiveParticipants' "$temporary_directory/monitoring.yaml"

for template in "$repo_root/ansible/roles/rf-edge-proxy/templates/playsay-honey-rf-edge.conf.j2" "$repo_root/ansible/roles/edge-proxy/tasks/main.yaml"; do
  format="$(grep 'log_format playsay_livekit_signal ' "$template")"
  printf '%s\n' "$format" | grep -q 'request_id='
  printf '%s\n' "$format" | grep -q 'upstream_connect_time='
  if printf '%s\n' "$format" | grep -Eq '(request_uri|remote_addr|http_cookie|http_authorization|user_agent)'; then
    echo "Sensitive nginx field in signaling log format: $template" >&2; exit 1
  fi
done
grep -q 'mmin +{{ rf_edge_observability_queue_retention_minutes }} -delete' "$repo_root/ansible/roles/rf-edge-media-relay/templates/probe-rf-to-ax41.sh.j2"

ansible localhost -c local -i localhost, -m ansible.builtin.template \
  -a "src=$repo_root/ansible/roles/rf-edge-media-relay/templates/collect-nginx-signal-metrics.py.j2 dest=$temporary_directory/rendered-collector.py" \
  -e "nginx_signal_metrics_log_path=$temporary_directory/signal.log" \
  -e "nginx_signal_metrics_state_directory=$temporary_directory/state" \
  -e "nginx_signal_metrics_output_path=$temporary_directory/metrics.prom" \
  -e 'nginx_signal_metrics_edge=test' >/dev/null
python3 -m py_compile "$temporary_directory/rendered-collector.py"

python3 - "$repo_root" "$temporary_directory" <<'PY'
import subprocess, sys
from pathlib import Path
root, tmp = Path(sys.argv[1]), Path(sys.argv[2])
log, state_dir, output = tmp/'signal.log', tmp/'state', tmp/'metrics.prom'
source=(root/'ansible/roles/rf-edge-media-relay/templates/collect-nginx-signal-metrics.py.j2').read_text()
for key,value in {'{{ nginx_signal_metrics_log_path }}':str(log),'{{ nginx_signal_metrics_state_directory }}':str(state_dir),'{{ nginx_signal_metrics_output_path }}':str(output),'{{ nginx_signal_metrics_edge }}':'test'}.items(): source=source.replace(key,value)
collector=tmp/'collector.py'; collector.write_text(source); compile(source,str(collector),'exec')
log.write_text('msec=1 request_id=0123456789abcdef0123456789abcdef status=101 request_time=1 upstream_connect_time=0.1 upstream_header_time=0.2 upstream_response_time=1 upstream_status=101\n' 'msec=2 request_id=fedcba9876543210fedcba9876543210 status=499 request_time=15 upstream_connect_time=- upstream_header_time=- upstream_response_time=- upstream_status=-\n' 'msec=3 request_id=0123456789abcdef0123456789abcdef status=502 request_time=1 upstream_connect_time=0.1 upstream_header_time=0.2 upstream_response_time=1 upstream_status=502\n')
subprocess.run([sys.executable,str(collector)],check=True); subprocess.run([sys.executable,str(collector)],check=True)
metrics=output.read_text()
for item in ('outcome="101"} 1','outcome="499"} 1','outcome="502"} 1','outcome="504"} 0','outcome="upstream_connect_failure"} 1'):
    assert item in metrics, (item,metrics)
state=(state_dir/'nginx-signal.state').read_text()
for forbidden in ('request_id','remote_addr','uri','token','identity'): assert forbidden not in state
PY

cat >"$temporary_directory/inventory.yaml" <<'YAML'
all:
  children:
    rf_edges:
      hosts:
        playsay-selectel-rf-edge: {ansible_host: 94.102.89.213, ansible_connection: local}
    ax41_hosts:
      hosts:
        ax41: {ansible_host: 65.109.55.110, ansible_connection: local}
YAML
ANSIBLE_ROLES_PATH="$repo_root/ansible/roles" ansible-playbook --syntax-check "$repo_root/ansible/playbooks/rf-edge.yaml" -i "$temporary_directory/inventory.yaml" >/dev/null
ANSIBLE_ROLES_PATH="$repo_root/ansible/roles" ansible-playbook --syntax-check "$repo_root/ansible/playbooks/ax41-host.yaml" -i "$temporary_directory/inventory.yaml" >/dev/null
(cd "$repo_root" && openspec validate add-selectel-classroom-media-relay --strict >/dev/null)
echo 'classroom route observability regression checks passed'
