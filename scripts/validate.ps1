<#
.SYNOPSIS
    Validates the public-classroom Easy Auth and managed-identity flow.

.DESCRIPTION
    Runs the SAS-free Lab 3 scenario matrix:
    - B1: Function test harness -> managed identity -> Logic App (200)
    - B2: invalid token -> Logic App (401)
    - B3: wrong-audience token -> Logic App (401)
    - B4: no token -> Logic App (401)
    - B6: optional reversible allowedPrincipals override -> Function (403)

    Tokens remain in memory and are never written to output or evidence files.
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
    [string]$TenantId,

    [string]$ParameterFile = '',

    [switch]$RunAuthorizationMutation
)

$ErrorActionPreference = 'Stop'
$workflowName = 'httpTriggerWorkflow'
$triggerName = 'When_a_HTTP_request_is_received'
$results = [System.Collections.Generic.List[object]]::new()

function Invoke-LabRequest {
    param(
        [Parameter(Mandatory)]
        [string]$Scenario,

        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [int]$ExpectedStatus,

        [hashtable]$Headers = @{},

        [bool]$Record = $true
    )

    $response = Invoke-WebRequest `
        -Uri $Uri `
        -Method Post `
        -Headers $Headers `
        -ContentType 'application/json' `
        -Body (ConvertTo-Json @{ scenario = $Scenario } -Compress) `
        -SkipHttpErrorCheck `
        -TimeoutSec 120

    $body = $null
    if (-not [string]::IsNullOrWhiteSpace($response.Content)) {
        try {
            $body = $response.Content | ConvertFrom-Json
        }
        catch {
            $body = $response.Content
        }
    }

    $result = [pscustomobject]@{
        scenario = $Scenario
        expectedStatus = $ExpectedStatus
        actualStatus = [int]$response.StatusCode
        passed = ([int]$response.StatusCode -eq $ExpectedStatus)
        assertions = $null
        body = $body
    }
    if ($Record) {
        $results.Add($result)
    }
    return $result
}

function Get-AzureToken {
    param(
        [Parameter(Mandatory)]
        [string]$Resource
    )

    $arguments = @('account', 'get-access-token', '--subscription', $SubscriptionId, '--resource', $Resource)
    $arguments += @('--query', 'accessToken', '--output', 'tsv')

    $token = & az @arguments
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
        throw 'Access-token acquisition failed. Confirm Azure CLI login, tenant, and app registration configuration.'
    }
    return $token
}

az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) {
    throw "Could not select subscription '$SubscriptionId'."
}

if ($RunAuthorizationMutation) {
    if ([string]::IsNullOrWhiteSpace($ParameterFile)) {
        throw '-ParameterFile is required when -RunAuthorizationMutation is specified.'
    }
    $ParameterFile = (Resolve-Path $ParameterFile -ErrorAction Stop).Path
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
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($logicAppHost) -or
    [string]::IsNullOrWhiteSpace($functionAppHost)) {
    throw 'Could not resolve the deployed app hostnames.'
}

$logicAppUrl = "https://$logicAppHost/api/$workflowName/triggers/$triggerName/invoke?api-version=2022-05-01"
$functionAppUrl = "https://$functionAppHost/api/CallLogicApp"
$functionPrincipalId = az functionapp identity show `
    --subscription $SubscriptionId `
    --resource-group $ResourceGroupName `
    --name $FunctionAppName `
    --query principalId `
    --output tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($functionPrincipalId)) {
    throw 'Could not resolve the Function App managed identity principal ID.'
}

