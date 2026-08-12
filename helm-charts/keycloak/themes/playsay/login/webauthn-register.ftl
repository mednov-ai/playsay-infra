<#import "template.ftl" as layout>
<#import "password-commons.ftl" as passwordCommons>

<@layout.registrationLayout; section>
    <#if section = "title">
        ${msg("playsayPasskeyRegisterTitle")}
    <#elseif section = "header">
        ${msg("playsayPasskeyRegisterTitle")}
    <#elseif section = "form">
        <p class="playsay-passkey-description">${msg("playsayPasskeyRegisterDescription")}</p>

        <form id="register" class="${properties.kcFormClass!}" action="${url.loginAction}" method="post">
            <div class="${properties.kcFormGroupClass!}">
                <input type="hidden" id="clientDataJSON" name="clientDataJSON" />
                <input type="hidden" id="attestationObject" name="attestationObject" />
                <input type="hidden" id="publicKeyCredentialId" name="publicKeyCredentialId" />
                <input type="hidden" id="authenticatorLabel" name="authenticatorLabel" />
                <input type="hidden" id="transports" name="transports" />
                <input type="hidden" id="authenticatorAttachment" name="authenticatorAttachment" />
                <input type="hidden" id="error" name="error" />
                <@passwordCommons.logoutOtherSessions/>
            </div>
        </form>

        <p class="playsay-passkey-progress" id="playsay-passkey-progress" role="status">
            ${msg("playsayPasskeyStarting")}
        </p>
        <button
            class="${properties.kcButtonClass!} ${properties.kcButtonPrimaryClass!} ${properties.kcButtonBlockClass!} ${properties.kcButtonLargeClass!}"
            hidden
            id="registerWebAuthn"
            type="button"
        >${msg("playsayPasskeyContinue")}</button>

        <#if !isSetRetry?has_content && isAppInitiatedAction?has_content>
            <form action="${url.loginAction}" class="${properties.kcFormClass!} playsay-passkey-cancel" id="kc-webauthn-settings-form" method="post">
                <button
                    class="${properties.kcButtonClass!} ${properties.kcButtonDefaultClass!} ${properties.kcButtonBlockClass!} ${properties.kcButtonLargeClass!}"
                    id="cancelWebAuthnAIA"
                    name="cancel-aia"
                    type="submit"
                    value="true"
                >${msg("doCancel")}</button>
            </form>
        </#if>

        <script type="module">
            <#outputformat "JavaScript">
            import { registerByWebAuthn, requiresExplicitUserGesture } from "${url.resourcesPath}/js/playsayWebAuthnRegister.js";

            const input = {
                challenge: ${challenge?c},
                userid: ${userid?c},
                username: ${username?c},
                signatureAlgorithms: [<#list signatureAlgorithms as sigAlg>${sigAlg?c},</#list>],
                rpEntityName: ${rpEntityName?c},
                rpId: ${rpId?c},
                attestationConveyancePreference: ${attestationConveyancePreference?c},
                authenticatorAttachment: ${authenticatorAttachment?c},
                requireResidentKey: ${requireResidentKey?c},
                residentKey: ${residentKey?c},
                userVerificationRequirement: ${userVerificationRequirement?c},
                createTimeout: ${createTimeout?c},
                excludeCredentialIds: ${excludeCredentialIds?c},
                defaultLabel: ${msg("playsayPasskeyDefaultLabel")?c},
                unsupportedMessage: ${msg("webauthn-unsupported-browser-text")?c}
            };
            const button = document.getElementById("registerWebAuthn");
            const progress = document.getElementById("playsay-passkey-progress");

            function showContinueButton() {
                progress.textContent = ${msg("playsayPasskeyTapContinue")?c};
                button.hidden = false;
                button.focus();
            }

            button.addEventListener("click", async () => {
                button.disabled = true;
                progress.textContent = ${msg("playsayPasskeyStarting")?c};
                await registerByWebAuthn(input, { allowGestureFallback: false });
            }, { once: true });

            if (requiresExplicitUserGesture()) {
                showContinueButton();
            } else {
                const completed = await registerByWebAuthn(input, { allowGestureFallback: true });
                if (!completed) showContinueButton();
            }
            </#outputformat>
        </script>
    </#if>
</@layout.registrationLayout>
