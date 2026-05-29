<#import "footer.ftl" as loginFooter>
<#macro registrationLayout bodyClass="" displayInfo=false displayMessage=true displayRequiredFields=false>
<!DOCTYPE html>
<html class="${properties.kcHtmlClass!}" lang="${lang}"<#if realm.internationalizationEnabled> dir="${(locale.rtl)?then('rtl','ltr')}"</#if>>
<head>
    <meta charset="utf-8">
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
    <meta name="robots" content="noindex, nofollow">
    <#if properties.meta?has_content>
        <#list properties.meta?split(' ') as meta>
            <meta name="${meta?split('==')[0]}" content="${meta?split('==')[1]}"/>
        </#list>
    </#if>
    <title>${msg("loginTitle",(realm.displayName!''))}</title>
    <link rel="icon" href="${url.resourcesPath}/img/logo.jpg" />
    <#if properties.stylesCommon?has_content>
        <#list properties.stylesCommon?split(' ') as style>
            <link href="${url.resourcesCommonPath}/${style}" rel="stylesheet" />
        </#list>
    </#if>
    <#if properties.styles?has_content>
        <#list properties.styles?split(' ') as style>
            <link href="${url.resourcesPath}/${style}" rel="stylesheet" />
        </#list>
    </#if>
    <#if properties.scripts?has_content>
        <#list properties.scripts?split(' ') as script>
            <script src="${url.resourcesPath}/${script}" type="text/javascript"></script>
        </#list>
    </#if>
    <script type="importmap">
        {
            "imports": {
                "rfc4648": "${url.resourcesCommonPath}/vendor/rfc4648/rfc4648.js"
            }
        }
    </script>
    <script src="${url.resourcesPath}/js/menu-button-links.js" type="module"></script>
    <#if scripts??>
        <#list scripts as script>
            <script src="${script}" type="text/javascript"></script>
        </#list>
    </#if>
    <script type="module">
        import { startSessionPolling } from "${url.resourcesPath}/js/authChecker.js";

        startSessionPolling(
            "${url.ssoLoginInOtherTabsUrl?no_esc}"
        );
    </script>
    <script type="module">
        document.addEventListener("click", (event) => {
            const link = event.target.closest("a[data-once-link]");

            if (!link) {
                return;
            }

            if (link.getAttribute("aria-disabled") === "true") {
                event.preventDefault();
                return;
            }

            const { disabledClass } = link.dataset;

            if (disabledClass) {
                link.classList.add(...disabledClass.trim().split(/\s+/));
            }

            link.setAttribute("role", "link");
            link.setAttribute("aria-disabled", "true");
        });
    </script>
    <#if authenticationSession??>
        <script type="module">
            import { checkAuthSession } from "${url.resourcesPath}/js/authChecker.js";

            checkAuthSession(
                "${authenticationSession.authSessionIdHash}"
            );
        </script>
    </#if>
</head>

