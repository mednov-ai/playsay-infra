export function passwordRecoveryHref(baseUrl, rawUsername, documentRef = globalThis.document, URLCtor = globalThis.URL) {
  const fallback = String(baseUrl || "");
  const email = String(rawUsername || "").trim();
  if (!fallback || !email || !documentRef?.createElement || !URLCtor) {
    return fallback;
  }

  const validator = documentRef.createElement("input");
  validator.type = "email";
  validator.required = true;
  validator.value = email;
  if (!validator.checkValidity()) {
    return fallback;
  }

  try {
    const destination = new URLCtor(fallback, globalThis.window?.location?.href);
    destination.searchParams.set("email", email);
    return destination.toString();
  } catch (caught) {
    return fallback;
  }
}

export function initPasswordRecoveryLink({
  link = globalThis.document?.getElementById?.("playsay-forgot-password"),
  username = globalThis.document?.getElementById?.("username"),
  documentRef = globalThis.document,
  URLCtor = globalThis.URL,
} = {}) {
  if (!link) {
    return;
  }

  const baseUrl = link.dataset?.recoveryBaseUrl || link.getAttribute?.("href") || link.href;
  const refreshDestination = () => {
    link.href = passwordRecoveryHref(baseUrl, username?.value, documentRef, URLCtor);
  };
  ["pointerdown", "focus", "keydown", "click"].forEach((eventName) => {
    link.addEventListener(eventName, refreshDestination);
  });
}

if (globalThis.document) {
  if (globalThis.document.readyState === "loading") {
    globalThis.document.addEventListener("DOMContentLoaded", () => initPasswordRecoveryLink(), { once: true });
  } else {
    initPasswordRecoveryLink();
  }
}
