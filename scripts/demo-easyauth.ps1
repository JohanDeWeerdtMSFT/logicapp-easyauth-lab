<#
.SYNOPSIS
    Demonstrates the Function-to-Logic-App Easy Auth flow.

.DESCRIPTION
    Proves that the unsigned Logic App endpoint rejects an unauthenticated call,
    then invokes the Function-key-protected caller. The Function uses its managed
    identity to acquire an Entra token for the Logic App audience.

    The Function key and bearer token remain in memory and are never printed.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SubscriptionId,

    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory)]
    [string]$LogicAppName,

    [Parameter(Mandatory)]
    [string]$FunctionAppName,

    [Parameter(Mandatory)]
    [string]$LogicAppClientId,

    [Parameter(Mandatory)]
    [string]$TenantId
)

$ErrorActionPreference = 'Stop'
$workflowName = 'httpTriggerWorkflow'
$triggerName = 'When_a_HTTP_request_is_received'

az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) {
    throw "Could not select subscription '$SubscriptionId'."
}

$logicAppHost = az webapp show `
    --subscription $SubscriptionId `
    --resource-group $ResourceGroupName `
    --name $LogicAppName `
    --query defaultHostName `
    --output tsv
$functionAppHost = az functionapp show `
    --subscription $SubscriptionId `
    --resource-group $ResourceGroupName `
    --name $FunctionAppName `
    --query defaultHostName `
    --output tsv
$functionPrincipalId = az functionapp identity show `
    --subscription $SubscriptionId `
    --resource-group $ResourceGroupName `
    --name $FunctionAppName `
    --query principalId `
    --output tsv

if ($LASTEXITCODE -ne 0 -or
    [string]::IsNullOrWhiteSpace($logicAppHost) -or
    [string]::IsNullOrWhiteSpace($functionAppHost) -or
    [string]::IsNullOrWhiteSpace($functionPrincipalId)) {
    throw 'Could not resolve the deployed app endpoints and Function managed identity.'
}

$logicAppUrl = "https://$logicAppHost/api/$workflowName/triggers/$triggerName/invoke?api-version=2022-05-01&scenario=DEMO-NO-TOKEN"
$functionAppUrl = "https://$functionAppHost/api/CallLogicApp"

$unauthenticatedResponse = Invoke-WebRequest `
    -Method Post `
    -Uri $logicAppUrl `
    -ContentType 'application/json' `
    -Body '{}' `
    -SkipHttpErrorCheck `
    -TimeoutSec 120

if ([int]$unauthenticatedResponse.StatusCode -ne 401) {
    throw "Expected the unauthenticated Logic App call to return 401, but received $([int]$unauthenticatedResponse.StatusCode)."
}

$functionKey = az functionapp keys list `
    --subscription $SubscriptionId `
    --resource-group $ResourceGroupName `
    --name $FunctionAppName `
    --query 'functionKeys.default' `
    --output tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($functionKey)) {
    throw 'Could not retrieve the Function key.'
}

$functionHeaders = @{ 'x-functions-key' = $functionKey }
try {
    $authenticatedResponse = Invoke-WebRequest `
        -Method Post `
        -Uri $functionAppUrl `
        -Headers $functionHeaders `
        -ContentType 'application/json' `
        -Body '{"scenario":"DEMO"}' `
        -SkipHttpErrorCheck `
        -TimeoutSec 120

    $callerBody = $authenticatedResponse.Content | ConvertFrom-Json
    $workflowBody = $callerBody.logicAppResponse | ConvertFrom-Json

    $assertions = [ordered]@{
        functionStatus = ([int]$authenticatedResponse.StatusCode -eq 200)
        callerStatus = ($callerBody.status -eq 'success')
        scenario = ($callerBody.scenario -eq 'DEMO')
        tokenAudience = ($callerBody.tokenClaims.Audience -eq "api://$LogicAppClientId")
        tokenIssuer = ($callerBody.tokenClaims.Issuer -eq "https://sts.windows.net/$TenantId/")
        tokenPrincipal = ($callerBody.tokenClaims.ObjectId -eq $functionPrincipalId)
        workflowStatus = ($workflowBody.status -eq 'ok')
        workflowAuthenticated = ([string]$workflowBody.authInfo.isAuthenticated -eq 'True')
        workflowPrincipal = ($workflowBody.authInfo.principalId -eq $functionPrincipalId)
    }

    $result = [pscustomobject]@{
        passed = -not ($assertions.Values -contains $false)
        unauthenticatedLogicAppStatus = [int]$unauthenticatedResponse.StatusCode
        authenticatedFunctionStatus = [int]$authenticatedResponse.StatusCode
        audience = $callerBody.tokenClaims.Audience
        issuer = $callerBody.tokenClaims.Issuer
        managedIdentityPrincipalId = $callerBody.tokenClaims.ObjectId
        workflowAuthenticated = $workflowBody.authInfo.isAuthenticated
        workflowPrincipalId = $workflowBody.authInfo.principalId
        assertions = $assertions
    }

    $result | ConvertTo-Json -Depth 5
    if (-not $result.passed) {
        throw 'The Easy Auth demo did not satisfy every assertion.'
    }
}
finally {
    Remove-Variable functionKey, functionHeaders -ErrorAction SilentlyContinue
}