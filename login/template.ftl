<#import "footer.ftl" as loginFooter>


<#macro registrationLayout bodyClass="" displayInfo=false displayMessage=true displayRequiredFields=false>
<!DOCTYPE html>
<html class="${properties.kcHtmlClass!}"<#if realm.internationalizationEnabled> lang="${locale.currentLanguageTag}" dir="${(locale.rtl)?then('rtl','ltr')}"</#if>>

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
    <link rel="icon" href="${url.resourcesPath}/img/favicon.ico" />
    <link href="${url.resourcesPath}/css/styles.css" rel="stylesheet" />
    <script type="module" src="${url.resourcesPath}/js/passwordVisibility.js"></script>
</head>

<body>


    <main>
      <div id="secondary-content">

      </div>
      <section id="primary-content">
        <h1>Welcome to Fédéré</h1>
        <#nested "form">
      </section>
    </main>


    <@loginFooter.content/>
  </div>
</div>
</body>
</html>
</#macro>
