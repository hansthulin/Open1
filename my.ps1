param (
    [string]$resourceGroup = "SecureApiRG",
    [string]$location = "westeurope",
    [string]$appName = "secureapihans$([System.Guid]::NewGuid().ToString().Substring(0, 8))",
    [string]$appServicePlan = "SecureApiPlan",
    [string]$publishFolder = ".\publish"
)

# Login to Azure if needed
az account show > $null 2>&1
if ($LASTEXITCODE -ne 0) {
    az login
}

Write-Host "`n===> Skapar resursgrupp och App Service..." -ForegroundColor Cyan
az group create --name $resourceGroup --location $location
az appservice plan create --name $appServicePlan --resource-group $resourceGroup --sku B1 --is-linux
az webapp create --resource-group $resourceGroup --plan $appServicePlan --name $appName --runtime "DOTNET|6.0" --deployment-local-git

$appUrl = "https://$appName.azurewebsites.net"

Write-Host "`n===> Skapar App Registration..." -ForegroundColor Cyan
$appReg = az ad app create --display-name $appName --sign-in-audience "AzureADandPersonalMicrosoftAccount" | ConvertFrom-Json
$clientId = $appReg.appId
$tenantId = az account show --query tenantId -o tsv

# Set Application ID URI
$apiIdUri = "api://$clientId"
az ad app update --id $clientId --identifier-uris $apiIdUri

# Add API permission: user_impersonation (standard)
az ad app permission add --id $clientId --api $clientId --api-permissions "user_impersonation=Scope"
az ad app permission grant --id $clientId --api $clientId --scope "user_impersonation"

Write-Host "`n===> Konfigurerar appsettings i Azure Web App..." -ForegroundColor Cyan
az webapp config appsettings set --name $appName --resource-group $resourceGroup --settings `
    "AzureAd__Instance=https://login.microsoftonline.com/" `
    "AzureAd__TenantId=$tenantId" `
    "AzureAd__ClientId=$clientId" `
    "AzureAd__Audience=$clientId"

Write-Host "`n===> Publicerar kod till Azure..." -ForegroundColor Cyan
if (-Not (Test-Path $publishFolder)) {
    Write-Error "Publish folder '$publishFolder' saknas. Kör 'dotnet publish -c Release' först."
    exit 1
}
$zipPath = "$env:TEMP\deploy.zip"
Compress-Archive -Path "$publishFolder\*" -DestinationPath $zipPath -Force
az webapp deployment source config-zip --resource-group $resourceGroup --name $appName --src $zipPath

Write-Host "`n===> KLART!" -ForegroundColor Green
Write-Host "Web API URL: $appUrl"
Write-Host "Azure AD App ClientId: $clientId"
Write-Host "`nLogga in med hans.thulin@hotmail.com efter att du konfigurerat åtkomst via Azure Portal."
