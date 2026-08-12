#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
THEME_ROOT="$REPO_ROOT/helm-charts/keycloak/themes/playsay/login"
SCRIPT="$THEME_ROOT/resources/js/playsayWebAuthnRegister.js"
TEMPLATE="$THEME_ROOT/webauthn-register.ftl"

if rg -q 'window\.prompt' "$SCRIPT" "$TEMPLATE"; then
  echo "Passkey theme must not ask the user for a credential label." >&2
  exit 1
fi

rg -q 'playsayPasskeyDefaultLabel' "$TEMPLATE"
rg -q 'requiresExplicitUserGesture' "$TEMPLATE"
rg -q 'allowGestureFallback: false' "$TEMPLATE"

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
cp "$SCRIPT" "$TEST_DIR/passkey.mjs"
mkdir -p "$TEST_DIR/node_modules/rfc4648"
cp "$REPO_ROOT/scripts/fixtures/rfc4648-package.json" "$TEST_DIR/node_modules/rfc4648/package.json"
cp "$REPO_ROOT/scripts/fixtures/rfc4648-stub.js" "$TEST_DIR/node_modules/rfc4648/index.js"

node --input-type=module - "$TEST_DIR/passkey.mjs" <<'NODE'
const scriptUrl = new URL(`file://${process.argv[2]}`);
Object.defineProperty(globalThis, "navigator", { configurable: true, value: { maxTouchPoints: 0, platform: "Linux", userAgent: "" } });
const { requiresExplicitUserGesture } = await import(scriptUrl);

if (!requiresExplicitUserGesture("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit Safari")) {
  throw new Error("Mobile Safari must use an explicit user gesture before WebAuthn registration.");
}
Object.defineProperty(globalThis, "navigator", { configurable: true, value: { maxTouchPoints: 5, platform: "MacIntel", userAgent: "" } });
if (!requiresExplicitUserGesture("Mozilla/5.0 (Macintosh) AppleWebKit Safari")) {
  throw new Error("iPad desktop mode must use an explicit user gesture.");
}
Object.defineProperty(globalThis, "navigator", { configurable: true, value: { maxTouchPoints: 0, platform: "Linux", userAgent: "" } });
if (requiresExplicitUserGesture("Mozilla/5.0 (X11; Linux x86_64) Chrome/140 Safari")) {
  throw new Error("Desktop Chromium should keep automatic registration.");
}
NODE

echo "Keycloak passkey theme regression checks passed."