<body class="${properties.kcBodyClass!} playsay-login-body" data-page-id="login-${pageId}">
    <div class="playsay-brand">
        <div class="playsay-brand-logo">
            <img src="${url.resourcesPath}/img/logo.jpg" alt="${msg("playsayLoginLogoAlt")}" />
        </div>
        <div>${msg("playsayLoginBrandSubtitle")}</div>
    </div>

    <main class="playsay-page">
        <section class="playsay-copy" aria-label="${msg("playsayLoginCopyAria")}">
            <p class="playsay-eyebrow">${msg("playsayLoginAccountEyebrow")}</p>
            <h1>${msg("playsayLoginHeroTitle")}<span class="playsay-mark"></span></h1>
            <p class="playsay-lead">
                ${msg("playsayLoginHeroLead")}
            </p>

            <div class="playsay-chips" aria-label="${msg("playsayLoginChipsAria")}">
                <span class="playsay-chip">${msg("playsayLoginChipPlay")}</span>
                <span class="playsay-chip">${msg("playsayLoginChipSpeak")}</span>
                <span class="playsay-chip">${msg("playsayLoginChipHello")}</span>
            </div>

            <div class="playsay-points" aria-label="${msg("playsayLoginPointsAria")}">
                <div class="playsay-point">${msg("playsayLoginLessonWorkspace")}</div>
                <div class="playsay-point">${msg("playsayLoginStudentTeacherProfile")}</div>
                <div class="playsay-point">${msg("playsayLoginSecureAccess")}</div>
            </div>
        </section>

        <section class="playsay-card" aria-label="${msg("loginAccountTitle")}">
            <#if realm.internationalizationEnabled  && locale.supported?size gt 1>
                <div class="${properties.kcLocaleMainClass!}" id="kc-locale">
                    <div id="kc-locale-wrapper" class="${properties.kcLocaleWrapperClass!}">
                        <div id="kc-locale-dropdown" class="menu-button-links ${properties.kcLocaleDropDownClass!}">
                            <button tabindex="1" id="kc-current-locale-link" aria-label="${msg("languages")}" aria-haspopup="true" aria-expanded="false" aria-controls="language-switch1">${locale.current}</button>
                            <ul role="menu" tabindex="-1" aria-labelledby="kc-current-locale-link" aria-activedescendant="" id="language-switch1" class="${properties.kcLocaleListClass!}">
                                <#assign i = 1>
                                <#list locale.supported as l>
                                    <li class="${properties.kcLocaleListItemClass!}" role="none">
                                        <a role="menuitem" id="language-${i}" class="${properties.kcLocaleItemClass!}" href="${l.url}">${l.label}</a>
                                    </li>
                                    <#assign i++>
                                </#list>
                            </ul>
                        </div>
                    </div>
                </div>
                <script>
                    (function () {
                        var supportedLanguages = { ru: true, en: true, de: true, fr: true };
                        var links = document.querySelectorAll("#language-switch1 a[href]");

                        function loginLanguageFromHref(href) {
                            try {
                                var url = new URL(href, window.location.href);
                                return url.searchParams.get("kc_locale") || url.searchParams.get("ui_locales");
                            } catch (caught) {
                                var match = href.match(/[?&](?:kc_locale|ui_locales)=([^&]+)/);
                                return match ? decodeURIComponent(match[1]) : null;
                            }
                        }

                        function rememberLoginLanguage(locale) {
                            var language = String(locale || "").toLowerCase().split(/[-_]/)[0];
                            if (!supportedLanguages[language]) {
                                return;
                            }

                            var cookie = "playsay.pendingLoginLanguage=" + encodeURIComponent(language) + "; Path=/; Max-Age=600; SameSite=Lax";
                            if (window.location.protocol === "https:") {
                                cookie += "; Secure";
                            }
                            if (window.location.hostname === "play-and-say.ru" || window.location.hostname.endsWith(".play-and-say.ru")) {
                                cookie += "; Domain=.play-and-say.ru";
                            }
                            document.cookie = cookie;
                        }

                        links.forEach(function (link) {
                            link.addEventListener("click", function () {
                                rememberLoginLanguage(loginLanguageFromHref(link.href));
                            });
                        });
                    })();
                </script>
            </#if>

            <p class="playsay-eyebrow">${msg("playsayLoginWelcome")}</p>
            <#if !(auth?has_content && auth.showUsername() && !auth.showResetCredentials())>
                <h2 id="kc-page-title" class="playsay-card-title"><#nested "header"></h2>
            <#else>
                <#nested "show-username">
                <div id="kc-username" class="${properties.kcFormGroupClass!}">
                    <label id="kc-attempted-username">${auth.attemptedUsername}</label>
                    <a id="reset-login" href="${url.loginRestartFlowUrl}" aria-label="${msg("restartLoginTooltip")}">
                        <div class="kc-login-tooltip">
                            <i class="${properties.kcResetFlowIcon!}"></i>
                            <span class="kc-tooltip-text">${msg("restartLoginTooltip")}</span>
                        </div>
                    </a>
                </div>
            </#if>
            <p class="playsay-card-text">${msg("playsayLoginCardText")}</p>

            <div id="kc-content">
                <div id="kc-content-wrapper">
                    <#if displayMessage && message?has_content && (message.type != 'warning' || !isAppInitiatedAction??)>
                        <div class="alert-${message.type} ${properties.kcAlertClass!} pf-m-<#if message.type = 'error'>danger<#else>${message.type}</#if>">
                            <div class="pf-c-alert__icon">
                                <#if message.type = 'success'><span class="${properties.kcFeedbackSuccessIcon!}"></span></#if>
                                <#if message.type = 'warning'><span class="${properties.kcFeedbackWarningIcon!}"></span></#if>
                                <#if message.type = 'error'><span class="${properties.kcFeedbackErrorIcon!}"></span></#if>
                                <#if message.type = 'info'><span class="${properties.kcFeedbackInfoIcon!}"></span></#if>
                            </div>
                            <span class="${properties.kcAlertTitleClass!}">${kcSanitize(message.summary)?no_esc}</span>
                        </div>
                    </#if>

                    <#nested "form">

                    <#if auth?has_content && auth.showTryAnotherWayLink()>
                        <form id="kc-select-try-another-way-form" action="${url.loginAction}" method="post">
                            <div class="${properties.kcFormGroupClass!}">
                                <input type="hidden" name="tryAnotherWay" value="on"/>
                                <a href="#" id="try-another-way"
                                   onclick="document.forms['kc-select-try-another-way-form'].requestSubmit();return false;">${msg("doTryAnotherWay")}</a>
                            </div>
                        </form>
                    </#if>

                    <#nested "socialProviders">

                    <#if displayInfo>
                        <div id="kc-info" class="${properties.kcSignUpClass!}">
                            <div id="kc-info-wrapper" class="${properties.kcInfoAreaWrapperClass!}">
                                <#nested "info">
                            </div>
                        </div>
                    </#if>
                </div>
            </div>

            <div class="playsay-help">${msg("playsayLoginAccessHelp")}</div>
            <div class="playsay-return"><a href="https://play-and-say.ru">${msg("playsayLoginReturnToSite")}</a></div>

            <@loginFooter.content/>
        </section>
    </main>
</body>
</html>
</#macro>
