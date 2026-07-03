<#
.SYNOPSIS
    Deploy Azure Easy Auth Lab infrastructure (Function App + Logic App + supporting services)

.DESCRIPTION
    This script automates the complete deployment of the Azure Easy Auth lab.
    
    What it does:
    1. Reads configuration from .env file
    2. Validates Azure CLI and subscription access
    3. Creates resource group
    4. Validates Bicep templates
    5. Deploys infrastructure (VNet, storage, apps, Easy Auth)
    6. Deploys workflow to Logic App
    7. Displays deployed resource information

    What you need:
    • .env file in current directory (copy from .env.example)
    • Azure CLI installed and logged in
    • Contributor role on Azure subscription

.EXAMPLE
    # Basic usage (reads .env automatically)
    ./setup.ps1

.EXAMPLE
    # Override environment
    ./setup.ps1 -EnvironmentName "test"

.EXAMPLE
    # Dry run (shows what will be deployed, doesn't create)
    ./setup.ps1 -WhatIf

.PARAMETER EnvironmentName
    Environment name (dev, test, prod). Overrides ENVIRONMENT_NAME from .env

.PARAMETER Location
    Azure region. Overrides AZURE_REGION from .env

.PARAMETER WhatIf
    Show deployment plan without creating resources
#>

[CmdletBinding()]
param(
    [string] $EnvironmentName,
    [string] $Location,
    [switch] $WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Azure Easy Auth Lab — Infrastructure Deployment                   ║" -ForegroundColor Cyan
Write-Host "║                                                                    ║" -ForegroundColor Cyan
Write-Host "║  This script will create:                                          ║" -ForegroundColor Cyan
Write-Host "║    • Resource Group                                                ║" -ForegroundColor Cyan
Write-Host "║    • Virtual Network with 2 subnets                                ║" -ForegroundColor Cyan
Write-Host "║    • Logic App Standard (HTTP-triggered workflow)                  ║" -ForegroundColor Cyan
Write-Host "║    • Function App (calls Logic App securely)                       ║" -ForegroundColor Cyan
Write-Host "║    • Easy Auth (Microsoft Entra ID authentication)                 ║" -ForegroundColor Cyan
Write-Host "║    • Application Insights (monitoring/logging)                     ║" -ForegroundColor Cyan
Write-Host "║    • Private Endpoints & DNS Zones                                 ║" -ForegroundColor Cyan
Write-Host "║                                                                    ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ Step 1: Load configuration from .env file                                  │
# └─────────────────────────────────────────────────────────────────────────────┘

Write-Host "Step 1: Loading configuration..." -ForegroundColor Yellow

$EnvFile = ".env"
if (-not (Test-Path $EnvFile)) {
    Write-Host ""
    Write-Host "ERROR: .env file not found!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please copy .env.example to .env and fill in your Azure values:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  cp .env.example .env" -ForegroundColor Cyan
    Write-Host "  notepad .env" -ForegroundColor Cyan
    Write-Host ""
    exit 1
}

# Parse .env file (simple key=value format, skip comments and empty lines)
$EnvConfig = @{}
Get-Content $EnvFile | Where-Object { $_ -and -not $_.StartsWith("#") } | ForEach-Object {
    $parts = $_ -split '=', 2
    if ($parts.Count -eq 2) {
        $EnvConfig[$parts[0].Trim()] = $parts[1].Trim()
    }
}

# Load from .env, allow command-line overrides
$SubscriptionId = $EnvConfig['AZURE_SUBSCRIPTION_ID']
$TenantId = $EnvConfig['AZURE_TENANT_ID']
$Region = if ($Location) { $Location } else { $EnvConfig['AZURE_REGION'] -or 'westeurope' }
$EnvName = if ($EnvironmentName) { $EnvironmentName } else { $EnvConfig['ENVIRONMENT_NAME'] -or 'dev' }
$UserEmail = $EnvConfig['YOUR_EMAIL'] -or 'lab-user'

if (-not $SubscriptionId -or -not $TenantId) {
    Write-Host "ERROR: AZURE_SUBSCRIPTION_ID and AZURE_TENANT_ID must be set in .env" -ForegroundColor Red
    exit 1
}

Write-Host "✓ Configuration loaded" -ForegroundColor Green
Write-Host "  Subscription: $SubscriptionId" -ForegroundColor Gray
Write-Host "  Tenant: $TenantId" -ForegroundColor Gray
Write-Host "  Region: $Region" -ForegroundColor Gray
Write-Host "  Environment: $EnvName" -ForegroundColor Gray
Write-Host ""

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ Step 2: Validate Azure CLI and authentication                              │
# └─────────────────────────────────────────────────────────────────────────────┘

Write-Host "Step 2: Validating Azure CLI and authentication..." -ForegroundColor Yellow

# Check if Azure CLI is installed
$AzVersion = az --version 2>$null
if (-not $AzVersion) {
    Write-Host "ERROR: Azure CLI is not installed or not in PATH" -ForegroundColor Red
    Write-Host "Download: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli" -ForegroundColor Yellow
    exit 1
}

# Check if user is logged in
$CurrentAccount = az account show --query "name" -o tsv 2>$null
if (-not $CurrentAccount) {
    Write-Host "ERROR: Not logged in to Azure. Run: az login" -ForegroundColor Red
    exit 1
}

# Verify subscription access
$SubExists = az account subscription list --query "[?id=='$SubscriptionId']" -o json 2>$null | ConvertFrom-Json
if (-not $SubExists -or $SubExists.Count -eq 0) {
    Write-Host "ERROR: Subscription $SubscriptionId not found or you don't have access" -ForegroundColor Red
    Write-Host "Available subscriptions:" -ForegroundColor Yellow
    az account list --query "[].{name:name, subscriptionId:id}" -o table
    exit 1
}

# Set subscription as active
az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) { throw "Failed to set subscription" }

