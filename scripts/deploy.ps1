<#
.SYNOPSIS
    Deploys the Logic App Easy Auth lab infrastructure (Lane B).

.DESCRIPTION
    Orchestrates the complete infrastructure deployment for the Logic App Standard
    Easy Auth validation lab, including resource group creation, ARM template
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
    - Generated ARM template must exist at infra\main.json
    - Required Entra app client ID and tenant ID for Easy Auth configuration
        - Permission to create resources and role assignments (Owner, or Contributor
            plus User Access Administrator/RBAC Administrator)

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

    [switch]$EnablePrivateAppNetworking,

    [string]$FuncCallerEntraClientId = '',

    [string]$EasyAuthAllowedPrincipalOverride = ''
)

$ErrorActionPreference = 'Stop'
$isWhatIf = [bool]$WhatIfPreference

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

if ($EnablePrivateAppNetworking -and -not $DeployFuncCallerDemo) {
    throw '-EnablePrivateAppNetworking requires -DeployFuncCallerDemo because the caller demo provisions the required VNet and subnets.'
}

# ── Variables ────────────────────────────────────────────────────────────────
$namingPrefix       = 'la-easyauth-lab'
$resourceGroupName  = "rg-${namingPrefix}-${EnvironmentName}"
$templateFile       = Join-Path $PSScriptRoot '..\infra\main.json'
$deploymentName     = "easyauth-lab-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$azureCliPath       = Get-Command az -CommandType Application -ErrorAction Stop |
    Select-Object -First 1 -ExpandProperty Source

Import-Module (Join-Path $PSScriptRoot 'lib' 'EasyAuthLab.psm1') -Force

Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host   "║  Logic App Easy Auth Lab — Deployment Orchestrator          ║" -ForegroundColor Cyan
Write-Host   "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Environment   : $EnvironmentName"
Write-Host "  Location      : $Location"
Write-Host "  Easy Auth Mode: $EasyAuthMode"
Write-Host "  Resource Group: $resourceGroupName"
Write-Host "  Subscription  : $SubscriptionId"
Write-Host "  ARM Template  : $templateFile"
Write-Host "  Mode          : $(if ($isWhatIf) { 'WHAT-IF (dry run)' } else { 'DEPLOY' })"
Write-Host "  Function App  : $(if ($DeployFunctionApp) { 'Yes' } else { 'No' })"
Write-Host "  Caller Demo   : $(if ($DeployFuncCallerDemo) { 'Yes' } else { 'No' })"
Write-Host "  Private Ingress: $(if ($EnablePrivateAppNetworking) { 'Yes' } else { 'No (classroom default)' })"
Write-Host ""

# ── Helpers ──────────────────────────────────────────────────────────────────
function Invoke-AzCommand {
    param([string]$Description, [string[]]$Arguments)
    Write-Host "→ $Description" -ForegroundColor Yellow
    $previousErrorActionPreference = $ErrorActionPreference
    $previousNativeErrorPreference = $PSNativeCommandUseErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $PSNativeCommandUseErrorActionPreference = $false
        $output = & $azureCliPath @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
        $PSNativeCommandUseErrorActionPreference = $previousNativeErrorPreference
    }
    if ($exitCode -ne 0) {
        throw "az command failed (exit $exitCode): $output"
    }
    return $output
}

