<#
.SYNOPSIS
    Fetches a managed-identity bearer token and calls the Logic App.

.DESCRIPTION
    Run this script inside the Azure Function App or another App Service app
    that has a managed identity. App Service supplies IDENTITY_ENDPOINT and
    IDENTITY_HEADER. The bearer token remains in memory and is never printed.

.PARAMETER Audience
    The Application ID URI of the app registration that represents the
    protected Logic App API.

    Azure portal location:
    Microsoft Entra ID > App registrations > la-easyauth-lab-dev >
    Expose an API > Application ID URI.

    The GUID inside api://... is the registration's Application (client) ID,
    which is also visible on the app registration Overview page. This value
    becomes the access token's aud claim and must match the Logic App Easy Auth
    Allowed token audiences value.

.PARAMETER LogicAppUrl
    The unsigned HTTP request-trigger URL. The hostname comes from:
    Logic App Standard > Overview > Default domain.

    The remaining path identifies the workflow and trigger:
    httpTriggerWorkflow > When_a_HTTP_request_is_received.

    This URL intentionally has no sig query parameter. The bearer token is the
    authentication mechanism for the Function-to-Logic-App call.
#>

[CmdletBinding()]
param(
    # Current Logic App API registration:
    # Microsoft Entra ID > App registrations > la-easyauth-lab-dev.
    # Application (client) ID: 786594a8-6b38-40cf-8c6b-d434b539dd46
    # Expose an API > Application ID URI: api://786594a8-...
    [string]$Audience = 'api://786594a8-6b38-40cf-8c6b-d434b539dd46',

    # Current Logic App Standard resource:
    # la-easyauth-lab-dev-la-daaq6t5xzrpaw > Overview > Default domain.
    # The workflow and trigger names are visible under Workflows in the portal.
    [string]$LogicAppUrl = 'https://la-easyauth-lab-dev-la-daaq6t5xzrpaw.azurewebsites.net/api/httpTriggerWorkflow/triggers/When_a_HTTP_request_is_received/invoke?api-version=2022-05-01'
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($env:IDENTITY_ENDPOINT) -or
    [string]::IsNullOrWhiteSpace($env:IDENTITY_HEADER)) {
    throw 'Managed identity endpoint variables are unavailable. Run this script inside the Azure Function App or another managed-identity-enabled App Service app.'
}

# Step 1: Ask the App Service managed-identity endpoint for a token.
# IDENTITY_ENDPOINT and IDENTITY_HEADER are generated and rotated by the Azure
# App Service platform. They are available only inside the running app and are
# not values that you copy from the portal.
#
# The identity represented by the resulting token is the Function App's
# system-assigned managed identity. Find its Object (principal) ID here:
# Function App > Settings > Identity > System assigned.
# Current Object (principal) ID: 82fc3b4f-e83c-42b4-9981-b3fb92ed25e1
#
# That same object ID must appear in the Logic App Easy Auth configuration:
# Logic App > Settings > Authentication > Microsoft > Edit > Allowed identities.
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
# Easy Auth validates the token issuer, the Audience value in the aud claim,
# and the Function managed-identity object ID in the oid claim before the
# Logic App workflow executes.
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