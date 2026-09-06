#!/usr/bin/env python3
"""Local contract tests for the Honey School GeoIP updater and nginx policy."""

from __future__ import annotations

import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parents[1]


def render_updater(state: Path, token: Path, nginx_config: Path) -> str:
    templates = ROOT / "ansible/roles/honey-school-geoip/templates"
    rendered = (templates / "update-ipinfo-lite.sh.j2").read_text()
    replacements = {
        "{{ honey_school_geoip_state_directory | quote }}": shlex.quote(str(state)),
        "{{ honey_school_geoip_token_path | quote }}": shlex.quote(str(token)),
        "{{ honey_school_geoip_nginx_database_config | quote }}": shlex.quote(str(nginx_config)),
        "{{ honey_school_geoip_maximum_age_seconds }}": "2592000",
        "{{ honey_school_geoip_warning_age_seconds }}": "604800",
        "{{ honey_school_geoip_minimum_database_bytes }}": "32",
    }
    for expression, value in replacements.items():
        rendered = rendered.replace(expression, value)
    assert "{{" not in rendered
    return rendered


def install_stub(directory: Path, name: str, body: str) -> None:
    path = directory / name
    path.write_text("#!/bin/sh\nset -eu\n" + body)
    path.chmod(0o755)


def updater_case(download_succeeds: bool, token_value: str = "test1234567890") -> tuple[subprocess.CompletedProcess[str], Path, Path]:
    temporary = Path(tempfile.mkdtemp(prefix="honey-school-geoip-test-"))
    state = temporary / "state"
    state.mkdir()
    token = temporary / "token"
    token.write_text(token_value + "\n")
    token.chmod(0o600)
    nginx_config = temporary / "geoip.conf"
    nginx_config.write_text('map $host $honey_school_geo_country_code { default ""; }\n')
    updater = temporary / "updater"
    updater.write_text(render_updater(state, token, nginx_config))
    updater.chmod(0o755)
    binaries = temporary / "bin"
    binaries.mkdir()
    install_stub(binaries, "flock", "exit 0\n")
    install_stub(binaries, "chown", "exit 0\n")
    install_stub(binaries, "logger", "exit 0\n")
    install_stub(binaries, "nginx", "exit 0\n")
    install_stub(binaries, "systemctl", 'printf "%s\\n" "$*" >> "$TEST_SYSTEMCTL_LOG"\n')
    install_stub(
        binaries,
        "mmdblookup",
        'printf \'  "RU" <utf8_string>\\n\'\n',
    )
    if download_succeeds:
        install_stub(
            binaries,
            "curl",
            'output=""\nwhile [ "$#" -gt 0 ]; do\n'
            '  [ "$1" != "--output" ] || { shift; output=$1; }\n  shift\ndone\n'
            'dd if=/dev/zero of="$output" bs=64 count=1 2>/dev/null\n',
        )
    else:
        install_stub(binaries, "curl", "exit 22\n")
    env = os.environ.copy()
    env["PATH"] = f"{binaries}:{env['PATH']}"
    env["TEST_SYSTEMCTL_LOG"] = str(temporary / "systemctl.log")
    result = subprocess.run([str(updater)], text=True, capture_output=True, env=env)
    return result, state, nginx_config


def test_success() -> None:
    result, state, nginx_config = updater_case(True)
    assert result.returncode == 0, result.stderr
    assert result.stdout == ""
    assert (state / "ipinfo-lite.mmdb").stat().st_size == 64
    assert "country_code" in nginx_config.read_text()
    metrics = (state / "update.prom").read_text()
    assert "honey_school_geoip_database_fresh 1" in metrics
    assert "honey_school_geoip_update_failures_total 0" in metrics


def test_invalid_token_does_not_activate_database() -> None:
    for value in ("", 'bad"token', "bad\ntoken", "bad&token"):
        result, state, nginx_config = updater_case(True, value)
        assert result.returncode != 0
        assert not (state / "ipinfo-lite.mmdb").exists()
        assert "geoip2" not in nginx_config.read_text()
        assert not result.stdout
        if value:
            assert value not in result.stderr
        else:
            assert not result.stderr


def test_failed_stale_update_preserves_database_and_disables_classification() -> None:
    result, state, nginx_config = updater_case(False)
    active = state / "ipinfo-lite.mmdb"
    active.write_bytes(b"last-good")
    (state / "last-success-epoch").write_text(str(int(time.time()) - 2_592_001))
    result, state, nginx_config = rerun_failed_case(result, state, nginx_config)
    assert result.returncode != 0
    assert active.read_bytes() == b"last-good"
    assert "geoip2" not in nginx_config.read_text()
    metrics = (state / "update.prom").read_text()
    assert "honey_school_geoip_database_fresh 0" in metrics
    assert "honey_school_geoip_database_age_warning 1" in metrics
    assert "honey_school_geoip_update_failures_total 1" in metrics


