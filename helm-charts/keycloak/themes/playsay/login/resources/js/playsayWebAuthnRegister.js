import { base64url } from "rfc4648";

export function requiresExplicitUserGesture(userAgent = navigator.userAgent) {
    return /iPad|iPhone|iPod/.test(userAgent)
        || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
}

export async function registerByWebAuthn(input, { allowGestureFallback = false } = {}) {
    if (!window.PublicKeyCredential || !navigator.credentials?.create) {
        returnFailure(input.unsupportedMessage);
        return true;
    }

    try {
        const result = await navigator.credentials.create({ publicKey: buildPublicKey(input) });
        returnSuccess(result, input.defaultLabel);
        return true;
    } catch (error) {
        if (allowGestureFallback && error?.name === "NotAllowedError") {
            return false;
        }
        returnFailure(error instanceof Error ? error.message : String(error));
        return true;
    }
}

function buildPublicKey(input) {
    const publicKey = {
        challenge: base64url.parse(input.challenge, { loose: true }),
        rp: { id: input.rpId, name: input.rpEntityName },
        user: {
            id: base64url.parse(input.userid, { loose: true }),
            name: input.username,
            displayName: input.username,
        },
        pubKeyCredParams: input.signatureAlgorithms.length
            ? input.signatureAlgorithms.map((alg) => ({ type: "public-key", alg }))
            : [{ type: "public-key", alg: -7 }],
    };

    if (input.attestationConveyancePreference !== "not specified") {
        publicKey.attestation = input.attestationConveyancePreference;
    }

    const authenticatorSelection = {};
    if (input.authenticatorAttachment !== "not specified") {
        authenticatorSelection.authenticatorAttachment = input.authenticatorAttachment;
    }
    if (input.residentKey && input.residentKey !== "not specified") {
        authenticatorSelection.residentKey = input.residentKey;
        authenticatorSelection.requireResidentKey = input.residentKey === "required";
    } else if (input.requireResidentKey !== "not specified") {
        const required = input.requireResidentKey === "Yes";
        authenticatorSelection.residentKey = required ? "required" : "discouraged";
        authenticatorSelection.requireResidentKey = required;
    }
    if (input.userVerificationRequirement !== "not specified") {
        authenticatorSelection.userVerification = input.userVerificationRequirement;
    }
    if (Object.keys(authenticatorSelection).length) {
        publicKey.authenticatorSelection = authenticatorSelection;
    }
    if (input.createTimeout !== 0) {
        publicKey.timeout = input.createTimeout * 1000;
    }
    if (input.excludeCredentialIds) {
        publicKey.excludeCredentials = input.excludeCredentialIds.split(",").map((id) => ({
            type: "public-key",
            id: base64url.parse(id, { loose: true }),
        }));
    }
    return publicKey;
}

function returnSuccess(result, defaultLabel) {
    document.getElementById("clientDataJSON").value = base64url.stringify(new Uint8Array(result.response.clientDataJSON), { pad: false });
    document.getElementById("attestationObject").value = base64url.stringify(new Uint8Array(result.response.attestationObject), { pad: false });
    document.getElementById("publicKeyCredentialId").value = base64url.stringify(new Uint8Array(result.rawId), { pad: false });

    if (typeof result.response.getTransports === "function") {
        document.getElementById("transports").value = (result.response.getTransports() ?? []).join();
    }
    if (result.authenticatorAttachment) {
        document.getElementById("authenticatorAttachment").value = result.authenticatorAttachment;
    }
    document.getElementById("authenticatorLabel").value = defaultLabel;
    document.getElementById("register").requestSubmit();
}

function returnFailure(error) {
    document.getElementById("error").value = error;
    document.getElementById("register").requestSubmit();
}
