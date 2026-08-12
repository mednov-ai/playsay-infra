#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
THEME_ROOT="$REPO_ROOT/helm-charts/keycloak/themes/playsay/login"
SCRIPT="$THEME_ROOT/resources/js/playsayWebAuthnRegister.js"
TEMPLATE="$THEME_ROOT/webauthn-register.ftl"
LOGIN_SCRIPT="$THEME_ROOT/resources/js/playsayPasskeyLogin.js"
LOGIN_TEMPLATE="$THEME_ROOT/login.ftl"

if rg -q 'window\.prompt' "$SCRIPT" "$TEMPLATE"; then
  echo "Passkey theme must not ask the user for a credential label." >&2
  exit 1
fi

rg -q 'playsayPasskeyDefaultLabel' "$TEMPLATE"
rg -q 'requiresExplicitUserGesture' "$TEMPLATE"
rg -q 'allowGestureFallback: false' "$TEMPLATE"
rg -q 'playsay-passkey-login' "$LOGIN_TEMPLATE"
rg -q 'playsay-password-panel.*hidden' "$LOGIN_TEMPLATE"
rg -q 'passwordInitiallyExpanded:.*passwordError' "$LOGIN_TEMPLATE"
rg -q 'mediation: "optional"' "$LOGIN_SCRIPT"

PASSKEY_LINE=$(rg -n 'id="playsay-passkey-login"' "$LOGIN_TEMPLATE" | cut -d: -f1)
PASSWORD_LINE=$(rg -n 'id="playsay-password-panel"' "$LOGIN_TEMPLATE" | cut -d: -f1)
if (( PASSKEY_LINE >= PASSWORD_LINE )); then
  echo "The passkey action must be rendered before the password fallback." >&2
  exit 1
fi

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

mkdir -p "$TEST_DIR/login"
cp "$LOGIN_SCRIPT" "$TEST_DIR/login/playsayPasskeyLogin.js"
cp "$REPO_ROOT/scripts/fixtures/webauthn-authenticate-stub.js" "$TEST_DIR/login/webauthnAuthenticate.js"
cp "$REPO_ROOT/scripts/fixtures/module-package.json" "$TEST_DIR/login/package.json"

node --input-type=module - "$TEST_DIR/login/playsayPasskeyLogin.js" <<'NODE'
const scriptUrl = new URL(`file://${process.argv[2]}`);
const { authenticationSessionIdentifier, isUserCancellation, reserveAutomaticAttempt } = await import(scriptUrl);

const identifier = authenticationSessionIdentifier("foo=bar; KC_AUTH_SESSION_HASH=session-123", "https://example.test/login?tab_id=tab-1");
if (identifier !== "hash:session-123") throw new Error("The Keycloak authentication-session hash must take precedence.");

const tabIdentifier = authenticationSessionIdentifier("", "https://example.test/login?client_id=web&tab_id=tab-1");
if (tabIdentifier !== "tab:web:tab-1") throw new Error("The Keycloak tab id must be used as a fallback.");

const values = new Map();
const storage = { getItem: (key) => values.get(key), setItem: (key, value) => values.set(key, value) };
if (!reserveAutomaticAttempt(storage, identifier)) throw new Error("The first automatic attempt must be reserved.");
if (reserveAutomaticAttempt(storage, identifier)) throw new Error("The automatic attempt must run only once per authentication session.");
if (!reserveAutomaticAttempt(storage, "hash:session-456")) throw new Error("A new authentication session must get its own automatic attempt.");

if (!isUserCancellation({ name: "NotAllowedError" }) || !isUserCancellation({ name: "AbortError" })) {
  throw new Error("User cancellation must keep the password form collapsed.");
}
if (isUserCancellation({ name: "SecurityError" })) throw new Error("Unexpected WebAuthn errors must reveal the password fallback.");
NODE

echo "Keycloak passkey theme regression checks passed."
