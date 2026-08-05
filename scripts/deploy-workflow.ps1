<#
.SYNOPSIS
    Deploys an HTTP-trigger workflow to an existing Logic App Standard resource.

.EXAMPLE
    .\deploy-workflow.ps1 `
      -LogicAppName "la-easyauth-lab-dev-la-abc123" `
      -ResourceGroupName "rg-la-easyauth-lab-dev"

    When -SubscriptionId is omitted, the script reads AZURE_SUBSCRIPTION_ID from
    the process environment or the repository .env file.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$LogicAppName,

    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [string]$SubscriptionId = '',

    [string]$WorkflowName = 'httpTriggerWorkflow',

    [string]$WorkflowJsonPath = ''
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

$projectPath = Join-Path $PSScriptRoot '..\src'
$hostJsonPath = Join-Path $projectPath 'host.json'
if ([string]::IsNullOrWhiteSpace($WorkflowJsonPath)) {
    $WorkflowJsonPath = Join-Path $projectPath "$WorkflowName\workflow.json"
}

foreach ($requiredPath in @($hostJsonPath, $WorkflowJsonPath)) {
    if (-not (Test-Path $requiredPath -PathType Leaf)) {
        throw "Required Logic App project file not found at '$requiredPath'."
    }
}

$workflowArtifact = Get-Content $WorkflowJsonPath -Raw | ConvertFrom-Json
$expectedMethod = $workflowArtifact.definition.triggers.When_a_HTTP_request_is_received.inputs.method
if ([string]::IsNullOrWhiteSpace($expectedMethod)) {
    throw "Workflow '$WorkflowName' does not define an HTTP trigger method."
}

az account show --subscription $SubscriptionId --output none
if ($LASTEXITCODE -ne 0) {
    throw "Could not access Azure subscription '$SubscriptionId'."
}

$packageRoot = Join-Path ([System.IO.Path]::GetTempPath()) "logicapp-workflow-$([guid]::NewGuid())"
$packagePath = "$packageRoot.zip"
$stagedWorkflowPath = Join-Path $packageRoot $WorkflowName

try {
    New-Item -ItemType Directory -Path $stagedWorkflowPath -Force | Out-Null
    Copy-Item $hostJsonPath (Join-Path $packageRoot 'host.json')
    Copy-Item $WorkflowJsonPath (Join-Path $stagedWorkflowPath 'workflow.json')
    Compress-Archive -Path (Join-Path $packageRoot '*') -DestinationPath $packagePath -Force

    Write-Host "Deploying workflow '$WorkflowName' to Logic App '$LogicAppName'..." -ForegroundColor Cyan
    $deploymentOutput = az webapp deploy `
        --subscription $SubscriptionId `
        --resource-group $ResourceGroupName `
        --name $LogicAppName `
        --src-path $packagePath `
        --type zip `
        --clean true `
        --restart true `
        --track-status true `
        --output none 2>&1
    $deploymentOutput | Write-Host
    if ($LASTEXITCODE -ne 0) {
        $deploymentMessage = $deploymentOutput -join "`n"
        if ($deploymentMessage -match 'AccountUnusable|previously been signed out|appservice\.azure\.com') {
            throw "Workflow ZIP deployment requires a fresh App Service login. Run 'az login --tenant <tenant-id> --scope https://appservice.azure.com/.default', then retry."
        }

        throw "Workflow ZIP deployment failed for '$WorkflowName'. Check the Azure CLI output above and confirm this machine can reach the app's SCM endpoint."
    }
}
finally {
    Remove-Item $packageRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $packagePath -Force -ErrorAction SilentlyContinue
}

$managementUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/sites/$LogicAppName/workflows/$WorkflowName" + '?api-version=2023-12-01'
$deployedWorkflow = az rest --subscription $SubscriptionId --method get --uri $managementUri --output json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
    throw "Workflow content deployed, but '$WorkflowName' could not be read from the Logic Apps runtime."
}

$deployedArtifact = $deployedWorkflow.properties.files.'workflow.json'
if ($deployedArtifact -is [string]) {
    $deployedArtifact = $deployedArtifact | ConvertFrom-Json
}
$actualMethod = $deployedArtifact.definition.triggers.When_a_HTTP_request_is_received.inputs.method
if ($actualMethod -ne $expectedMethod) {
    throw "Workflow deployed, but the live trigger method is '$actualMethod' instead of '$expectedMethod'."
}

$logicAppHostname = az webapp show `
    --subscription $SubscriptionId `
    --name $LogicAppName `
    --resource-group $ResourceGroupName `
    --query defaultHostName `
    --output tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($logicAppHostname)) {
    throw 'Workflow deployed, but the Logic App hostname could not be resolved.'
}

$invokeUrl = "https://$logicAppHostname/api/$WorkflowName/triggers/When_a_HTTP_request_is_received/invoke?api-version=2022-05-01"

Write-Host "Workflow deployed successfully with HTTP $actualMethod." -ForegroundColor Green
Write-Host 'Unsigned invoke URL (use with an Entra bearer token):' -ForegroundColor Green
Write-Host "  $invokeUrl"