#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
THEME_ROOT="$REPO_ROOT/helm-charts/keycloak/themes/playsay/login"
SCRIPT="$THEME_ROOT/resources/js/playsayWebAuthnRegister.js"
TEMPLATE="$THEME_ROOT/webauthn-register.ftl"
LOGIN_SCRIPT="$THEME_ROOT/resources/js/playsayPasskeyLogin.js"
LOGIN_TEMPLATE="$THEME_ROOT/login.ftl"
RECOVERY_SCRIPT="$THEME_ROOT/resources/js/playsayPasswordRecovery.js"
LAYOUT_TEMPLATE="$THEME_ROOT/template.ftl"

if rg -q 'window\.prompt' "$SCRIPT" "$TEMPLATE"; then
  echo "Passkey theme must not ask the user for a credential label." >&2
  exit 1
fi

rg -q 'playsayPasskeyDefaultLabel' "$TEMPLATE"
rg -q 'requiresExplicitUserGesture' "$TEMPLATE"
rg -q 'allowGestureFallback: false' "$TEMPLATE"
rg -q 'playsay-passkey-login' "$LOGIN_TEMPLATE"
rg -q 'id="kc-form-login"' "$LOGIN_TEMPLATE"
rg -q 'playsaySignInTitle' "$LOGIN_TEMPLATE"
rg -q 'initPasskeyLogin' "$LOGIN_TEMPLATE"
rg -q 'id="playsay-forgot-password"' "$LAYOUT_TEMPLATE"
rg -q 'data-recovery-base-url=' "$LAYOUT_TEMPLATE"
rg -q 'playsayPasswordRecovery.js' "$LAYOUT_TEMPLATE"
rg -q 'mediation: "optional"' "$LOGIN_SCRIPT"
if rg -q 'sessionStorage|reserveAutomaticAttempt|authenticationSessionIdentifier|passwordInitiallyExpanded|initPasskeyFirstLogin' "$LOGIN_SCRIPT" "$LOGIN_TEMPLATE"; then
  echo "Login must not reserve or start an automatic Passkey attempt." >&2
  exit 1
fi

for locale in ru en de fr; do
  messages="$THEME_ROOT/messages/messages_${locale}.properties"
  rg -q '^playsaySignInTitle=' "$messages"
  rg -q '^playsaySignInDescription=' "$messages"
  rg -q '^playsaySignInAlternative=' "$messages"
  rg -q '^playsayPasskeyLoginPrimary=' "$messages"
  rg -q '^playsayPasskeyLoginFailed=' "$messages"
done

PASSKEY_LINE=$(rg -n 'id="playsay-passkey-login"' "$LOGIN_TEMPLATE" | cut -d: -f1)
PASSWORD_LINE=$(rg -n 'id="kc-form-login"' "$LOGIN_TEMPLATE" | cut -d: -f1)
if (( PASSWORD_LINE >= PASSKEY_LINE )); then
  echo "The visible password form must be rendered before the optional Passkey action." >&2
  exit 1
fi

rg -q 'kcButtonPrimaryClass.*id="kc-login"' "$LOGIN_TEMPLATE"
rg -q 'kcButtonDefaultClass.*playsay-passkey-login-secondary' "$LOGIN_TEMPLATE"

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
import assert from "node:assert/strict";

const scriptUrl = new URL(`file://${process.argv[2]}`);
const stubUrl = new URL("./webauthnAuthenticate.js", scriptUrl);
const login = await import(scriptUrl);
const stub = await import(stubUrl);

class FakeElement extends EventTarget {
  constructor() {
    super();
    this.disabled = false;
    this.hidden = false;
    this.textContent = "";
  }
}

function installDom({ supported = true } = {}) {
  const elements = new Map([
    ["playsay-passkey-option", new FakeElement()],
    ["playsay-passkey-login", new FakeElement()],
    ["playsay-passkey-status", new FakeElement()],
    ["kc-form-login", new FakeElement()],
  ]);
  elements.get("playsay-passkey-status").hidden = true;
  globalThis.document = { getElementById: (id) => elements.get(id) };
  globalThis.window = { PublicKeyCredential: supported ? function PublicKeyCredential() {} : undefined };
  Object.defineProperty(globalThis, "navigator", {
    configurable: true,
    value: { credentials: supported ? { get() {} } : undefined },
  });
  return elements;
}

function initialize(elements, enabled = true) {
  login.initPasskeyLogin({
    enabled,
    input: { isUserIdentified: false },
    messages: { opening: "opening", failed: "failed" },
  });
  return {
    form: elements.get("kc-form-login"),
    section: elements.get("playsay-passkey-option"),
    button: elements.get("playsay-passkey-login"),
    status: elements.get("playsay-passkey-status"),
  };
}

async function flush() {
  await new Promise((resolve) => setTimeout(resolve, 0));
}

stub.resetWebauthnTestState();
let elements = installDom();
let controls = initialize(elements);
assert.equal(stub.webauthnTestState.authenticateCalls.length, 0, "Initialization must not start WebAuthn.");
assert.equal(controls.section.hidden, false);
controls.button.dispatchEvent(new Event("click"));
await flush();
assert.equal(stub.webauthnTestState.authenticateCalls.length, 1, "Explicit activation must start one request.");
assert.equal(stub.webauthnTestState.authenticateCalls[0].additionalOptions.mediation, "optional");
assert.equal(controls.button.disabled, false);