# ── Pre-flight ───────────────────────────────────────────────────────────────
try {
    Write-Host "── Pre-flight checks ──────────────────────────────────────" -ForegroundColor DarkGray

    # main.json is generated from main.bicep and committed so deployment does
    # not depend on Azure CLI's on-the-fly Bicep compilation path.
    if (-not (Test-Path $templateFile)) {
        throw "Generated ARM template not found at '$templateFile'. Build infra/main.bicep before deploying."
    }

    # Set subscription context
    Invoke-AzCommand -Description "Setting subscription context" `
        -Arguments @('account', 'set', '--subscription', $SubscriptionId)

    # Verify logged-in identity
    $accountJson = Invoke-AzCommand -Description "Verifying Azure CLI login" `
        -Arguments @('account', 'show', '--output', 'json')
    $account = $accountJson | ConvertFrom-Json
    Write-Host "  Logged in as: $($account.user.name) ($($account.user.type))" -ForegroundColor Green

    # Ensure Entra can issue managed-identity tokens for the Logic App API audience.
    $logicAppAudience = "api://$EntraAppClientId"
    $logicAppRegistrationJson = Invoke-AzCommand -Description "Verifying Logic App Entra app registration" `
        -Arguments @('ad', 'app', 'show', '--id', $EntraAppClientId, '--output', 'json')
    $logicAppRegistration = $logicAppRegistrationJson | ConvertFrom-Json

    if ($logicAppRegistration.identifierUris -notcontains $logicAppAudience) {
        if ($isWhatIf) {
            Write-Warning "Logic App Application ID URI is missing. Deployment will set '$logicAppAudience'."
        }
        else {
            $logicAppIdentifierUris = @($logicAppRegistration.identifierUris) + $logicAppAudience |
                Select-Object -Unique
            Invoke-AzCommand -Description "Setting Logic App Application ID URI" `
                -Arguments (@('ad', 'app', 'update', '--id', $EntraAppClientId, '--identifier-uris') + $logicAppIdentifierUris)
        }
    }

    $logicAppServicePrincipalId = az ad sp list `
        --filter "appId eq '$EntraAppClientId'" `
        --query '[0].id' `
        --output tsv
    if ($LASTEXITCODE -ne 0) {
        throw "Could not check the Logic App service principal for app ID '$EntraAppClientId'."
    }

    if ([string]::IsNullOrWhiteSpace($logicAppServicePrincipalId)) {
        if ($isWhatIf) {
            Write-Warning 'Logic App service principal is missing. Deployment will create it.'
        }
        else {
            Invoke-AzCommand -Description "Creating Logic App service principal" `
                -Arguments @('ad', 'sp', 'create', '--id', $EntraAppClientId, '--output', 'none')
        }
    }

    if ($DeployFuncCallerDemo) {
        if ([string]::IsNullOrWhiteSpace($FuncCallerEntraClientId)) {
            throw '-FuncCallerEntraClientId is required when -DeployFuncCallerDemo is specified.'
        }

        Invoke-AzCommand -Description "Verifying caller Function Entra app registration" `
            -Arguments @('ad', 'app', 'show', '--id', $FuncCallerEntraClientId, '--output', 'none') | Out-Null
    }

    # ── Step 1: Resource Group ───────────────────────────────────────────────
    Write-Host "`n── Step 1: Resource Group ─────────────────────────────────" -ForegroundColor DarkGray

    $rgExists = az group exists --name $resourceGroupName 2>$null
    if ($rgExists -eq 'true') {
        Write-Host "  Resource group '$resourceGroupName' already exists." -ForegroundColor Green
    }
    elseif ($isWhatIf) {
        throw "Resource group '$resourceGroupName' does not exist. Create it explicitly before running -WhatIf; preview mode does not create resources."
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
        'deployFuncCallerDemo=' + $DeployFuncCallerDemo.ToString().ToLower(),
        'enablePrivateAppNetworking=' + $EnablePrivateAppNetworking.ToString().ToLower()
    )

    if ($DeployFuncCallerDemo) {
        if ([string]::IsNullOrWhiteSpace($FuncCallerEntraClientId)) {
            throw "-FuncCallerEntraClientId is required when -DeployFuncCallerDemo is specified."
        }
        $deployParams += 'funcCallerEntraClientId=' + $FuncCallerEntraClientId
    }

    if (-not [string]::IsNullOrWhiteSpace($EasyAuthAllowedPrincipalOverride)) {
        $deployParams += 'easyAuthAllowedPrincipalOverride=' + $EasyAuthAllowedPrincipalOverride
    }

    # ── Step 2/3: What-If or Deploy ─────────────────────────────────────────
    if ($isWhatIf) {
        Write-Host "`n── Step 2: What-If Analysis ───────────────────────────────" -ForegroundColor DarkGray

        $whatIfArgs = @(
            'deployment', 'group', 'what-if',
            '--resource-group', $resourceGroupName,
            '--template-file', $templateFile,
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
            '--template-file', $templateFile,
            '--name', $deploymentName,
            '--mode', 'Incremental',
            '--only-show-errors',
            '--output', 'none'
        )
        foreach ($p in $deployParams) { $deployArgs += '--parameters'; $deployArgs += $p }

        Invoke-AzCommand -Description "Creating deployment '$deploymentName'" -Arguments $deployArgs | Out-Null
        $deploymentOutputRaw = Invoke-AzCommand -Description "Reading deployment '$deploymentName' outputs" `
            -Arguments @(
                'deployment', 'group', 'show',
                '--resource-group', $resourceGroupName,
                '--name', $deploymentName,
                '--only-show-errors',
                '--output', 'json'
            )
        $deployment = ($deploymentOutputRaw -join '') | ConvertFrom-Json

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

        # ── Step 3b: Effective storage policy validation ─────────────────────
        # The template requests the WS1-compatible combination of private ingress
        # (publicNetworkAccess = Disabled) and Shared Key authorization
        # (allowSharedKeyAccess = true). An inherited management-group Modify
        # policy can silently override the second value, so validate what Azure
        # actually stored instead of trusting deployment success.
        if ($DeployFuncCallerDemo -and $outputs.PSObject.Properties['storageAccountName']) {
            $storageAccountName = $outputs.storageAccountName.value

            $storagePropertiesRaw = Invoke-AzCommand -Description "Reading effective storage account authorization settings" `
                -Arguments @(
                    'storage', 'account', 'show',
                    '--subscription', $SubscriptionId,
                    '--resource-group', $resourceGroupName,
                    '--name', $storageAccountName,
                    '--query', '{publicNetworkAccess:publicNetworkAccess,allowSharedKeyAccess:allowSharedKeyAccess}',
                    '--output', 'json'
                )
            $storageProperties = ($storagePropertiesRaw -join '') | ConvertFrom-Json

            $storagePolicy = Test-StorageAuthorizationPolicy `
                -StorageAccountName $storageAccountName `
                -PublicNetworkAccess $storageProperties.publicNetworkAccess `
                -AllowSharedKeyAccess $storageProperties.allowSharedKeyAccess

            if (-not $storagePolicy.compliant) {
                throw $storagePolicy.message
            }

            Write-Host "  Storage public access: Disabled" -ForegroundColor Green
            Write-Host "  Storage Shared Key   : Allowed (WS1 requirement)" -ForegroundColor Green
        }

        # Incremental ARM deployments do not remove resources that disappear from
        # the template. Explicitly remove retained private ingress when the public
        # classroom mode is selected.
        if (-not $EnablePrivateAppNetworking) {
            $privateEndpointName = "pe-$logicAppName"
            $privateEndpointId = az network private-endpoint show `
                --subscription $SubscriptionId `
                --resource-group $resourceGroupName `
                --name $privateEndpointName `
                --query id `
                --output tsv 2>$null

            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($privateEndpointId)) {
                Invoke-AzCommand -Description "Removing retained Logic App private endpoint for public classroom mode" `
                    -Arguments @(
                        'network', 'private-endpoint', 'delete',
                        '--subscription', $SubscriptionId,
                        '--resource-group', $resourceGroupName,
                        '--name', $privateEndpointName
                    ) | Out-Null
            }

            $privateDnsZoneName = 'privatelink.azurewebsites.net'
            $privateDnsZoneId = az network private-dns zone show `
                --subscription $SubscriptionId `
                --resource-group $resourceGroupName `
                --name $privateDnsZoneName `
                --query id `
                --output tsv 2>$null

            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($privateDnsZoneId)) {
                $privateDnsLinkName = "${namingPrefix}-${EnvironmentName}-vnet-link"
                $privateDnsLinkId = az network private-dns link vnet show `
                    --subscription $SubscriptionId `
                    --resource-group $resourceGroupName `
                    --zone-name $privateDnsZoneName `
                    --name $privateDnsLinkName `
                    --query id `
                    --output tsv 2>$null

                if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($privateDnsLinkId)) {
                    Invoke-AzCommand -Description "Removing retained App Service private DNS VNet link" `
                        -Arguments @(
                            'network', 'private-dns', 'link', 'vnet', 'delete',
                            '--subscription', $SubscriptionId,
                            '--resource-group', $resourceGroupName,
                            '--zone-name', $privateDnsZoneName,
                            '--name', $privateDnsLinkName,
                            '--yes'
                        ) | Out-Null
                }

                Invoke-AzCommand -Description "Removing retained App Service private DNS zone for public classroom mode" `
                    -Arguments @(
                        'network', 'private-dns', 'zone', 'delete',
                        '--subscription', $SubscriptionId,
                        '--resource-group', $resourceGroupName,
                        '--name', $privateDnsZoneName,
                        '--yes'
                    ) | Out-Null
            }
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
        Write-Host "  1. Publish the workflow artifact (requires access to the Logic App SCM endpoint):"
        Write-Host "       ./scripts/deploy-workflow.ps1 -SubscriptionId '$SubscriptionId' -ResourceGroupName '$resourceGroupName' -LogicAppName '$logicAppName'"
        Write-Host ""
        Write-Host "  2. Verify workflow health, deploy the caller code, and run the managed-identity tests:"
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
