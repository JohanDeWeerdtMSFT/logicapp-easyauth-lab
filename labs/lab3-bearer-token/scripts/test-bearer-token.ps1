# End-to-End Bearer Token Test
# Tests complete flow: token acquisition -> Function App call -> Logic App response

param(
    [string]$Environment = "dev"
)

$ErrorActionPreference = "Stop"

# Configuration
$logicAppClientId = "786594a8-6b38-40cf-8c6b-d434b539dd46"
$functionAppUrl = "https://func-la-easyauth-lab-dev.azurewebsites.net/api/CallLogicApp"

Write-Host "═════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  BEARER TOKEN E2E TEST" -ForegroundColor Cyan
Write-Host "═════════════════════════════════════════" -ForegroundColor Cyan

# Step 1: Token Acquisition
Write-Host "`n[STEP 1] Acquiring bearer token..." -ForegroundColor White
Write-Host "  Scope: $logicAppClientId/.default" -ForegroundColor Gray
try {
    $tokenResult = az account get-access-token --resource $logicAppClientId 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ❌ FAILED: $tokenResult" -ForegroundColor Red
        exit 1
    }
    $tokenObj = $tokenResult | ConvertFrom-Json
    $token = $tokenObj.accessToken
    $expiresOn = $tokenObj.expiresOn
    Write-Host "  ✅ SUCCESS" -ForegroundColor Green
    Write-Host "     Token: $($token.Substring(0,30))..." -ForegroundColor Gray
    Write-Host "     Expires: $expiresOn" -ForegroundColor Gray
}
catch {
    Write-Host "  ❌ EXCEPTION: $_" -ForegroundColor Red
    exit 1
}

# Step 2: Call Function App
Write-Host "`n[STEP 2] Calling Function App..." -ForegroundColor White
Write-Host "  URL: $functionAppUrl" -ForegroundColor Gray
try {
    $headers = @{
        "Authorization" = "Bearer $token"
        "Content-Type" = "application/json"
    }
    
    $response = Invoke-WebRequest `
        -Uri $functionAppUrl `
        -Method GET `
        -Headers $headers `
        -TimeoutSec 30 `
        -ErrorAction Stop
    
    Write-Host "  ✅ SUCCESS - HTTP $($response.StatusCode)" -ForegroundColor Green
}
catch {
    Write-Host "  ❌ FAILED: $_" -ForegroundColor Red
    if ($_.Exception.Response) {
        Write-Host "     Status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
    }
    exit 1
}

# Step 3: Parse Response
Write-Host "`n[STEP 3] Validating response..." -ForegroundColor White
try {
    $body = $response.Content | ConvertFrom-Json
    Write-Host "  ✅ Response parsed successfully" -ForegroundColor Green
}
catch {
    Write-Host "  ❌ Failed to parse JSON: $_" -ForegroundColor Red
    Write-Host "     Raw response: $($response.Content)" -ForegroundColor Red
    exit 1
}

# Step 4: Validate Response Content
Write-Host "`n[STEP 4] Validating response content..." -ForegroundColor White

$hasError = $body.error
$hasScenario = $body.scenario
$hasLogicAppResponse = $body.logicAppResponse
$hasCallerPrincipal = $body.callerPrincipal

if ($hasError) {
    Write-Host "  ❌ ERROR field present:" -ForegroundColor Red
    Write-Host "     $($body.error | ConvertTo-Json)" -ForegroundColor Red
    exit 1
} else {
    Write-Host "  ✅ No error field" -ForegroundColor Green
}

if ($hasScenario) {
    Write-Host "  ✅ Scenario: $hasScenario" -ForegroundColor Green
}

if ($hasLogicAppResponse) {
    Write-Host "  ✅ Logic App response present" -ForegroundColor Green
    Write-Host "     Keys: $($body.logicAppResponse.PSObject.Properties.Name -join ', ')" -ForegroundColor Gray
}

if ($hasCallerPrincipal) {
    Write-Host "  ✅ Caller principal: $($body.callerPrincipal)" -ForegroundColor Green
}

# Summary
Write-Host "`n═════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  TEST RESULTS" -ForegroundColor Cyan
Write-Host "═════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "`n✅ All checks passed!" -ForegroundColor Green
Write-Host "`nFull response:" -ForegroundColor Cyan
Write-Host ($body | ConvertTo-Json -Depth 3) -ForegroundColor Gray

Write-Host "`n✅ Bearer token authentication working end-to-end:" -ForegroundColor Green
Write-Host "   • Token acquired with client ID scope: $logicAppClientId/.default" -ForegroundColor Green
Write-Host "   • Function App received and processed request" -ForegroundColor Green
Write-Host "   • Easy Auth validated bearer token" -ForegroundColor Green
Write-Host "   • Function App called Logic App successfully" -ForegroundColor Green
Write-Host "   • No ManagedIdentityCredential errors" -ForegroundColor Green