$wrongAudienceToken = $null
try {
    $b1 = Invoke-LabRequest `
        -Scenario 'B1' `
        -Uri $functionAppUrl `
        -ExpectedStatus 200

    $logicAppResponse = $null
    if ($b1.body -and $b1.body.logicAppResponse) {
        try {
            $logicAppResponse = $b1.body.logicAppResponse | ConvertFrom-Json
        }
        catch {
            $logicAppResponse = $null
        }
    }

    $b1.assertions = [ordered]@{
        callerStatus = ($b1.body.status -eq 'success')
        callerScenario = ($b1.body.scenario -eq 'B1')
        tokenAudience = ($b1.body.tokenClaims.Audience -eq "api://$LogicAppClientId")
        tokenIssuer = ($b1.body.tokenClaims.Issuer -eq "https://sts.windows.net/$TenantId/")
        tokenPrincipal = ($b1.body.tokenClaims.ObjectId -eq $functionPrincipalId)
        workflowScenario = ($logicAppResponse.scenario -eq 'B1')
        workflowAuthenticated = ([string]$logicAppResponse.authInfo.isAuthenticated -eq 'True')
        workflowPrincipal = ($logicAppResponse.authInfo.principalId -eq $functionPrincipalId)
    }
    $b1.passed = $b1.passed -and -not ($b1.assertions.Values -contains $false)

    $invalidToken = 'eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJpbnZhbGlkIiwiZXhwIjoxMDAwMDAwMDAwfQ.invalid-signature'
    Invoke-LabRequest `
        -Scenario 'B2' `
        -Uri "$logicAppUrl&scenario=B2" `
        -ExpectedStatus 401 `
        -Headers @{ Authorization = "Bearer $invalidToken" } | Out-Null

    $wrongAudienceToken = Get-AzureToken -Resource 'https://management.azure.com/'
    Invoke-LabRequest `
        -Scenario 'B3' `
        -Uri "$logicAppUrl&scenario=B3" `
        -ExpectedStatus 401 `
        -Headers @{ Authorization = "Bearer $wrongAudienceToken" } | Out-Null

    Invoke-LabRequest `
        -Scenario 'B4' `
        -Uri "$logicAppUrl&scenario=B4" `
        -ExpectedStatus 401 | Out-Null

    if ($RunAuthorizationMutation) {
        $nonCallerPrincipalId = az webapp identity show `
            --subscription $SubscriptionId `
            --resource-group $ResourceGroupName `
            --name $LogicAppName `
            --query principalId `
            --output tsv
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($nonCallerPrincipalId)) {
            throw 'Could not resolve the temporary B6 principal.'
        }

        $authUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/sites/$LogicAppName/config/authsettingsv2?api-version=2023-12-01"
        $originalAuth = az rest `
            --subscription $SubscriptionId `
            --method get `
            --uri $authUri `
            --output json | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0 -or $null -eq $originalAuth.properties) {
            throw 'Could not capture the original Logic App Easy Auth configuration.'
        }

        $originalPrincipals = @(
            $originalAuth.properties.identityProviders.azureActiveDirectory.validation.defaultAuthorizationPolicy.allowedPrincipals.identities
        )
        try {
            az deployment group create `
                --subscription $SubscriptionId `
                --resource-group $ResourceGroupName `
                --name "b6-validation-$(Get-Date -Format 'yyyyMMdd-HHmmss')" `
                --parameters $ParameterFile "easyAuthAllowedPrincipalOverride=$nonCallerPrincipalId" `
                --mode Incremental `
                --only-show-errors `
                --output none
            if ($LASTEXITCODE -ne 0) {
                throw 'Could not deploy the B6 principal override.'
            }

            $b6 = Invoke-LabRequest `
                -Scenario 'B6' `
                -Uri $functionAppUrl `
                -ExpectedStatus 403
            $b6.assertions = [ordered]@{
                errorType = ($b6.body.error -eq 'Forbidden')
            }
            $b6.passed = $b6.passed -and -not ($b6.assertions.Values -contains $false)
        }
        finally {
            az deployment group create `
                --subscription $SubscriptionId `
                --resource-group $ResourceGroupName `
                --name "b6-restoration-$(Get-Date -Format 'yyyyMMdd-HHmmss')" `
                --parameters $ParameterFile `
                --mode Incremental `
                --only-show-errors `
                --output none
            if ($LASTEXITCODE -ne 0) {
                throw 'B6 restoration failed.'
            }
        }

        $restoredPrincipals = @(
            az rest `
                --subscription $SubscriptionId `
                --method get `
                --uri $authUri `
                --query 'properties.identityProviders.azureActiveDirectory.validation.defaultAuthorizationPolicy.allowedPrincipals.identities' `
                --output json | ConvertFrom-Json
        )
        if ($LASTEXITCODE -ne 0 -or
            (Compare-Object $originalPrincipals $restoredPrincipals)) {
            throw 'B6 restoration verification failed: allowedPrincipals does not match the captured original value.'
        }

    }
}
finally {
    Remove-Variable wrongAudienceToken -ErrorAction SilentlyContinue
}

$summary = [pscustomobject]@{
    passed = @($results | Where-Object passed).Count
    failed = @($results | Where-Object { -not $_.passed }).Count
    results = $results
}
$summary | ConvertTo-Json -Depth 10

if ($summary.failed -gt 0) {
    exit 1
}