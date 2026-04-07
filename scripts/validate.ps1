<#
.SYNOPSIS
    Validates Easy Auth behavior on Logic App Standard (Track A & Track B).

.DESCRIPTION
    Track A: Portal manageability — triggers test runs and queries run history
    via the management API to gather API-level evidence.
    Track B: Trigger security — validates token enforcement scenarios (valid
    token, invalid token, wrong audience, no token).

.EXAMPLE
    $secret = Read-Host -AsSecureString 'Client secret'
    .\validate.ps1 -LogicAppName "la-easyauth-lab-dev" `
        -ResourceGroupName "rg-la-easyauth-lab-dev" `
        -EntraAppClientId "00000000-..." `
        -EntraAppTenantId "00000000-..." `
        -ClientSecret $secret
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$LogicAppName,

    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory)]
    [string]$EntraAppClientId,

    [Parameter(Mandatory)]
    [string]$EntraAppTenantId,

    [Parameter(Mandatory)]
    [SecureString]$ClientSecret,

    [ValidateSet('TrackA', 'TrackB', 'Both')]
    [string]$TestMode = 'Both'
)

$ErrorActionPreference = 'Stop'

# ── Constants ────────────────────────────────────────────────────────────────
$subscriptionId = '6851693c-0b74-4462-8da8-cd498b088827'
$workflowName   = 'httpTriggerWorkflow'
$evidencePath   = Join-Path $PSScriptRoot '..\docs\evidence'
$timestamp      = Get-Date -Format 'yyyyMMdd-HHmmss'
$resultsFile    = Join-Path $evidencePath "validation-results-${timestamp}.json"

# ── State ────────────────────────────────────────────────────────────────────
$results = [System.Collections.Generic.List[object]]::new()

Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host   "║  Logic App Easy Auth Lab — Validation Runner                ║" -ForegroundColor Cyan
Write-Host   "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Logic App       : $LogicAppName"
Write-Host "  Resource Group  : $ResourceGroupName"
Write-Host "  Test Mode       : $TestMode"
Write-Host "  Client ID       : $EntraAppClientId"
Write-Host "  Tenant ID       : $EntraAppTenantId"
Write-Host "  Results File    : $resultsFile"
Write-Host ""

# ── Helpers ──────────────────────────────────────────────────────────────────
function ConvertFrom-SecureStringPlain {
    param([SecureString]$Secure)
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) }
    finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Get-MsalClientToken {
    param(
        [string]$TenantId,
        [string]$ClientId,
        [string]$Secret,
        [string]$Scope
    )
    $body = @{
        grant_type    = 'client_credentials'
        client_id     = $ClientId
        client_secret = $Secret
        scope         = $Scope
    }
    $tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $response = Invoke-RestMethod -Uri $tokenUrl -Method POST -Body $body -ContentType 'application/x-www-form-urlencoded'
    return $response.access_token
}

function Invoke-ScenarioRequest {
    param(
        [string]$ScenarioId,
        [string]$Description,
        [string]$Url,
        [hashtable]$Headers = @{},
        [int]$ExpectedStatus
    )

    Write-Host "  [$ScenarioId] $Description" -ForegroundColor Yellow -NoNewline

    $result = [ordered]@{
        scenarioId      = $ScenarioId
        description     = $Description
        url             = $Url
        expectedStatus  = $ExpectedStatus
        actualStatus    = $null
        passed          = $false
        correlationId   = $null
        responseSnippet = $null
        error           = $null
        timestamp       = (Get-Date -Format 'o')
    }

    try {
        $response = $null
        try {
            $splatArgs = @{
                Uri                = $Url
                Method             = 'GET'
                Headers            = $Headers
                MaximumRedirection = 0
                ErrorAction        = 'Stop'
            }
            $response = Invoke-WebRequest @splatArgs
        }
        catch [System.Net.WebException] {
            $response = $_.Exception.Response
            if ($null -eq $response) { throw }
            # Wrap the error response so we can read status and headers
            $result.actualStatus = [int]$response.StatusCode
        }
        catch {
            if ($_.Exception.Response) {
                $response = $_.Exception.Response
                $result.actualStatus = [int]$response.StatusCode
            }
            else { throw }
        }

        if ($null -eq $result.actualStatus -and $null -ne $response) {
            $result.actualStatus = [int]$response.StatusCode
        }

        # Extract correlation ID from headers
        if ($response -is [Microsoft.PowerShell.Commands.BasicHtmlWebResponseObject]) {
            $result.correlationId = $response.Headers['x-ms-request-id']
            $bodyText = $response.Content
        }
        elseif ($response -is [System.Net.HttpWebResponse]) {
            $result.correlationId = $response.Headers['x-ms-request-id']
            $reader = [System.IO.StreamReader]::new($response.GetResponseStream())
            $bodyText = $reader.ReadToEnd()
            $reader.Close()
        }
        else {
            $bodyText = ''
        }

        $result.responseSnippet = if ($bodyText.Length -gt 500) { $bodyText.Substring(0, 500) + '...' } else { $bodyText }
        $result.passed = ($result.actualStatus -eq $ExpectedStatus)
    }
    catch {
        # PowerShell 7+ wraps web errors in HttpResponseException
        if ($_.Exception -is [Microsoft.PowerShell.Commands.HttpResponseException]) {
            $result.actualStatus    = [int]$_.Exception.Response.StatusCode
            $result.correlationId   = $_.Exception.Response.Headers | Where-Object Key -eq 'x-ms-request-id' | Select-Object -ExpandProperty Value -First 1
            $result.responseSnippet = $_.ErrorDetails.Message
            $result.passed          = ($result.actualStatus -eq $ExpectedStatus)
        }
        else {
            $result.error = $_.Exception.Message
        }
    }

    $statusIcon = if ($result.passed) { '✔' } else { '✖' }
    $statusColor = if ($result.passed) { 'Green' } else { 'Red' }
    Write-Host " → $($result.actualStatus) $statusIcon" -ForegroundColor $statusColor

    $results.Add([PSCustomObject]$result)
    return $result
}

