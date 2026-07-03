<#
.SYNOPSIS
    Deploys CallerFunctionApp to an existing Azure Function App and configures
    the three required application settings.

.DESCRIPTION
    1. Builds and publishes the .NET 8 isolated Function App.
    2. Deploys the zip package to the target Azure Function App.
    3. Sets LOGIC_APP_URL, LOGIC_APP_AUDIENCE, and WEBSITE_AUTH_AAD_ALLOWED_TENANTS
       as application settings.

.PARAMETER FunctionAppName
    Name of the Azure Function App to deploy to.
    Find it: az functionapp list --query "[].name" -o table

.PARAMETER ResourceGroupName
    Resource group that contains the Function App.

.PARAMETER LogicAppUrl
    Full callback URL of the Logic App HTTP trigger (including SAS parameters).
    Find it: Azure Portal → Logic App → Workflows → httpTriggerWorkflow → Overview → Callback URL

.PARAMETER LogicAppAudience
    Entra ID App Registration client ID for the Logic App, in URI format.
    Format: api://<client-id>
    Find it: Entra ID → App Registrations → <your Logic App registration> → Application (client) ID

.PARAMETER TenantId
    Entra ID tenant ID.
    Find it: Entra ID → Overview → Tenant ID

.EXAMPLE
    .\deploy.ps1 `
      -FunctionAppName "la-easyauth-lab-dev-func-abc123" `
      -ResourceGroupName "rg-la-easyauth-lab-dev" `
      -LogicAppUrl "https://la-easyauth-lab-dev-logic-abc123.azurewebsites.net/api/workflows/httpTriggerWorkflow/triggers/manual/invoke?api-version=2022-05-01&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=<sig>" `
      -LogicAppAudience "api://a1b2c3d4-e5f6-7890-abcd-ef1234567890" `
      -TenantId "00922812-791e-41c8-a99e-45c3ed784cf5"
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)] [string] $FunctionAppName,
    [Parameter(Mandatory)] [string] $ResourceGroupName,
    [Parameter(Mandatory)] [string] $LogicAppUrl,
    [Parameter(Mandatory)] [string] $LogicAppAudience,
    [Parameter(Mandatory)] [string] $TenantId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectDir  = Join-Path $PSScriptRoot "CallerFunctionApp"
$PublishDir  = Join-Path $ProjectDir "publish"
$ZipPath     = Join-Path $PSScriptRoot "CallerFunctionApp.zip"

# ── 1. Build & publish ────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=== Step 1: Build and publish ===" -ForegroundColor Cyan
dotnet publish "$ProjectDir/CallerFunctionApp.csproj" `
    --configuration Release `
    --output $PublishDir `
    --runtime win-x64 `
    --self-contained false
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed" }

# ── 2. Create zip package ─────────────────────────────────────────────────────
Write-Host ""
Write-Host "=== Step 2: Create deployment zip ===" -ForegroundColor Cyan
if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
Compress-Archive -Path "$PublishDir\*" -DestinationPath $ZipPath
Write-Host "Package: $ZipPath"

# ── 3. Deploy to Azure ────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=== Step 3: Deploy to Azure Function App ===" -ForegroundColor Cyan
Write-Host "Target: $FunctionAppName (RG: $ResourceGroupName)"
az functionapp deployment source config-zip `
    --name $FunctionAppName `
    --resource-group $ResourceGroupName `
    --src $ZipPath
if ($LASTEXITCODE -ne 0) { throw "az functionapp deployment failed" }

# ── 4. Configure application settings ────────────────────────────────────────
Write-Host ""
Write-Host "=== Step 4: Configure application settings ===" -ForegroundColor Cyan
az functionapp config appsettings set `
    --name $FunctionAppName `
    --resource-group $ResourceGroupName `
    --settings `
        "LOGIC_APP_URL=$LogicAppUrl" `
        "LOGIC_APP_AUDIENCE=$LogicAppAudience" `
        "WEBSITE_AUTH_AAD_ALLOWED_TENANTS=$TenantId"
if ($LASTEXITCODE -ne 0) { throw "Failed to configure app settings" }

# ── 5. Confirm deployed settings ──────────────────────────────────────────────
Write-Host ""
Write-Host "=== Step 5: Verify configuration ===" -ForegroundColor Cyan
az functionapp config appsettings list `
    --name $FunctionAppName `
    --resource-group $ResourceGroupName `
    --query "[?name=='LOGIC_APP_URL' || name=='LOGIC_APP_AUDIENCE' || name=='WEBSITE_AUTH_AAD_ALLOWED_TENANTS']" `
    --output table

# ── Done ──────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=== Deployment complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Function App URL:"
$hostname = az functionapp show `
    --name $FunctionAppName `
    --resource-group $ResourceGroupName `
    --query "defaultHostName" -o tsv
Write-Host "  https://$hostname/api/CallLogicApp" -ForegroundColor Yellow
Write-Host ""
Write-Host "Test with:"
Write-Host "  curl -X POST https://$hostname/api/CallLogicApp" -ForegroundColor DarkYellow
Write-Host ""
Write-Host "Monitor in Application Insights:"
Write-Host "  Azure Portal → Application Insights → Logs → traces | where message contains 'Bearer token'" -ForegroundColor DarkYellow
