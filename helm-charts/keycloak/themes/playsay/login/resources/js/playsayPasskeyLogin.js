import { doAuthenticate, getAllowCredentials, returnSuccess, signal } from "./webauthnAuthenticate.js";

export function isUserCancellation(error) {
    return error?.name === "AbortError" || error?.name === "NotAllowedError";
}

export function initPasskeyLogin({ enabled, input, messages }) {
    const passkeySection = document.getElementById("playsay-passkey-option");
    const passkeyButton = document.getElementById("playsay-passkey-login");
    const passwordForm = document.getElementById("kc-form-login");
    const status = document.getElementById("playsay-passkey-status");
    let pending = false;
    let attemptId = 0;

    function setStatus(message) {
        status.textContent = message || "";
        status.hidden = !message;
    }

    function finishAttempt(id = attemptId) {
        if (id !== attemptId) return;
        pending = false;
        passkeyButton.disabled = false;
    }

    function abortForPassword() {
        if (!pending) return;
        attemptId += 1;
        signal();
        finishAttempt();
        setStatus("");
    }

    async function authenticate() {
        if (pending) return;
        pending = true;
        const currentAttemptId = ++attemptId;
        passkeyButton.disabled = true;
        setStatus(messages.opening);

        try {
            const result = await doAuthenticate({
                ...input,
                allowCredentials: input.isUserIdentified ? getAllowCredentials() : [],
                additionalOptions: { mediation: "optional" },
            });
            if (currentAttemptId !== attemptId) return;
            if (result) returnSuccess(result);
            else setStatus("");
        } catch (error) {
            if (currentAttemptId === attemptId) {
                if (isUserCancellation(error)) setStatus("");
                else setStatus(messages.failed);
            }
        } finally {
            finishAttempt(currentAttemptId);
        }
    }

    passwordForm.addEventListener("focusin", abortForPassword);
    passwordForm.addEventListener("submit", abortForPassword);

    if (!enabled || !window.PublicKeyCredential || !navigator.credentials?.get) {
        passkeySection.hidden = true;
        return;
    }

    passkeyButton.addEventListener("click", authenticate);
}
