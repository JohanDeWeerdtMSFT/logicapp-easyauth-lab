<#
.SYNOPSIS
    Validates the public-classroom Easy Auth and managed-identity flow.

.DESCRIPTION
    Runs the SAS-free Lab 3 scenario matrix:
    - B1: Function-key-protected test harness -> managed identity -> Logic App (200)
    - B2: invalid token -> Logic App (401)
    - B3: wrong-audience token -> Logic App (401)
    - B4: no token -> Logic App (401)
    - B6: optional reversible allowedPrincipals override -> Function (403)

    Tokens and the Function key remain in memory and are never written to output or evidence files.
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

    [switch]$RunAuthorizationMutation
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'EasyAuthLab.psm1') -Force
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

function Wait-AllowedPrincipals {
    param(
        [Parameter(Mandatory)]
        [string]$AuthUri,

        [Parameter(Mandatory)]
        [string[]]$ExpectedPrincipals,

        [int]$MaximumAttempts = 12
    )

    for ($attempt = 1; $attempt -le $MaximumAttempts; $attempt++) {
        $actualPrincipals = @(
            az rest `
                --subscription $SubscriptionId `
                --method get `
                --uri $AuthUri `
                --query 'properties.identityProviders.azureActiveDirectory.validation.defaultAuthorizationPolicy.allowedPrincipals.identities' `
                --output json | ConvertFrom-Json
        )
        if ($LASTEXITCODE -ne 0) {
            throw 'Could not read the Logic App Easy Auth allowedPrincipals policy.'
        }

        if (-not (Compare-Object $ExpectedPrincipals $actualPrincipals)) {
            return
        }

        if ($attempt -lt $MaximumAttempts) {
            Start-Sleep -Seconds 5
        }
    }

    throw 'Timed out waiting for the Logic App Easy Auth allowedPrincipals policy to update.'
}

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
$functionKey = az functionapp keys list `
    --subscription $SubscriptionId `
    --resource-group $ResourceGroupName `
    --name $FunctionAppName `
    --query 'functionKeys.default' `
    --output tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($functionKey)) {
    throw 'Could not retrieve the CallLogicApp Function key.'
}
$functionHeaders = @{ 'x-functions-key' = $functionKey }

$wrongAudienceToken = $null
try {
    $b1 = Invoke-LabRequest `
        -Scenario 'B1' `
        -Uri $functionAppUrl `
        -ExpectedStatus 200 `
        -Headers $functionHeaders

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
        $originalPayloadPath = Join-Path ([System.IO.Path]::GetTempPath()) "easyauth-original-$([guid]::NewGuid()).json"
        $mutationPayloadPath = Join-Path ([System.IO.Path]::GetTempPath()) "easyauth-b6-$([guid]::NewGuid()).json"
        [ordered]@{ properties = $originalAuth.properties } |
            ConvertTo-Json -Depth 100 |
            Set-Content $originalPayloadPath -Encoding utf8NoBOM

        $mutationProperties = $originalAuth.properties |
            ConvertTo-Json -Depth 100 |
            ConvertFrom-Json
        $mutationProperties.identityProviders.azureActiveDirectory.validation.defaultAuthorizationPolicy.allowedPrincipals.identities = @($nonCallerPrincipalId)
        [ordered]@{ properties = $mutationProperties } |
            ConvertTo-Json -Depth 100 |
            Set-Content $mutationPayloadPath -Encoding utf8NoBOM

        # Probing the real Function path is the only reliable signal that App
        # Service Authentication runtime is enforcing the new policy; ARM state
        # alone is not sufficient.
        $b6Probe = {
            (Invoke-LabRequest `
                -Scenario 'B6-probe' `
                -Uri $functionAppUrl `
                -ExpectedStatus 403 `
                -Headers $functionHeaders `
                -Record $false).actualStatus
        }
        $restartLogicApp = {
            Write-Host 'Runtime still allowed the call; restarting the Logic App to refresh Easy Auth.' -ForegroundColor Yellow
            az webapp restart `
                --subscription $SubscriptionId `
                --resource-group $ResourceGroupName `
                --name $LogicAppName `
                --output none
            Start-Sleep -Seconds 30
        }

        try {
            az rest `
                --subscription $SubscriptionId `
                --method put `
                --uri $authUri `
                --body "@$mutationPayloadPath" `
                --output none
            if ($LASTEXITCODE -ne 0) {
                throw 'Could not apply the B6 principal override.'
            }
            Wait-AllowedPrincipals -AuthUri $authUri -ExpectedPrincipals @($nonCallerPrincipalId)

            $b6Wait = Wait-RuntimeHttpStatus `
                -Probe $b6Probe `
                -ExpectedStatus 403 `
                -RefreshAction $restartLogicApp

            if (-not $b6Wait.succeeded) {
                $currentPrincipals = @(
                    az rest `
                        --subscription $SubscriptionId `
                        --method get `
                        --uri $authUri `
                        --query 'properties.identityProviders.azureActiveDirectory.validation.defaultAuthorizationPolicy.allowedPrincipals.identities' `
                        --output json | ConvertFrom-Json
                )
                Write-Warning ("B6 timed out waiting for runtime enforcement. Expected HTTP 403, observed HTTP $($b6Wait.lastStatus) after $($b6Wait.attempts) attempts. " +
                    "Current ARM allowedPrincipals: $($currentPrincipals -join ', '). Restoration runs next.")
            }

            $b6 = Invoke-LabRequest `
                -Scenario 'B6' `
                -Uri $functionAppUrl `
                -ExpectedStatus 403 `
                -Headers $functionHeaders
            $b6.assertions = [ordered]@{
                errorType = ($b6.body.error -eq 'Forbidden')
                runtimeEnforced = [bool]$b6Wait.succeeded
            }
            $b6.passed = $b6.passed -and -not ($b6.assertions.Values -contains $false)
        }
        finally {
            # Restoration must succeed even when the B6 assertion, the runtime
            # wait, or the request itself failed.
            $restorationSucceeded = $false
            try {
                az rest `
                    --subscription $SubscriptionId `
                    --method put `
                    --uri $authUri `
                    --body "@$originalPayloadPath" `
                    --output none
                if ($LASTEXITCODE -ne 0) {
                    throw 'B6 restoration failed.'
                }

                Wait-AllowedPrincipals -AuthUri $authUri -ExpectedPrincipals $originalPrincipals
                $restorationSucceeded = $true
            }
            finally {
                Remove-Item $originalPayloadPath, $mutationPayloadPath -Force -ErrorAction SilentlyContinue
                Write-Host "B6 restoration succeeded: $restorationSucceeded" -ForegroundColor DarkGray
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

        # ARM agreement is not enough: confirm the runtime allows the original
        # Function managed identity again before declaring the lab restored.
        $restoreWait = Wait-RuntimeHttpStatus `
            -Probe {
                (Invoke-LabRequest `
                    -Scenario 'B6-restore-probe' `
                    -Uri $functionAppUrl `
                    -ExpectedStatus 200 `
                    -Headers $functionHeaders `
                    -Record $false).actualStatus
            } `
            -ExpectedStatus 200 `
            -RefreshAction $restartLogicApp

        $b6Restored = Invoke-LabRequest `
            -Scenario 'B6-restored' `
            -Uri $functionAppUrl `
            -ExpectedStatus 200 `
            -Headers $functionHeaders

        $restoredWorkflowResponse = $null
        if ($b6Restored.body -and $b6Restored.body.logicAppResponse) {
            try {
                $restoredWorkflowResponse = $b6Restored.body.logicAppResponse | ConvertFrom-Json
            }
            catch {
                $restoredWorkflowResponse = $null
            }
        }

        $b6Restored.assertions = [ordered]@{
            runtimeRestored = [bool]$restoreWait.succeeded
            workflowPrincipal = ($restoredWorkflowResponse.authInfo.principalId -eq $functionPrincipalId)
        }
        $b6Restored.passed = $b6Restored.passed -and -not ($b6Restored.assertions.Values -contains $false)
    }
}
finally {
    Remove-Variable wrongAudienceToken -ErrorAction SilentlyContinue
    Remove-Variable functionKey, functionHeaders -ErrorAction SilentlyContinue
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