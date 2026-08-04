<#
.SYNOPSIS
    Deploys the HTTP-trigger workflow definition to an existing Logic App Standard resource.

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

if ([string]::IsNullOrWhiteSpace($WorkflowJsonPath)) {
    $WorkflowJsonPath = Join-Path $PSScriptRoot '..\src\httpTriggerWorkflow\workflow.json'
}

if (-not (Test-Path $WorkflowJsonPath)) {
    throw "Workflow definition not found at '$WorkflowJsonPath'."
}

az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) {
    throw "Could not select Azure subscription '$SubscriptionId'."
}

$managementUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/sites/$LogicAppName/workflows/$WorkflowName" + '?api-version=2023-12-01'

Write-Host "Deploying workflow '$WorkflowName' to Logic App '$LogicAppName'..." -ForegroundColor Cyan
az rest --method put --uri $managementUri --body "@$WorkflowJsonPath" --output none
if ($LASTEXITCODE -ne 0) {
    throw "Workflow deployment failed for '$WorkflowName'."
}

$logicAppHostname = az webapp show `
    --name $LogicAppName `
    --resource-group $ResourceGroupName `
    --query defaultHostName `
    --output tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($logicAppHostname)) {
    throw 'Workflow deployed, but the Logic App hostname could not be resolved.'
}

$invokeUrl = "https://$logicAppHostname/api/workflows/$WorkflowName/triggers/manual/invoke?api-version=2022-05-01"

Write-Host "Workflow deployed successfully." -ForegroundColor Green
Write-Host "Unsigned invoke URL (use with an Entra bearer token):" -ForegroundColor Green
Write-Host "  $invokeUrl"