def rerun_failed_case(
    initial: subprocess.CompletedProcess[str], state: Path, nginx_config: Path
) -> tuple[subprocess.CompletedProcess[str], Path, Path]:
    # updater_case already exercised a missing download. Reset the persisted counter
    # so this assertion describes one scheduled attempt against an existing database.
    failure_count = state / "update-failures"
    failure_count.unlink(missing_ok=True)
    temporary = state.parent
    env = os.environ.copy()
    env["PATH"] = f"{temporary / 'bin'}:{env['PATH']}"
    env["TEST_SYSTEMCTL_LOG"] = str(temporary / "systemctl.log")
    result = subprocess.run([str(temporary / "updater")], text=True, capture_output=True, env=env)
    return result, state, nginx_config



def test_activation_failure_restores_database_and_freshness() -> None:
    for failure in ("nginx", "systemctl"):
        result, state, config = updater_case(True)
        assert result.returncode == 0
        active = state / "ipinfo-lite.mmdb"
        active.write_bytes(b"previous-valid-database")
        previous_config = config.read_bytes()
        stamp = str(int(time.time()) - 86400)
        (state / "last-success-epoch").write_text(stamp)
        install_stub(state.parent / "bin", failure, "exit 1\n")
        result, _, _ = rerun_failed_case(result, state, config)
        assert result.returncode != 0
        assert active.read_bytes() == b"previous-valid-database"
        assert config.read_bytes() == previous_config
        assert (state / "last-success-epoch").read_text() == stamp
        assert "honey_school_geoip_update_failures_total 1" in (state / "update.prom").read_text()


def test_explicit_rollback_preserves_original_age_without_download() -> None:
    result, state, config = updater_case(True)
    assert result.returncode == 0
    stamp = str(int(time.time()) - 86400)
    (state / "ipinfo-lite.last-good.mmdb").write_bytes(b"old-valid-database" * 4)
    (state / "last-good-epoch").write_text(stamp)
    install_stub(state.parent / "bin", "curl", "exit 99\n")
    env = os.environ.copy()
    env["PATH"] = f"{state.parent / 'bin'}:{env['PATH']}"
    env["TEST_SYSTEMCTL_LOG"] = str(state.parent / "systemctl.log")
    result = subprocess.run([str(state.parent / "updater"), "--rollback-last-good"], env=env, capture_output=True)
    assert result.returncode == 0
    assert (state / "ipinfo-lite.mmdb").read_bytes() == b"old-valid-database" * 4
    assert (state / "last-success-epoch").read_text().strip() == stamp


def redirect_decision(country: str, enabled: bool, direct_peer: bool, method: str, sec_fetch_mode: str, accept: str, path: str, upgrade: str) -> bool:
    navigation = method in {"GET", "HEAD"} and (sec_fetch_mode == "navigate" or (not sec_fetch_mode and "text/html" in accept))
    excluded = path.startswith("/.well-known/acme-challenge/") or any(
        path == prefix or path.startswith(prefix + "/") or path.startswith(prefix + "?")
        for prefix in ("/api", "/auth", "/keycloak", "/livekit", "/collab", "/ws")
    )
    return country == "RU" and enabled and direct_peer and navigation and not excluded and not upgrade


def test_redirect_matrix() -> None:
    base = dict(country="RU", enabled=True, direct_peer=True, method="GET", sec_fetch_mode="navigate", accept="text/html", path="/lessons/one?invite=x", upgrade="")
    assert redirect_decision(**base)
    assert redirect_decision(**{**base, "sec_fetch_mode": "", "accept": "text/html"})
    for change in (
        {"country": "DE"}, {"country": ""}, {"enabled": False}, {"direct_peer": False},
        {"method": "POST"}, {"path": "/api/lessons"}, {"path": "/auth/callback?code=hidden"},
        {"path": "/livekit"}, {"upgrade": "websocket"},
    ):
        assert not redirect_decision(**{**base, **change}), change


def test_static_nginx_contract() -> None:
    template = (ROOT / "ansible/roles/edge-proxy/templates/playsay-honey.conf.j2").read_text()
    policy = (ROOT / "ansible/roles/honey-school-geoip/templates/browser-entry-policy.conf.j2").read_text()
    assert "honey_school_geoip_redirect_prod_enabled" in policy
    assert "honey_school_geoip_redirect_dev_enabled" in policy
    assert '"RU:1:1:1:0:1" 1;' in policy
    assert "94.102.89.213" not in template
    assert "private, no-store" in (
        ROOT / "ansible/roles/honey-school-geoip/tasks/main.yaml"
    ).read_text()
    assert template.count("honey-school-browser-entry.conf") == 5
    for excluded in ("api", "auth", "keycloak", "livekit", "collab", "ws"):
        assert excluded in policy


if __name__ == "__main__":
    test_success()
    test_explicit_rollback_preserves_original_age_without_download()
    test_activation_failure_restores_database_and_freshness()
    test_invalid_token_does_not_activate_database()
    test_failed_stale_update_preserves_database_and_disables_classification()
    test_redirect_matrix()
    test_static_nginx_contract()
    print("Honey School GeoIP tests passed")
