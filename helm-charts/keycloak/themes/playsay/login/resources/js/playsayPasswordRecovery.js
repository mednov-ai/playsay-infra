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

export function passwordRecoveryBaseUrl(
  fallbackUrl,
  rawAllowedOrigins,
  currentHref = globalThis.window?.location?.href,
  URLCtor = globalThis.URL,
) {
  const fallback = String(fallbackUrl || "");
  if (!fallback || !currentHref || !URLCtor) {
    return fallback;
  }
  try {
    const allowedOrigins = String(rawAllowedOrigins || "")
      .split(",")
      .map((value) => new URLCtor(value.trim()).origin)
      .filter(Boolean);
    const redirectUri = new URLCtor(currentHref).searchParams.get("redirect_uri");
    const redirectOrigin = redirectUri ? new URLCtor(redirectUri).origin : "";
    return allowedOrigins.includes(redirectOrigin) ? `${redirectOrigin}/forgot-password` : fallback;
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

  const fallbackUrl = link.dataset?.recoveryBaseUrl || link.getAttribute?.("href") || link.href;
  const baseUrl = passwordRecoveryBaseUrl(
    fallbackUrl,
    link.dataset?.recoveryAllowedOrigins,
    globalThis.window?.location?.href,
    URLCtor,
  );
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
