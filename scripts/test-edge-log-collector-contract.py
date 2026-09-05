#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
config = (ROOT / "ansible/roles/honey-school-edge-logs/templates/fluent-bit.conf.j2").read_text()
privacy = (ROOT / "ansible/roles/honey-school-edge-logs/templates/privacy-filter.lua.j2").read_text()
values = (ROOT / "helm-charts/monitoring-lite/values-dev.yaml").read_text()
deployment = (ROOT / "helm-charts/monitoring-lite/templates/victoria-logs.yaml").read_text()
edge = (ROOT / "ansible/roles/edge-proxy/templates/playsay-honey.conf.j2").read_text()

assert "storage.total_limit_size {{ honey_school_edge_logs_buffer_limit }}" in config
assert "Mem_Buf_Limit   8M" in config
assert "storage.type    memory" in config
assert "[PARSER]" not in config
assert "Parsers_File" in config
assert "Retry_Limit              False" in config
assert "HTTP_User                ${HONEY_SCHOOL_LOG_INGEST_USERNAME}" in config
assert "HTTP_Passwd              ${HONEY_SCHOOL_LOG_INGEST_PASSWORD}" in config
assert "raw_ip" not in config and "request_uri" not in config
assert 'record["MESSAGE"]' in privacy
assert "return -1" in privacy and "return 2" in privacy
assert "victoriaLogs:\n  enabled: true" in values
assert "nodePort: 32086" in values
assert "retentionPeriod" in deployment and "resources:" in deployment
assert "auth_basic_user_file {{ route.victoria_logs_ingest_credentials_path }};" in edge
assert "client_max_body_size 4m;" in edge
print("edge log collector contract: PASS")
