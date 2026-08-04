<#
.SYNOPSIS
    Deploys the Logic App Easy Auth lab infrastructure (Lane B).

.DESCRIPTION
    Orchestrates the complete infrastructure deployment for the Logic App Standard
    Easy Auth validation lab, including resource group creation, Bicep template
    deployment, and infrastructure configuration. This script automates the setup
    of Azure resources needed for testing Easy Auth authentication patterns with
    Logic App Standard workloads.
    
    The deployment includes:
    - Resource group provisioning in the specified location
    - Azure Networking resources (VNets, subnets, private endpoints)
    - Logic App Standard instance with Easy Auth configuration
    - Azure API Management integration (optional APIM lab)
    - Function App deployment (optional, controlled by -DeployFunctionApp switch)
    
    Prerequisites:
    - Azure CLI must be installed and authenticated
    - Bicep template must exist at infra\main.bicep
    - Required Entra app client ID and tenant ID for Easy Auth configuration
    - Appropriate Azure subscription permissions (Contributor or higher)

.EXAMPLE
    .\deploy.ps1 -SubscriptionId "00000000-..." -EntraAppClientId "00000000-..." -EntraAppTenantId "00000000-..."
    .\deploy.ps1 -EntraAppClientId "00000000-..." -EntraAppTenantId "00000000-..." -WhatIf

    When -SubscriptionId is omitted, the script reads AZURE_SUBSCRIPTION_ID from
    the process environment or the repository .env file.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidatePattern('^[a-z0-9]+$')]
    [string]$EnvironmentName = 'dev',

    [string]$Location = 'westeurope',

    [ValidateSet('Return401', 'AllowAnonymous')]
    [string]$EasyAuthMode = 'Return401',

    [string]$SubscriptionId = '',

    [Parameter(Mandatory)]
    [string]$EntraAppClientId,

    [Parameter(Mandatory)]
    [string]$EntraAppTenantId,

    [switch]$DeployFunctionApp,

    [switch]$DeployFuncCallerDemo,

    [string]$FuncCallerEntraClientId = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($SubscriptionId)) {
    $SubscriptionId = [Environment]::GetEnvironmentVariable('AZURE_SUBSCRIPTION_ID')
}

if ([string]::IsNullOrWhiteSpace($SubscriptionId)) {
    $envFile = Join-Path $PSScriptRoot '..\.env'
    if (Test-Path $envFile) {
        $subscriptionLine = Get-Content $envFile | Where-Object {
            $_ -match '^\s*AZURE_SUBSCRIPTION_ID\s*='
        } | Select-Object -First 1

        if ($subscriptionLine) {
            $SubscriptionId = ($subscriptionLine -split '=', 2)[1].Trim().Trim('"').Trim("'")
        }
    }
}

if ([string]::IsNullOrWhiteSpace($SubscriptionId) -or $SubscriptionId -eq 'your-subscription-id-here') {
    throw 'Provide -SubscriptionId, set AZURE_SUBSCRIPTION_ID, or configure AZURE_SUBSCRIPTION_ID in .env.'
}

# ── Variables ────────────────────────────────────────────────────────────────
$namingPrefix       = 'la-easyauth-lab'
$resourceGroupName  = "rg-${namingPrefix}-${EnvironmentName}"
$bicepFile          = Join-Path $PSScriptRoot '..\infra\main.bicep'
$deploymentName     = "easyauth-lab-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host   "║  Logic App Easy Auth Lab — Deployment Orchestrator          ║" -ForegroundColor Cyan
Write-Host   "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Environment   : $EnvironmentName"
Write-Host "  Location      : $Location"
Write-Host "  Easy Auth Mode: $EasyAuthMode"
Write-Host "  Resource Group: $resourceGroupName"
Write-Host "  Subscription  : $SubscriptionId"
Write-Host "  Bicep Template: $bicepFile"
Write-Host "  Mode          : $(if ($WhatIf) { 'WHAT-IF (dry run)' } else { 'DEPLOY' })"
Write-Host "  Function App  : $(if ($DeployFunctionApp) { 'Yes' } else { 'No' })"
Write-Host "  Caller Demo   : $(if ($DeployFuncCallerDemo) { 'Yes' } else { 'No' })"
Write-Host ""

# ── Helpers ──────────────────────────────────────────────────────────────────
function Invoke-AzCommand {
    param([string]$Description, [string[]]$Arguments)
    Write-Host "→ $Description" -ForegroundColor Yellow
    $output = & az @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "az command failed (exit $LASTEXITCODE): $output"
    }
    return $output
}

