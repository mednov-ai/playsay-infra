#!/usr/bin/env bash

base64url() {
  openssl base64 -A | tr '+/' '-_' | tr -d '='
}

github_app_token() {
  : "${GITHUB_APP_ID:?GITHUB_APP_ID is required}"
  : "${GITHUB_APP_INSTALLATION_ID:?GITHUB_APP_INSTALLATION_ID is required}"
  : "${GITHUB_APP_PRIVATE_KEY_PATH:?GITHUB_APP_PRIVATE_KEY_PATH is required}"
  [[ -r "${GITHUB_APP_PRIVATE_KEY_PATH}" ]] || {
    echo "GitHub App private key is not readable." >&2
    return 1
  }

  local now issued_at expires_at header payload unsigned signature jwt response token
  now="$(date +%s)"
  issued_at="$((now - 60))"
  expires_at="$((now + 540))"
  header="$(printf '%s' '{"alg":"RS256","typ":"JWT"}' | base64url)"
  payload="$(
    jq -cn \
      --argjson iat "${issued_at}" \
      --argjson exp "${expires_at}" \
      --arg iss "${GITHUB_APP_ID}" \
      '{iat:$iat,exp:$exp,iss:$iss}' |
      base64url
  )"
  unsigned="${header}.${payload}"
  signature="$(
    printf '%s' "${unsigned}" |
      openssl dgst -sha256 -sign "${GITHUB_APP_PRIVATE_KEY_PATH}" |
      base64url
  )"
  jwt="${unsigned}.${signature}"
  response="$(
    curl -fsS \
      -X POST \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer ${jwt}" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "https://api.github.com/app/installations/${GITHUB_APP_INSTALLATION_ID}/access_tokens"
  )"
  token="$(jq -r '.token // empty' <<<"${response}")"
  [[ -n "${token}" ]] || {
    echo "GitHub App installation token response did not contain a token." >&2
    return 1
  }
  printf '%s' "${token}"
}

github_curl() {
  : "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"
  curl -fsS \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$@"
}

github_git() {
  : "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"
  git -c "http.extraHeader=Authorization: Bearer ${GITHUB_TOKEN}" "$@"
}