stub.resetWebauthnTestState();
let settlePending;
stub.setAuthenticateImplementation(() => new Promise((resolve) => { settlePending = resolve; }));
elements = installDom();
controls = initialize(elements);
controls.button.dispatchEvent(new Event("click"));
controls.button.dispatchEvent(new Event("click"));
assert.equal(stub.webauthnTestState.authenticateCalls.length, 1, "A pending request must reject duplicate activation.");
assert.equal(controls.button.disabled, true);
settlePending(undefined);
await flush();
assert.equal(controls.button.disabled, false);

stub.resetWebauthnTestState();
stub.setAuthenticateImplementation(async () => { throw Object.assign(new Error("cancelled"), { name: "NotAllowedError" }); });
elements = installDom();
controls = initialize(elements);
controls.button.dispatchEvent(new Event("click"));
await flush();
assert.equal(controls.status.hidden, true, "Cancellation must not be announced as an error.");
assert.equal(controls.button.disabled, false);

stub.resetWebauthnTestState();
stub.setAuthenticateImplementation(async () => { throw Object.assign(new Error("failed"), { name: "SecurityError" }); });
elements = installDom();
controls = initialize(elements);
controls.button.dispatchEvent(new Event("click"));
await flush();
assert.equal(controls.status.textContent, "failed");
assert.equal(controls.status.hidden, false);
assert.equal(controls.section.hidden, false, "Unexpected failure must keep the Passkey retry available.");

stub.resetWebauthnTestState();
let rejectPending;
stub.setAuthenticateImplementation(() => new Promise((_, reject) => { rejectPending = reject; }));
elements = installDom();
controls = initialize(elements);
controls.button.dispatchEvent(new Event("click"));
controls.form.dispatchEvent(new Event("focusin"));
assert.equal(stub.webauthnTestState.signalCalls, 1, "Password interaction must abort the pending request.");
assert.equal(controls.button.disabled, false);
assert.equal(controls.status.hidden, true);
rejectPending(Object.assign(new Error("aborted"), { name: "AbortError" }));
await flush();

stub.resetWebauthnTestState();
elements = installDom({ supported: false });
controls = initialize(elements);
assert.equal(controls.section.hidden, true, "Unsupported WebAuthn must hide the optional method.");
assert.equal(stub.webauthnTestState.authenticateCalls.length, 0);

assert.equal(login.isUserCancellation({ name: "NotAllowedError" }), true);
assert.equal(login.isUserCancellation({ name: "AbortError" }), true);
assert.equal(login.isUserCancellation({ name: "SecurityError" }), false);
NODE

mkdir -p "$TEST_DIR/recovery"
cp "$RECOVERY_SCRIPT" "$TEST_DIR/recovery/playsayPasswordRecovery.js"
cp "$REPO_ROOT/scripts/fixtures/module-package.json" "$TEST_DIR/recovery/package.json"

node --input-type=module - "$TEST_DIR/recovery/playsayPasswordRecovery.js" <<'NODE'
import assert from "node:assert/strict";

const recovery = await import(new URL(`file://${process.argv[2]}`));
const documentRef = {
  createElement() {
    return {
      required: false,
      type: "text",
      value: "",
      checkValidity() { return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(this.value); },
    };
  },
};

assert.equal(
  recovery.passwordRecoveryHref("https://online.honey.school/forgot-password", " learner+one@example.test ", documentRef),
  "https://online.honey.school/forgot-password?email=learner%2Bone%40example.test",
);
assert.equal(
  recovery.passwordRecoveryHref("https://online.honey.school/forgot-password", "not-an-email", documentRef),
  "https://online.honey.school/forgot-password",
);
assert.equal(
  recovery.passwordRecoveryHref("https://online.honey.school/forgot-password", "", documentRef),
  "https://online.honey.school/forgot-password",
);

class FakeLink extends EventTarget {
  constructor() {
    super();
    this.dataset = { recoveryBaseUrl: "https://online.honey.school/forgot-password" };
    this.href = this.dataset.recoveryBaseUrl;
  }
}

const link = new FakeLink();
const username = { value: "changed@example.test" };
recovery.initPasswordRecoveryLink({ link, username, documentRef });
link.dispatchEvent(new Event("pointerdown"));
assert.equal(link.href, "https://online.honey.school/forgot-password?email=changed%40example.test");
username.value = "second@example.test";
link.dispatchEvent(new Event("focus"));
assert.equal(link.href, "https://online.honey.school/forgot-password?email=second%40example.test");

const missingUsernameLink = new FakeLink();
recovery.initPasswordRecoveryLink({ link: missingUsernameLink, username: null, documentRef });
missingUsernameLink.dispatchEvent(new Event("click"));
assert.equal(missingUsernameLink.href, "https://online.honey.school/forgot-password");
assert.equal(
  recovery.passwordRecoveryHref("https://online.honey.school/forgot-password", "learner@example.test", null),
  "https://online.honey.school/forgot-password",
);
NODE

echo "Keycloak passkey theme regression checks passed."