# ── Pre-flight ───────────────────────────────────────────────────────────────
try {
    Write-Host "── Pre-flight checks ──────────────────────────────────────" -ForegroundColor DarkGray

    # Verify Bicep file exists
    if (-not (Test-Path $bicepFile)) {
        throw "Bicep template not found at '$bicepFile'. Run Lane A first."
    }

    # Set subscription context
    Invoke-AzCommand -Description "Setting subscription context" `
        -Arguments @('account', 'set', '--subscription', $SubscriptionId)

    # Verify logged-in identity
    $accountJson = Invoke-AzCommand -Description "Verifying Azure CLI login" `
        -Arguments @('account', 'show', '--output', 'json')
    $account = $accountJson | ConvertFrom-Json
    Write-Host "  Logged in as: $($account.user.name) ($($account.user.type))" -ForegroundColor Green

    # ── Step 1: Resource Group ───────────────────────────────────────────────
    Write-Host "`n── Step 1: Resource Group ─────────────────────────────────" -ForegroundColor DarkGray

    $rgExists = az group exists --name $resourceGroupName 2>$null
    if ($rgExists -eq 'true') {
        Write-Host "  Resource group '$resourceGroupName' already exists." -ForegroundColor Green
    }
    else {
        Write-Host "  Creating resource group '$resourceGroupName' in '$Location'..." -ForegroundColor Yellow
        Invoke-AzCommand -Description "Creating resource group" `
            -Arguments @('group', 'create',
                '--name', $resourceGroupName,
                '--location', $Location,
                '--tags', "project=$namingPrefix", "environment=$EnvironmentName",
                '--output', 'none')
        Write-Host "  Resource group created." -ForegroundColor Green
    }

    # ── Build parameter set ──────────────────────────────────────────────────
    $unauthAction = if ($EasyAuthMode -eq 'Return401') { 'Return401' } else { 'AllowAnonymous' }

    $deployParams = @(
        'environmentName=' + $EnvironmentName,
        'location=' + $Location,
        'entraAppClientId=' + $EntraAppClientId,
        'entraAppTenantId=' + $EntraAppTenantId,
        'easyAuthMode=' + $unauthAction,
        'deployFunctionApp=' + $DeployFunctionApp.ToString().ToLower(),
        'deployFuncCallerDemo=' + $DeployFuncCallerDemo.ToString().ToLower()
    )

    if ($DeployFuncCallerDemo) {
        if ([string]::IsNullOrWhiteSpace($FuncCallerEntraClientId)) {
            throw "-FuncCallerEntraClientId is required when -DeployFuncCallerDemo is specified."
        }
        $deployParams += 'funcCallerEntraClientId=' + $FuncCallerEntraClientId
    }

    # ── Step 2/3: What-If or Deploy ─────────────────────────────────────────
    if ($WhatIf) {
        Write-Host "`n── Step 2: What-If Analysis ───────────────────────────────" -ForegroundColor DarkGray

        $whatIfArgs = @(
            'deployment', 'group', 'what-if',
            '--resource-group', $resourceGroupName,
            '--template-file', $bicepFile,
            '--name', $deploymentName,
            '--mode', 'Incremental'
        )
        foreach ($p in $deployParams) { $whatIfArgs += '--parameters'; $whatIfArgs += $p }

        $whatIfOutput = Invoke-AzCommand -Description "Running what-if analysis" -Arguments $whatIfArgs
        Write-Host $($whatIfOutput -join "`n")
    }
    else {
        Write-Host "`n── Step 2: Deploying Infrastructure ───────────────────────" -ForegroundColor DarkGray

        $deployArgs = @(
            'deployment', 'group', 'create',
            '--resource-group', $resourceGroupName,
            '--template-file', $bicepFile,
            '--name', $deploymentName,
            '--mode', 'Incremental',
            '--output', 'json'
        )
        foreach ($p in $deployParams) { $deployArgs += '--parameters'; $deployArgs += $p }

        $deployOutputRaw = Invoke-AzCommand -Description "Creating deployment '$deploymentName'" -Arguments $deployArgs
        $deployment = ($deployOutputRaw -join '') | ConvertFrom-Json

        # ── Step 3: Capture Outputs ──────────────────────────────────────────
        Write-Host "`n── Step 3: Deployment Outputs ─────────────────────────────" -ForegroundColor DarkGray

        $outputs = $deployment.properties.outputs

        $logicAppName     = $outputs.logicAppName.value
        $logicAppHostname = $outputs.logicAppDefaultHostname.value
        $logicAppId       = $outputs.logicAppResourceId.value

        Write-Host "  Logic App Name     : $logicAppName"
        Write-Host "  Logic App Hostname : $logicAppHostname"
        Write-Host "  Logic App ID       : $logicAppId"

        if ($DeployFunctionApp -and $outputs.PSObject.Properties['functionAppName']) {
            Write-Host "  Function App Name  : $($outputs.functionAppName.value)"
        }

        if ($DeployFuncCallerDemo) {
            $requiredCallerOutputs = @(
                'functionAppCallerName',
                'functionAppCallerHostname',
                'functionAppCallerPrincipalId'
            )
            foreach ($outputName in $requiredCallerOutputs) {
                if (-not $outputs.PSObject.Properties[$outputName] -or
                    [string]::IsNullOrWhiteSpace($outputs.$outputName.value)) {
                    throw "Deployment did not return required caller output '$outputName'."
                }
            }

            Write-Host "  Caller Function App: $($outputs.functionAppCallerName.value)"
            Write-Host "  Caller Hostname    : $($outputs.functionAppCallerHostname.value)"
            Write-Host "  Caller Principal ID: $($outputs.functionAppCallerPrincipalId.value)"
        }

        # ── Step 4: Summary ──────────────────────────────────────────────────
        Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
        Write-Host   "║  Deployment Succeeded                                        ║" -ForegroundColor Green
        Write-Host   "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
        Write-Host ""
        Write-Host "  Deployment Name  : $deploymentName"
        Write-Host "  Resource Group   : $resourceGroupName"
        Write-Host "  Easy Auth Mode   : $EasyAuthMode"
        Write-Host "  Endpoint         : https://$logicAppHostname"
        Write-Host ""
        Write-Host "  ── Next Steps ──" -ForegroundColor Cyan
        Write-Host "  1. Deploy workflow code:"
        Write-Host "       az logicapp deployment source config-zip --name $logicAppName --resource-group $resourceGroupName --src <zip-path>"
        Write-Host ""
        Write-Host "  2. Deploy the caller code and run the managed-identity validation guide:"
        Write-Host "       docs/lab3-testing-and-verification.md"
        Write-Host ""
        Write-Host "  3. Portal verification (manual):"
        Write-Host "       https://portal.azure.com/#@/resource$logicAppId/logicApp"
        Write-Host ""
    }
}
catch {
    Write-Host "`n✖ Deployment failed:" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  At: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor DarkRed
    exit 1
}
