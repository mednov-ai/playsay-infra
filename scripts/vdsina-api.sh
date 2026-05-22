#!/usr/bin/env bash
set -euo pipefail

API_BASE="${VDSINA_API_BASE:-https://userapi.vdsina.ru/v1}"
TOKEN="${VDSINA_API_TOKEN:-}"

if [[ -z "$TOKEN" ]]; then
  echo "VDSINA_API_TOKEN is required" >&2
  exit 1
fi

request() {
  local method="$1"
  local path="$2"
  local body="${3:-}"

  if [[ -n "$body" ]]; then
    curl -fsS -X "$method" "$API_BASE$path" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      --data "$body"
  else
    curl -fsS -X "$method" "$API_BASE$path" \
      -H "Authorization: Bearer $TOKEN"
  fi
}

case "${1:-}" in
  list)
    request GET "/server"
    ;;
  get)
    [[ -n "${2:-}" ]] || { echo "Usage: $0 get <server-id>" >&2; exit 1; }
    request GET "/server/$2"
    ;;
  delete)
    [[ -n "${2:-}" ]] || { echo "Usage: $0 delete <server-id>" >&2; exit 1; }
    request DELETE "/server/$2"
    ;;
  create)
    [[ -n "${2:-}" ]] || { echo "Usage: $0 create <payload.json>" >&2; exit 1; }
    request POST "/server" "@$2"
    ;;
  *)
    cat <<USAGE
Usage:
  VDSINA_API_TOKEN=... $0 list
  VDSINA_API_TOKEN=... $0 get <server-id>
  VDSINA_API_TOKEN=... $0 create <payload.json>
  VDSINA_API_TOKEN=... $0 delete <server-id>

This wrapper is intentionally thin. Validate payload fields against the current
VDSina API documentation before using create/delete in a real account.
USAGE
    exit 1
    ;;
esac

