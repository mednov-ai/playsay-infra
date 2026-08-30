import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const source = await readFile(
  new URL("../themes/playsay/login/resources/js/playsayPasswordRecovery.js", import.meta.url),
  "utf8",
);
const recovery = await import(`data:text/javascript;base64,${Buffer.from(source).toString("base64")}`);

test("keeps the exact allowed application origin selected by OIDC redirect_uri", () => {
  const allowed = "https://online.honeyschool.ru,https://online.honey.school";
  const rfAuth = "https://ops.honey.school/keycloak/auth?redirect_uri=https%3A%2F%2Fonline.honeyschool.ru%2Fauth%2Fcallback";
  const directAuth = "https://ops.honey.school/keycloak/auth?redirect_uri=https%3A%2F%2Fonline.honey.school%2Fauth%2Fcallback";

  assert.equal(
    recovery.passwordRecoveryBaseUrl("https://online.honey.school/forgot-password", allowed, rfAuth, URL),
    "https://online.honeyschool.ru/forgot-password",
  );
  assert.equal(
    recovery.passwordRecoveryBaseUrl("https://online.honey.school/forgot-password", allowed, directAuth, URL),
    "https://online.honey.school/forgot-password",
  );
});

test("rejects lookalike and unlisted redirect origins", () => {
  const fallback = "https://online.honey.school/forgot-password";
  const allowed = "https://online.honeyschool.ru,https://online.honey.school";
  const foreignAuth = "https://ops.honey.school/keycloak/auth?redirect_uri=https%3A%2F%2Fonline.honeyschool.ru.example%2Fauth%2Fcallback";

  assert.equal(recovery.passwordRecoveryBaseUrl(fallback, allowed, foreignAuth, URL), fallback);
  assert.equal(recovery.passwordRecoveryBaseUrl(fallback, allowed, "not-a-url", URL), fallback);
});

test("transfers only a complete valid email", () => {
  const documentRef = {
    createElement() {
      return {
        type: "",
        required: false,
        value: "",
        checkValidity() {
          return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(this.value);
        },
      };
    },
  };
  const base = "https://online.honeyschool.ru/forgot-password";

  assert.equal(recovery.passwordRecoveryHref(base, "student@example.com", documentRef, URL), `${base}?email=student%40example.com`);
  for (const invalid of ["", "student", "student@", "student@example"]) {
    assert.equal(recovery.passwordRecoveryHref(base, invalid, documentRef, URL), base);
  }
});
