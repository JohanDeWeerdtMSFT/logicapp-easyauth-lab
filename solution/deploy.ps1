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
    Base invoke URL of the Logic App HTTP trigger (no SAS signature needed!).
    Format: https://<logicapp-name>.azurewebsites.net/api/httpTriggerWorkflow/triggers/When_a_HTTP_request_is_received/invoke?api-version=2022-05-01
    Why no signature? Managed Identity bearer token provides authentication instead.

.PARAMETER LogicAppAudience
    Entra ID App Registration client ID for the Logic App, in URI format.
    Format: api://<client-id>
    Find it: Entra ID → App Registrations → <your Logic App registration> → Application (client) ID

.PARAMETER TenantId
    Entra ID tenant ID.
    Find it: Entra ID → Overview → Tenant ID

.EXAMPLE
    .\deploy.ps1 `
      -FunctionAppName "la-easyauth-lab-dev-caller-xyz123" `
      -ResourceGroupName "rg-la-easyauth-lab-dev" `
    -LogicAppUrl "https://la-easyauth-lab-dev-la-xyz123.azurewebsites.net/api/httpTriggerWorkflow/triggers/When_a_HTTP_request_is_received/invoke?api-version=2022-05-01" `
      -LogicAppAudience "api://786594a8-6b38-40cf-8c6b-d434b539dd46" `
      -TenantId "00922812-791e-41c8-a99e-45c3ed784cf5"
    
    Note: No SAS signature (sig=...) is required! The bearer token authenticates the request.
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
az webapp deploy `
    --name $FunctionAppName `
    --resource-group $ResourceGroupName `
    --src-path $ZipPath `
    --type zip `
    --clean true `
    --restart true `
    --track-status true
if ($LASTEXITCODE -ne 0) { throw "az webapp deploy failed" }

# ── 4. Configure application settings (NO SECRETS!) ────────────────────────────
Write-Host ""
Write-Host "=== Step 4: Configure application settings ===" -ForegroundColor Cyan
Write-Host "Note: These settings contain NO SECRETS or SAS signatures." -ForegroundColor Green
Write-Host "      Authentication uses Managed Identity bearer tokens instead." -ForegroundColor Green
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
Write-Host "The HTTP trigger requires a Function key." -ForegroundColor Yellow
Write-Host "Retrieve it with 'az functionapp keys list', keep it in memory, and send it in the x-functions-key header." -ForegroundColor DarkYellow
Write-Host ""
Write-Host "Monitor in Application Insights:"
Write-Host "  Azure Portal → Application Insights → Logs → traces | where message contains 'Bearer token'" -ForegroundColor DarkYellow
