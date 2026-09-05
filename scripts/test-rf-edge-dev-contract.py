#!/usr/bin/env python3
"""Static fail-closed checks for the isolated RF development contour."""

from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[1]


def section(text: str, start: str, end: str) -> str:
    return text.split(start, 1)[1].split(end, 1)[0]


def main() -> None:
    variables = (ROOT / "ansible/group_vars/rf_edges.yaml").read_text()
    production = section(variables, "rf_edge_production_routes:", "rf_edge_development_routes:")
    development = section(variables, "rf_edge_development_routes:", "rf_edge_routes:")
    assert "dev." not in production
    for value in (
        "dev.online.honeyschool.ru",
        "dev.key.honeyschool.ru",
        "dev.ops.honey.school",
        "dev.online.honey.school",
        "dev.key.honey.school",
    ):
        assert value in development
    assert "online.honeyschool.ru\n" not in development.replace("dev.online.honeyschool.ru", "")
    assert 'rf_edge_routes: "{{ rf_edge_production_routes }}"' in variables
    assert "/etc/honeyschool/secrets/dev-turn-rest-secret" in variables
    assert "rf_edge_dev_media_relay_listening_port: 3479" in variables
    assert "rf_edge_dev_media_relay_tls_port: 5350" in variables
    assert "rf_edge_dev_media_relay_min_port: 49300" in variables
    assert "rf_edge_dev_media_relay_max_port: 49399" in variables

    playbook = (ROOT / "ansible/playbooks/rf-edge-dev.yaml").read_text()
    assert "rf_edge_production_routes + rf_edge_development_routes" not in playbook
    assert "honey-school-dev-ingress" in playbook
    assert "honey-school-dev-media-relay" in playbook
    assert "rf-edge-media-relay" not in playbook

    role = ROOT / "ansible/roles/honey-school-dev-media-relay"
    tasks = (role / "tasks/main.yaml").read_text()
    service = (role / "templates/honey-school-dev-turn.service.j2").read_text()
    firewall = (role / "templates/dev-turn-firewall.nft.j2").read_text()
    assert "systemctl is-active coturn" in tasks
    assert "restart coturn" not in tasks.lower()
    assert "User=honey-turn-dev" in service
    assert "CPUQuota=25%" in service
    assert "MemoryMax={{ rf_edge_dev_media_relay_memory_max }}" in service
    assert "meta skuid {{ honey_school_dev_turn_uid }}" in firewall
    assert "rf_edge_dev_media_relay_sfu_min_port" in firewall
    assert "rf_edge_dev_media_relay_sfu_max_port" in firewall

    wrapper = ROOT / "scripts/apply-rf-edge-dev-release.sh"
    result = subprocess.run(["sh", "-n", str(wrapper)], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    rejected = subprocess.run([str(wrapper), "short", "syntax"], capture_output=True, text=True)
    assert rejected.returncode == 2
    print("RF dev contract tests passed")


if __name__ == "__main__":
    main()

