<#import "template.ftl" as layout>

<#assign passwordError = messagesPerField.existsError('username','password')>
<#assign passkeyEnabled = enableWebAuthnConditionalUI?has_content>

<@layout.registrationLayout displayMessage=!passwordError displayInfo=false; section>
    <#if section = "title">
        ${msg("playsaySignInTitle")}
    <#elseif section = "header">
        ${msg("playsaySignInTitle")}
    <#elseif section = "form">
        <div class="playsay-login-methods" id="playsay-login-methods">
            <#if passkeyEnabled>
                <form id="webauth" action="${url.loginAction}" method="post">
                    <input type="hidden" id="clientDataJSON" name="clientDataJSON" />
                    <input type="hidden" id="authenticatorData" name="authenticatorData" />
                    <input type="hidden" id="signature" name="signature" />
                    <input type="hidden" id="credentialId" name="credentialId" />
                    <input type="hidden" id="userHandle" name="userHandle" />
                    <input type="hidden" id="error" name="error" />
                </form>

                <#if authenticators??>
                    <form id="authn_select" class="${properties.kcFormClass!}">
                        <#list authenticators.authenticators as authenticator>
                            <input type="hidden" name="authn_use_chk" value="${authenticator.credentialId}" />
                        </#list>
                    </form>
                </#if>
            </#if>

            <p class="playsay-sign-in-description">${msg("playsaySignInDescription")}</p>

            <form id="kc-form-login" onsubmit="login.disabled = true; return true;" action="${url.loginAction}" method="post">
                <#if !usernameHidden??>
                    <div class="${properties.kcFormGroupClass!}">
                        <label for="username" class="${properties.kcLabelClass!}"><#if !realm.loginWithEmailAllowed>${msg("username")}<#elseif !realm.registrationEmailAsUsername>${msg("usernameOrEmail")}<#else>${msg("email")}</#if></label>
                        <input
                            aria-invalid="${passwordError?c}"
                            autocomplete="username"
                            class="${properties.kcInputClass!}"
                            dir="ltr"
                            id="username"
                            name="username"
                            type="text"
                            value="${(login.username!'')}"
                            <#if passwordError>autofocus</#if>
                        />

                        <#if passwordError>
                            <span id="input-error" class="${properties.kcInputErrorMessageClass!}" aria-live="polite">
                                ${kcSanitize(messagesPerField.getFirstError('username','password'))?no_esc}
                            </span>
                        </#if>
                    </div>
                </#if>

                <div class="${properties.kcFormGroupClass!}">
                    <label for="password" class="${properties.kcLabelClass!}">${msg("password")}</label>
                    <div class="${properties.kcInputGroup!}" dir="ltr">
                        <input
                            aria-invalid="${passwordError?c}"
                            autocomplete="current-password"
                            class="${properties.kcInputClass!}"
                            id="password"
                            name="password"
                            type="password"
                        />
                        <button
                            aria-controls="password"
                            aria-label="${msg("showPassword")}"
                            class="${properties.kcFormPasswordVisibilityButtonClass!}"
                            data-icon-hide="${properties.kcFormPasswordVisibilityIconHide!}"
                            data-icon-show="${properties.kcFormPasswordVisibilityIconShow!}"
                            data-label-hide="${msg('hidePassword')}"
                            data-label-show="${msg('showPassword')}"
                            data-password-toggle
                            type="button"
                        ><i class="${properties.kcFormPasswordVisibilityIconShow!}" aria-hidden="true"></i></button>
                    </div>

                    <#if usernameHidden?? && passwordError>
                        <span id="input-error" class="${properties.kcInputErrorMessageClass!}" aria-live="polite">
                            ${kcSanitize(messagesPerField.getFirstError('username','password'))?no_esc}
                        </span>
                    </#if>
                </div>

                <#if realm.rememberMe && !usernameHidden??>
                    <div class="${properties.kcFormGroupClass!} ${properties.kcFormSettingClass!}">
                        <div id="kc-form-options">
                            <div class="checkbox">
                                <label>
                                    <input id="rememberMe" name="rememberMe" type="checkbox" <#if login.rememberMe??>checked</#if>> ${msg("rememberMe")}
                                </label>
                            </div>
                        </div>
                    </div>
                </#if>

                <div id="kc-form-buttons" class="${properties.kcFormGroupClass!}">
                    <input type="hidden" id="id-hidden-input" name="credentialId" <#if auth.selectedCredential?has_content>value="${auth.selectedCredential}"</#if> />
                    <input class="${properties.kcButtonClass!} ${properties.kcButtonPrimaryClass!} ${properties.kcButtonBlockClass!} ${properties.kcButtonLargeClass!}" name="login" id="kc-login" type="submit" value="${msg("playsayPasswordLoginSubmit")}" />
                </div>
            </form>

            <div class="playsay-login-separator" role="separator">
                <span>${msg("playsaySignInAlternative")}</span>
            </div>

            <div class="playsay-passkey-option" id="playsay-passkey-option">
                <p class="playsay-passkey-description" id="playsay-passkey-login-description">
                    ${msg("playsayPasskeyLoginDescription")}
                </p>
                <button
                    aria-describedby="playsay-passkey-login-description"
                    class="${properties.kcButtonClass!} ${properties.kcButtonDefaultClass!} ${properties.kcButtonBlockClass!} ${properties.kcButtonLargeClass!} playsay-passkey-login-secondary"
                    id="playsay-passkey-login"
                    type="button"
                >${msg("playsayPasskeyLoginPrimary")}</button>
                <p class="playsay-passkey-status" id="playsay-passkey-status" role="status" aria-live="polite" hidden></p>
            </div>
        </div>

        <script type="module" src="${url.resourcesPath}/js/passwordVisibility.js"></script>
        <script type="module">
            <#outputformat "JavaScript">
            import { initPasskeyLogin } from ${(url.resourcesPath + "/js/playsayPasskeyLogin.js")?c};

            initPasskeyLogin({
                enabled: ${passkeyEnabled?c},
                input: {
                    isUserIdentified: ${(isUserIdentified!false)?c},
                    challenge: ${(challenge!'')?c},
                    userVerification: ${(userVerification!'not specified')?c},
                    rpId: ${(rpId!'')?c},
                    createTimeout: ${(createTimeout!0)?c},
                    authenticatorAttachment: ${(authenticatorAttachment!'not specified')?c},
                    errmsg: ${msg("passkey-unsupported-browser-text")?c}
                },
                messages: {
                    opening: ${msg("playsayPasskeyLoginOpening")?c},
                    failed: ${msg("playsayPasskeyLoginFailed")?c}
                }
            });
            </#outputformat>
        </script>
    <#elseif section = "socialProviders">
        <#if realm.password && social?? && social.providers?has_content>
            <div id="kc-social-providers" class="${properties.kcFormSocialAccountSectionClass!}">
                <hr />
                <h2>${msg("identity-provider-login-label")}</h2>
                <ul class="${properties.kcFormSocialAccountListClass!} <#if social.providers?size gt 3>${properties.kcFormSocialAccountListGridClass!}</#if>">
                    <#list social.providers as p>
                        <li>
                            <a data-once-link data-disabled-class="${properties.kcFormSocialAccountListButtonDisabledClass!}" id="social-${p.alias}" class="${properties.kcFormSocialAccountListButtonClass!} <#if social.providers?size gt 3>${properties.kcFormSocialAccountGridItem!}</#if>" type="button" href="${p.loginUrl}">
                                <#if p.iconClasses?has_content><i class="${properties.kcCommonLogoIdP!} ${p.iconClasses!}" aria-hidden="true"></i></#if>
                                <span class="${properties.kcFormSocialAccountNameClass!}">${p.displayName!}</span>
                            </a>
                        </li>
                    </#list>
                </ul>
            </div>
        </#if>
    </#if>
</@layout.registrationLayout>
