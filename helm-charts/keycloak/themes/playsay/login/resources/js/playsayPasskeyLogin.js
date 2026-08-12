import { doAuthenticate, getAllowCredentials, returnSuccess, signal } from "./webauthnAuthenticate.js";

const ATTEMPT_STORAGE_PREFIX = "playsay.passkey-auto-attempt:";

export function authenticationSessionIdentifier(cookie = document.cookie, href = window.location.href) {
    const cookieMatch = cookie.match(/(?:^|;\s*)KC_AUTH_SESSION_HASH=([^;]+)/);
    if (cookieMatch?.[1]) return `hash:${decodeURIComponent(cookieMatch[1])}`;

    try {
        const url = new URL(href);
        const tabId = url.searchParams.get("tab_id");
        const clientId = url.searchParams.get("client_id");
        if (tabId) return `tab:${clientId || "unknown"}:${tabId}`;
    } catch (_) {
        // The browser still gets the explicit passkey button if the URL is malformed.
    }

    return null;
}

export function reserveAutomaticAttempt(storage = window.sessionStorage, sessionIdentifier = authenticationSessionIdentifier()) {
    if (!sessionIdentifier) return false;

    const key = `${ATTEMPT_STORAGE_PREFIX}${sessionIdentifier}`;
    try {
        if (storage.getItem(key)) return false;
        storage.setItem(key, "1");
        return true;
    } catch (_) {
        return false;
    }
}

export function isUserCancellation(error) {
    return error?.name === "AbortError" || error?.name === "NotAllowedError";
}

export function initPasskeyFirstLogin({ enabled, passwordInitiallyExpanded, input, messages }) {
    const passkeyButton = document.getElementById("playsay-passkey-login");
    const passwordToggle = document.getElementById("playsay-password-login-toggle");
    const passwordPanel = document.getElementById("playsay-password-panel");
    const status = document.getElementById("playsay-passkey-status");
    const username = document.getElementById("username");
    let pending = false;

    function setStatus(message) {
        status.textContent = message || "";
        status.hidden = !message;
    }

    function revealPassword(message = "", hidePasskey = false) {
        signal();
        passwordPanel.hidden = false;
        passwordToggle.hidden = true;
        passwordToggle.setAttribute("aria-expanded", "true");
        passkeyButton.hidden = hidePasskey;
        setStatus(message);
        username?.focus();
    }

    async function authenticate({ automatic }) {
        if (pending) return;
        pending = true;
        passkeyButton.disabled = true;
        setStatus(messages.opening);

        try {
            const result = await doAuthenticate({
                ...input,
                allowCredentials: input.isUserIdentified ? getAllowCredentials() : [],
                additionalOptions: { mediation: "optional" },
            });
            if (result) returnSuccess(result);
            else if (!automatic) setStatus("");
        } catch (error) {
            if (isUserCancellation(error)) setStatus("");
            else revealPassword(messages.failed);
        } finally {
            pending = false;
            passkeyButton.disabled = false;
        }
    }

    passwordToggle.addEventListener("click", () => revealPassword());

    if (!enabled || !window.PublicKeyCredential || !navigator.credentials?.get) {
        revealPassword(messages.unsupported, true);
        return;
    }

    passkeyButton.addEventListener("click", () => authenticate({ automatic: false }));

    if (!passwordInitiallyExpanded && reserveAutomaticAttempt()) {
        authenticate({ automatic: true });
    }
}
