#!/usr/bin/env python3
"""Regression tests for fail-closed RF TURN allocation metrics."""

from pathlib import Path
import os
import re
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
COLLECTOR_TEMPLATE = ROOT / "ansible/roles/rf-edge-media-relay/templates/collect-rf-edge-media-relay-metrics.sh.j2"
VALIDATOR_TEMPLATE = ROOT / "ansible/roles/rf-edge-media-relay/templates/validate-rf-edge-media-relay.py.j2"
TASKS = ROOT / "ansible/roles/rf-edge-media-relay/tasks/main.yaml"
RELEASE_WRAPPER = ROOT / "scripts/apply-rf-edge-release.sh"


def render_collector(metrics_directory: Path) -> str:
    rendered = COLLECTOR_TEMPLATE.read_text()
    replacements = {
        "{{ rf_edge_media_relay_metrics_directory }}": str(metrics_directory),
        "{{ rf_edge_media_relay_min_port }}": "49152",
        "{{ rf_edge_media_relay_max_port }}": "49251",
    }
    for source, target in replacements.items():
        rendered = rendered.replace(source, target)
    assert "{{" not in rendered
    return rendered


def metric_value(metrics: str, name: str) -> int:
    matches = re.findall(rf"^{re.escape(name)} ([0-9]+)$", metrics, re.MULTILINE)
    assert len(matches) == 1, (name, matches)
    return int(matches[0])


def main() -> None:
    collector_source = COLLECTOR_TEMPLATE.read_text()
    assert "$5" not in collector_source
    assert 'ss -H -lun "$relay_socket_filter"' in collector_source
    assert "sport >= :{{ rf_edge_media_relay_min_port }}" in collector_source
    assert "sport <= :{{ rf_edge_media_relay_max_port }}" in collector_source
    assert collector_source.index("relay_socket_rows=") < collector_source.index("} >\"$temporary_file\"")

    with tempfile.TemporaryDirectory(prefix="playsay-rf-metrics-") as temporary:
        temporary_path = Path(temporary)
        metrics_directory = temporary_path / "metrics"
        metrics_directory.mkdir()
        bin_directory = temporary_path / "bin"
        bin_directory.mkdir()
        collector = temporary_path / "collector.sh"
        collector.write_text(render_collector(metrics_directory))
        collector.chmod(0o755)

        ss_stub = bin_directory / "ss"
        ss_stub.write_text(
            "#!/bin/sh\n"
            "[ \"$#\" -eq 3 ] && [ \"$1\" = -H ] && [ \"$2\" = -lun ] && "
            "[ \"$3\" = 'sport >= :49152 and sport <= :49251' ] || exit 9\n"
            "[ \"${SS_FAIL:-0}\" = 0 ] || exit 7\n"
            "printf '%s\\n' "
            "'UNCONN 0 0 192.0.2.1:49152 0.0.0.0:*' "
            "'UNCONN 0 0 192.0.2.1:49153 0.0.0.0:*' "
            "'UNCONN 0 0 192.0.2.1:49154 0.0.0.0:*' "
            "'UNCONN 0 0 192.0.2.1:49155 0.0.0.0:*' "
            "'UNCONN 0 0 192.0.2.1:49156 0.0.0.0:*' "
            "'UNCONN 0 0 192.0.2.1:49251 0.0.0.0:*'\n"
        )
        ss_stub.chmod(0o755)

        systemctl_stub = bin_directory / "systemctl"
        systemctl_stub.write_text(
            "#!/bin/sh\n"
            "case \"$1\" in is-active) exit 0 ;; show) printf '0\\n' ;; *) exit 2 ;; esac\n"
        )
        systemctl_stub.chmod(0o755)
        journalctl_stub = bin_directory / "journalctl"
        journalctl_stub.write_text("#!/bin/sh\nexit 0\n")
        journalctl_stub.chmod(0o755)

        environment = {**os.environ, "PATH": f"{bin_directory}:{os.environ['PATH']}"}
        subprocess.run([str(collector)], check=True, env=environment, capture_output=True, text=True)
        output_file = metrics_directory / "rf_edge_media_relay.prom"
        successful_output = output_file.read_text()
        assert metric_value(successful_output, "playsay_rf_edge_media_relay_udp_sockets") == 6
        assert metric_value(successful_output, "playsay_rf_edge_media_relay_active_udp_allocations") == 6

        failed = subprocess.run(
            [str(collector)],
            check=False,
            env={**environment, "SS_FAIL": "1"},
            capture_output=True,
            text=True,
        )
        assert failed.returncode != 0
        assert "Unable to collect bounded relay UDP sockets." in failed.stderr
        assert output_file.read_text() == successful_output

    validator_source = VALIDATOR_TEMPLATE.read_text()
    rendered_validator = re.sub(r"{{[^}]+}}", "fixture", validator_source)
    compile(rendered_validator, str(VALIDATOR_TEMPLATE), "exec")
    assert "metric_integer" in validator_source
    assert "relay_socket_count" in validator_source
    assert "relay allocation metrics disagree with bounded UDP sockets" in validator_source
    assert TASKS.read_text().count("tags: [rf_edge_media_relay_monitoring]") == 2
    wrapper_source = RELEASE_WRAPPER.read_text()
    assert "--monitoring-only" in wrapper_source
    assert "--tags rf_edge_media_relay_monitoring" in wrapper_source
    print("RF edge media relay monitoring tests passed")


if __name__ == "__main__":
    main()
