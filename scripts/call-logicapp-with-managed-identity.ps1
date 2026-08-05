<#
.SYNOPSIS
    Fetches a managed-identity bearer token and calls the Logic App.

.DESCRIPTION
    Run this script inside the Azure Function App or another App Service app
    that has a managed identity. App Service supplies IDENTITY_ENDPOINT and
    IDENTITY_HEADER. The bearer token remains in memory and is never printed.
#>

[CmdletBinding()]
param(
    [string]$Audience = 'api://786594a8-6b38-40cf-8c6b-d434b539dd46',

    [string]$LogicAppUrl = 'https://la-easyauth-lab-dev-la-daaq6t5xzrpaw.azurewebsites.net/api/httpTriggerWorkflow/triggers/When_a_HTTP_request_is_received/invoke?api-version=2022-05-01'
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($env:IDENTITY_ENDPOINT) -or
    [string]::IsNullOrWhiteSpace($env:IDENTITY_HEADER)) {
    throw 'Managed identity endpoint variables are unavailable. Run this script inside the Azure Function App or another managed-identity-enabled App Service app.'
}

# Step 1: Ask the App Service managed-identity endpoint for a token.
$tokenUri = '{0}?resource={1}&api-version=2019-08-01' -f `
    $env:IDENTITY_ENDPOINT,
    [uri]::EscapeDataString($Audience)

$tokenResponse = Invoke-RestMethod `
    -Method Get `
    -Uri $tokenUri `
    -Headers @{ 'X-IDENTITY-HEADER' = $env:IDENTITY_HEADER }

$bearerToken = $tokenResponse.access_token
if ([string]::IsNullOrWhiteSpace($bearerToken)) {
    throw 'The managed-identity endpoint did not return an access token.'
}

# Step 2: Send the bearer token to the unsigned Logic App trigger URL.
$separator = if ($LogicAppUrl.Contains('?')) { '&' } else { '?' }
$requestUrl = "$LogicAppUrl${separator}scenario=SIMPLE-MI-SCRIPT"

try {
    Invoke-RestMethod `
        -Method Post `
        -Uri $requestUrl `
        -Headers @{ Authorization = "Bearer $bearerToken" } `
        -ContentType 'application/json' `
        -Body '{"message":"Called with a managed-identity bearer token"}'
}
finally {
    Remove-Variable bearerToken, tokenResponse -ErrorAction SilentlyContinue
}