# ── Resolve callback URL ────────────────────────────────────────────────────
try {
    Write-Host "── Resolving callback URL ─────────────────────────────────" -ForegroundColor DarkGray

    $managementBase = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/sites/$LogicAppName"

    $callbackJson = az rest `
        --method POST `
        --url "${managementBase}/hostruntime/runtime/webhooks/workflow/api/management/workflows/${workflowName}/triggers/When_a_HTTP_request_is_received/listCallbackUrl?api-version=2024-04-01" `
        --output json 2>&1

    if ($LASTEXITCODE -ne 0) { throw "Failed to get callback URL: $callbackJson" }

    $callbackInfo = ($callbackJson -join '') | ConvertFrom-Json
    $callbackUrl  = $callbackInfo.value

    # Derive the host (scheme + host) for token-only calls (strip SAS query params)
    $callbackUri = [System.Uri]::new($callbackUrl)
    $baseUrl     = "$($callbackUri.Scheme)://$($callbackUri.Host)$($callbackUri.AbsolutePath)"
    # Keep the full URL with SAS for scenarios that need it
    $sasUrl      = $callbackUrl

    Write-Host "  Base URL : $baseUrl"
    Write-Host "  SAS URL  : $($sasUrl.Substring(0, [Math]::Min($sasUrl.Length, 80)))..."
    Write-Host ""
}
catch {
    Write-Host "✖ Could not resolve callback URL:" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Ensure the workflow '$workflowName' is deployed and has an HTTP trigger." -ForegroundColor Red
    exit 1
}

# ── Token acquisition ────────────────────────────────────────────────────────
$plainSecret = ConvertFrom-SecureStringPlain -Secure $ClientSecret

function Get-ValidToken {
    $scope = "$EntraAppClientId/.default"
    return Get-MsalClientToken -TenantId $EntraAppTenantId -ClientId $EntraAppClientId -Secret $plainSecret -Scope $scope
}

function Get-WrongAudienceToken {
    # Token scoped to Microsoft Graph instead of the app
    return Get-MsalClientToken -TenantId $EntraAppTenantId -ClientId $EntraAppClientId -Secret $plainSecret -Scope 'https://graph.microsoft.com/.default'
}

# ══════════════════════════════════════════════════════════════════════════════
# Track B — Trigger Security Validation
# ══════════════════════════════════════════════════════════════════════════════
if ($TestMode -in @('TrackB', 'Both')) {
    Write-Host "══ Track B: Trigger Security Validation ═══════════════════" -ForegroundColor Magenta
    Write-Host ""

    # B1 — Valid token
    try {
        $validToken = Get-ValidToken
        Invoke-ScenarioRequest `
            -ScenarioId 'B1' `
            -Description 'Valid bearer token → expect 200' `
            -Url "${baseUrl}?scenario=B1" `
            -Headers @{ Authorization = "Bearer $validToken" } `
            -ExpectedStatus 200
    }
    catch {
        Write-Host "  [B1] Token acquisition failed: $($_.Exception.Message)" -ForegroundColor Red
        $results.Add([PSCustomObject]@{
            scenarioId = 'B1'; description = 'Valid bearer token'; expectedStatus = 200
            actualStatus = $null; passed = $false; error = $_.Exception.Message
            correlationId = $null; responseSnippet = $null; timestamp = (Get-Date -Format 'o')
        })
    }

    # B2 — Invalid / expired token
    $expiredToken = 'eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJpbnZhbGlkIiwiZXhwIjoxMDAwMDAwMDAwfQ.invalid-signature'
    Invoke-ScenarioRequest `
        -ScenarioId 'B2' `
        -Description 'Invalid/expired token → expect 401' `
        -Url "${baseUrl}?scenario=B2" `
        -Headers @{ Authorization = "Bearer $expiredToken" } `
        -ExpectedStatus 401

    # B3 — Wrong audience token
    try {
        $wrongToken = Get-WrongAudienceToken
        Invoke-ScenarioRequest `
            -ScenarioId 'B3' `
            -Description 'Wrong audience token → expect 401' `
            -Url "${baseUrl}?scenario=B3" `
            -Headers @{ Authorization = "Bearer $wrongToken" } `
            -ExpectedStatus 401
    }
    catch {
        Write-Host "  [B3] Token acquisition failed: $($_.Exception.Message)" -ForegroundColor Red
        $results.Add([PSCustomObject]@{
            scenarioId = 'B3'; description = 'Wrong audience token'; expectedStatus = 401
            actualStatus = $null; passed = $false; error = $_.Exception.Message
            correlationId = $null; responseSnippet = $null; timestamp = (Get-Date -Format 'o')
        })
    }

    # B4 — No token at all (behavior depends on Easy Auth mode)
    # In Return401 mode: expect 401. In AllowAnonymous mode: expect 200.
    # We test for 401 by default; the operator can check the output for AllowAnonymous.
    Invoke-ScenarioRequest `
        -ScenarioId 'B4' `
        -Description 'No token (Return401 → 401, AllowAnonymous → 200)' `
        -Url "${baseUrl}?scenario=B4" `
        -Headers @{} `
        -ExpectedStatus 401

    Write-Host ""
}

# ══════════════════════════════════════════════════════════════════════════════
# Track A — Portal Manageability Validation
# ══════════════════════════════════════════════════════════════════════════════
if ($TestMode -in @('TrackA', 'Both')) {
    Write-Host "══ Track A: Portal Manageability Validation ═══════════════" -ForegroundColor Magenta
    Write-Host ""

    # Step 1: Trigger multiple test runs via the callback URL (with SAS)
    Write-Host "  Triggering test runs via SAS callback URL..." -ForegroundColor Yellow
    $triggerCount = 3
    for ($i = 1; $i -le $triggerCount; $i++) {
        $scenarioTag = "TrackA-Run$i"
        try {
            $triggerUrl = "${sasUrl}&scenario=$scenarioTag"
            # Use -SkipHttpErrorCheck if available (PS7+), else catch errors
            $triggerResponse = Invoke-WebRequest -Uri $triggerUrl -Method GET -ErrorAction SilentlyContinue
            Write-Host "    Run $i triggered: $([int]$triggerResponse.StatusCode)" -ForegroundColor Green
        }
        catch {
            $status = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 'error' }
            Write-Host "    Run $i triggered: $status" -ForegroundColor Yellow
        }
        Start-Sleep -Seconds 2
    }

    # Step 2: Wait for runs to complete
    Write-Host ""
    Write-Host "  Waiting 10s for runs to settle..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 10

    # Step 3: Query run history via management API
    Write-Host "  Querying run history via management API..." -ForegroundColor Yellow
    $runsUrl = "${managementBase}/hostruntime/runtime/webhooks/workflow/api/management/workflows/${workflowName}/runs?api-version=2024-04-01"

    try {
        $runsJson = az rest --method GET --url $runsUrl --output json 2>&1
        if ($LASTEXITCODE -ne 0) { throw "az rest failed: $runsJson" }

        $runsData = ($runsJson -join '') | ConvertFrom-Json
        $runCount = @($runsData.value).Count

        Write-Host "    Runs returned: $runCount" -ForegroundColor Green

        $trackAResult = [ordered]@{
            scenarioId      = 'A1'
            description     = 'Run history API accessible'
            expectedStatus  = 200
            actualStatus    = 200
            passed          = ($runCount -ge $triggerCount)
            correlationId   = $null
            responseSnippet = "Returned $runCount run(s)"
            error           = $null
            timestamp       = (Get-Date -Format 'o')
            runCount        = $runCount
            runs            = @($runsData.value | Select-Object -First 5 -Property name, @{N='status';E={$_.properties.status}}, @{N='startTime';E={$_.properties.startTime}})
        }
        $results.Add([PSCustomObject]$trackAResult)

        # Display run details
        Write-Host "`n    Recent runs:" -ForegroundColor DarkGray
        foreach ($run in ($runsData.value | Select-Object -First 5)) {
            $runStatus = $run.properties.status
            $runStart  = $run.properties.startTime
            $statusColor = if ($runStatus -eq 'Succeeded') { 'Green' } else { 'Yellow' }
            Write-Host "      [$runStatus] $($run.name) @ $runStart" -ForegroundColor $statusColor
        }
    }
    catch {
        Write-Host "    ✖ Run history query failed: $($_.Exception.Message)" -ForegroundColor Red
        $results.Add([PSCustomObject]@{
            scenarioId = 'A1'; description = 'Run history API accessible'
            expectedStatus = 200; actualStatus = $null; passed = $false
            error = $_.Exception.Message; correlationId = $null
            responseSnippet = $null; timestamp = (Get-Date -Format 'o')
        })
    }

    # Step 4: Check run details for a specific run
    try {
        $firstRun = $runsData.value | Select-Object -First 1
        if ($firstRun) {
            $runId = $firstRun.name
            $runDetailUrl = "${managementBase}/hostruntime/runtime/webhooks/workflow/api/management/workflows/${workflowName}/runs/${runId}?api-version=2024-04-01"

            $detailJson = az rest --method GET --url $runDetailUrl --output json 2>&1
            if ($LASTEXITCODE -ne 0) { throw "az rest failed: $detailJson" }

            $detailData = ($detailJson -join '') | ConvertFrom-Json
            Write-Host "`n    Run detail for $runId :" -ForegroundColor DarkGray
            Write-Host "      Status    : $($detailData.properties.status)"
            Write-Host "      StartTime : $($detailData.properties.startTime)"
            Write-Host "      EndTime   : $($detailData.properties.endTime)"

            $results.Add([PSCustomObject]@{
                scenarioId = 'A2'; description = 'Run detail API accessible'
                expectedStatus = 200; actualStatus = 200; passed = $true
                error = $null; correlationId = $runId
                responseSnippet = "Run $runId status: $($detailData.properties.status)"
                timestamp = (Get-Date -Format 'o')
            })
        }
    }
    catch {
        Write-Host "    ✖ Run detail query failed: $($_.Exception.Message)" -ForegroundColor Red
        $results.Add([PSCustomObject]@{
            scenarioId = 'A2'; description = 'Run detail API accessible'
            expectedStatus = 200; actualStatus = $null; passed = $false
            error = $_.Exception.Message; correlationId = $null
            responseSnippet = $null; timestamp = (Get-Date -Format 'o')
        })
    }

    Write-Host ""
    Write-Host "  ⚠ Portal visual behavior (run history, inputs/outputs, re-run)" -ForegroundColor DarkYellow
    Write-Host "    must be verified manually in the Azure portal." -ForegroundColor DarkYellow
    Write-Host ""
}

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "══ Findings Summary ═══════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