Write-Host "✓ Logged in as: $CurrentAccount" -ForegroundColor Green
Write-Host "✓ Using subscription: $SubscriptionId" -ForegroundColor Green
Write-Host ""

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ Step 3: Generate resource names and create resource group                  │
# └─────────────────────────────────────────────────────────────────────────────┘

Write-Host "Step 3: Creating resource group..." -ForegroundColor Yellow

$ResourceGroupName = "rg-easyauth-lab-$EnvName"
$BaseName = "la-easyauth-lab-$EnvName"

Write-Host "  Resource Group: $ResourceGroupName" -ForegroundColor Gray
Write-Host "  Base Name: $BaseName" -ForegroundColor Gray

# Check if resource group already exists
$RgExists = az group exists --name $ResourceGroupName -o tsv
if ($RgExists -eq "true") {
    Write-Host "✓ Resource group already exists: $ResourceGroupName" -ForegroundColor Green
} else {
    Write-Host "  Creating resource group..." -ForegroundColor Gray
    if ($WhatIf) {
        Write-Host "  [WhatIf] Would create resource group: $ResourceGroupName" -ForegroundColor Cyan
    } else {
        az group create `
            --name $ResourceGroupName `
            --location $Region `
            --tags Owner="$UserEmail" Lab="easyauth" Environment="$EnvName" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Failed to create resource group" }
        Write-Host "✓ Resource group created" -ForegroundColor Green
    }
}

Write-Host ""

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ Step 4: Validate Bicep template                                            │
# └─────────────────────────────────────────────────────────────────────────────┘

Write-Host "Step 4: Validating Bicep template..." -ForegroundColor Yellow

$BicepFile = "infra/main.bicep"
if (-not (Test-Path $BicepFile)) {
    Write-Host "ERROR: Bicep template not found at $BicepFile" -ForegroundColor Red
    exit 1
}

if ($WhatIf) {
    Write-Host "  [WhatIf] Would validate: $BicepFile" -ForegroundColor Cyan
} else {
    az bicep build --file $BicepFile --output-format json | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Bicep validation failed" }
    Write-Host "✓ Bicep template is valid" -ForegroundColor Green
}

Write-Host ""

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ Step 5: Deploy infrastructure with Bicep                                   │
# └─────────────────────────────────────────────────────────────────────────────┘

Write-Host "Step 5: Deploying infrastructure..." -ForegroundColor Yellow
Write-Host "  (This may take 15-20 minutes; Azure provisions resources)" -ForegroundColor Gray
Write-Host ""

$ParamFile = "infra/params/dev-$Region.bicepparam"
if (-not (Test-Path $ParamFile)) {
    $ParamFile = "infra/params/dev-westeurope.bicepparam"
    Write-Host "  Using default parameters: $ParamFile" -ForegroundColor Gray
}

if ($WhatIf) {
    Write-Host "  [WhatIf] Would deploy template:" -ForegroundColor Cyan
    Write-Host "    az deployment group what-if \" -ForegroundColor Cyan
    Write-Host "      --resource-group $ResourceGroupName \" -ForegroundColor Cyan
    Write-Host "      --template-file $BicepFile \" -ForegroundColor Cyan
    Write-Host "      --parameters $ParamFile" -ForegroundColor Cyan
    Write-Host "      environmentName=$EnvName" -ForegroundColor Cyan
} else {
    $DeploymentName = "easyauth-lab-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    
    az deployment group create `
        --name $DeploymentName `
        --resource-group $ResourceGroupName `
        --template-file $BicepFile `
        --parameters `
            environmentName=$EnvName `
            location=$Region | Out-Null
    
    if ($LASTEXITCODE -ne 0) { throw "Deployment failed" }
    Write-Host "✓ Infrastructure deployed successfully" -ForegroundColor Green
}

Write-Host ""

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ Step 6: Display deployed resources and next steps                          │
# └─────────────────────────────────────────────────────────────────────────────┘

Write-Host "Step 6: Deployment Summary" -ForegroundColor Yellow

if (-not $WhatIf) {
    Write-Host ""
    Write-Host "Resources deployed:" -ForegroundColor Green
    
    # Get resource details
    $Resources = az resource list --resource-group $ResourceGroupName --query "[].{name:name, type:type}" -o json | ConvertFrom-Json
    $Resources | ForEach-Object {
        $TypeShort = $_.type -split '/' | Select-Object -Last 1
        Write-Host "  • $($_.name) [$TypeShort]" -ForegroundColor Gray
    }
    
    # Get resource group ID
    Write-Host ""
    Write-Host "Quick Reference:" -ForegroundColor Green
    Write-Host "  Resource Group: $ResourceGroupName" -ForegroundColor Gray
    Write-Host "  Location: $Region" -ForegroundColor Gray
    Write-Host "  Subscription ID: $SubscriptionId" -ForegroundColor Gray
    
    # Store values for next steps
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Cyan
    Write-Host "  1. Deploy Function App code:" -ForegroundColor Gray
    Write-Host "     cd solution" -ForegroundColor Gray
    Write-Host "     .\deploy.ps1 -FunctionAppName <func-app-name> -ResourceGroupName $ResourceGroupName" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  2. Read the lab documentation:" -ForegroundColor Gray
    Write-Host "     docs/lab3-passwordless-managed-identity-easy-auth.md" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  3. Test the bearer token flow:" -ForegroundColor Gray
    Write-Host "     curl https://<func-app-name>.azurewebsites.net/api/CallLogicApp" -ForegroundColor Gray
    Write-Host ""
}

Write-Host ""
Write-Host "✓ Setup complete!" -ForegroundColor Green
Write-Host ""
