<#
.SYNOPSIS
    Deploys the Logic App Easy Auth lab infrastructure (Lane B).

.DESCRIPTION
    Orchestrates resource group creation and Bicep deployment for the
    Logic App Standard Easy Auth validation lab.

.EXAMPLE
    .\deploy.ps1 -EntraAppClientId "00000000-..." -EntraAppTenantId "00000000-..."
    .\deploy.ps1 -EntraAppClientId "00000000-..." -EntraAppTenantId "00000000-..." -WhatIf
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidatePattern('^[a-z0-9]+$')]
    [string]$EnvironmentName = 'dev',

    [string]$Location = 'westeurope',

    [ValidateSet('Return401', 'AllowAnonymous')]
    [string]$EasyAuthMode = 'Return401',

    [Parameter(Mandatory)]
    [string]$EntraAppClientId,

    [Parameter(Mandatory)]
    [string]$EntraAppTenantId,

    [switch]$DeployFunctionApp
)

$ErrorActionPreference = 'Stop'

# ── Variables ────────────────────────────────────────────────────────────────
$namingPrefix       = 'la-easyauth-lab'
$resourceGroupName  = "rg-${namingPrefix}-${EnvironmentName}"
$subscriptionId     = '6851693c-0b74-4462-8da8-cd498b088827'
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
Write-Host "  Subscription  : $subscriptionId"
Write-Host "  Bicep Template: $bicepFile"
Write-Host "  Mode          : $(if ($WhatIf) { 'WHAT-IF (dry run)' } else { 'DEPLOY' })"
Write-Host "  Function App  : $(if ($DeployFunctionApp) { 'Yes' } else { 'No' })"
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
        -Arguments @('account', 'set', '--subscription', $subscriptionId)

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
        'deployFunctionApp=' + $DeployFunctionApp.ToString().ToLower()
    )

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
        Write-Host "  2. Run validation (Track B — trigger security):"
        Write-Host "       .\validate.ps1 -LogicAppName $logicAppName -ResourceGroupName $resourceGroupName ``"
        Write-Host "           -EntraAppClientId $EntraAppClientId -EntraAppTenantId $EntraAppTenantId ``"
        Write-Host "           -ClientSecret (Read-Host -AsSecureString 'Client secret')"
        Write-Host ""
        Write-Host "  3. Run validation (Track A — portal manageability):"
        Write-Host "       .\validate.ps1 ... -TestMode TrackA"
        Write-Host ""
        Write-Host "  4. Portal verification (manual):"
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