$passCount = @($results | Where-Object { $_.passed }).Count
$failCount = @($results | Where-Object { -not $_.passed }).Count
$totalCount = $results.Count

# Table output
$results | Format-Table -AutoSize -Property `
    @{N='ID';E={$_.scenarioId}; W=4},
    @{N='Result';E={if($_.passed){'PASS'}else{'FAIL'}}; W=6},
    @{N='Expected';E={$_.expectedStatus}; W=8},
    @{N='Actual';E={$_.actualStatus ?? 'N/A'}; W=8},
    @{N='Correlation';E={$_.correlationId ?? '-'}; W=36},
    @{N='Description';E={$_.description}}

Write-Host "  Total: $totalCount | Passed: $passCount | Failed: $failCount" -ForegroundColor $(if ($failCount -gt 0) { 'Yellow' } else { 'Green' })

# ── Save results ─────────────────────────────────────────────────────────────
if (-not (Test-Path $evidencePath)) {
    New-Item -ItemType Directory -Path $evidencePath -Force | Out-Null
}

$outputPayload = [ordered]@{
    metadata = [ordered]@{
        logicAppName      = $LogicAppName
        resourceGroupName = $ResourceGroupName
        testMode          = $TestMode
        entraAppClientId  = $EntraAppClientId
        entraAppTenantId  = $EntraAppTenantId
        timestamp         = (Get-Date -Format 'o')
        passCount         = $passCount
        failCount         = $failCount
    }
    results = @($results)
}

$outputPayload | ConvertTo-Json -Depth 10 | Set-Content -Path $resultsFile -Encoding UTF8
Write-Host "`n  Results saved to: $resultsFile" -ForegroundColor Green
Write-Host ""

# Exit with non-zero if any scenario failed
if ($failCount -gt 0) {
    Write-Host "  ⚠ Some scenarios did not match expected outcomes." -ForegroundColor Yellow
    Write-Host "    Review the results above and the JSON evidence file." -ForegroundColor Yellow
    exit 1
}
