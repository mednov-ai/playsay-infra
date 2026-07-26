#!/usr/bin/env bash
set -Eeuo pipefail

: "${EXPECTED_RELEASE:?EXPECTED_RELEASE is required}"
: "${BROWSER_TIMEOUT_SECONDS:=90}"

urls=(
  https://online.honey.school/
  https://key.honey.school/
  https://online.honeyschool.ru/
  https://key.honeyschool.ru/
)

for url in "${urls[@]}"; do
  status="$(curl -fsS -o /tmp/playsay-smoke-body -w '%{http_code}' "${url}")"
  [[ "${status}" == "200" ]] || {
    echo "${url} returned HTTP ${status}." >&2
    exit 1
  }
  grep -Eiq '<html|<!doctype' /tmp/playsay-smoke-body || {
    echo "${url} did not return an HTML application shell." >&2
    exit 1
  }
done

health="$(
  curl -fsS https://online.honey.school/api/actuator/health/readiness |
    jq -r '.status // empty'
)"
[[ "${health}" == "UP" ]] || {
  echo "Production API readiness is not UP." >&2
  exit 1
}

for url in "${urls[@]}"; do
  timeout "${BROWSER_TIMEOUT_SECONDS}" \
    chromium-browser \
      --headless \
      --disable-dev-shm-usage \
      --disable-gpu \
      --no-sandbox \
      --dump-dom \
      "${url}" > /tmp/playsay-browser-dom
  grep -Eiq '<html|<!doctype' /tmp/playsay-browser-dom || {
    echo "Headless Chromium did not render ${url}." >&2
    exit 1
  }
done

issuer="$(
  curl -fsS \
    https://ops.honey.school/keycloak/realms/playsay/.well-known/openid-configuration |
    jq -r '.issuer // empty'
)"
[[ "${issuer}" == "https://ops.honey.school/keycloak/realms/playsay" ]] || {
  echo "Canonical production issuer changed unexpectedly." >&2
  exit 1
}

echo "Production smoke passed for ${EXPECTED_RELEASE}."
