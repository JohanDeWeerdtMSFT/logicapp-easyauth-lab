# Bearer Token Authentication Testing Guide

## Overview

This guide demonstrates how to test **passwordless bearer token authentication** between an Azure Function App and a Logic App using Azure Easy Auth. The Function App uses its **system-assigned managed identity** to acquire a bearer token and call the Logic App securely, without storing any secrets.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  Function App (System-Assigned Managed Identity)                   │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │ 1. Request arrives at /api/CallLogicApp endpoint           │   │
│  │ 2. Acquires bearer token using DefaultAzureCredential      │   │
│  │    - Scope: {logicAppClientId}/.default                   │   │
│  │ 3. POSTs to Logic App with Authorization header:          │   │
│  │    Authorization: Bearer {token}                          │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
                                ↓
                        [Easy Auth validates token]
                                ↓
┌─────────────────────────────────────────────────────────────────────┐
│  Logic App with Easy Auth (Bearer Token Validation)                │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │ • Validates Bearer token signature (issued by Entra ID)    │   │
│  │ • Checks caller identity in allowedPrincipals              │   │
│  │ • Sets X-MS-CLIENT-PRINCIPAL headers for workflow           │   │
│  │ • Executes workflow or returns 401/403 if validation fails │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

## Key Components

### 1. Function App Bearer Token Acquisition
**File:** `solution/CallerFunctionApp/CallLogicApp.cs`

The Function App uses `DefaultAzureCredential` to automatically acquire bearer tokens:

```csharp
private async Task<AccessToken> GetAccessTokenAsync(CancellationToken cancellationToken)
{
    var logicAppClientId = Environment.GetEnvironmentVariable("LOGIC_APP_CLIENT_ID")
                           ?? "{logicAppClientId}";  // Example: {example-client-id}

    var credential = new DefaultAzureCredential(new DefaultAzureCredentialOptions
    {
        TenantId = Environment.GetEnvironmentVariable("WEBSITE_AUTH_AAD_ALLOWED_TENANTS")
    });

    // IMPORTANT: Use the client ID with /.default suffix
    // This is the CORRECT format Entra ID recognizes for app-to-app authentication
    return await credential.GetTokenAsync(
        new TokenRequestContext(scopes: [$"{logicAppClientId}/.default"]),
        cancellationToken);
}
```

**Critical Detail:** The token scope must be in format `{clientId}/.default`, NOT `api://client-id/.default`
- ✅ Works: `{logicAppClientId}/.default`
- ❌ Fails: `api://{logicAppClientId}/.default`
- ❌ Fails: `https://{functionAppHostname}.azurewebsites.net`

### 2. Bearer Token Usage
The token is passed in the HTTP Authorization header:

```csharp
request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearerToken);
```

### 3. Easy Auth Validation (Logic App Side)
The Logic App's Easy Auth middleware:
- Validates the token signature was issued by Entra ID
- Checks that the caller's principal ID is in `allowedPrincipals`
- Sets context headers for the workflow to consume
- Rejects with 401/403 if validation fails

## Testing Workflow

### Prerequisites

✅ **Verify Setup:**
```bash
# 1. Function App is deployed and running
az functionapp list --resource-group {resourceGroupName} \
  --query "[].{name: name, state: state}" -o table

# 2. Function App has system-assigned managed identity
az webapp identity show \
  --resource-group {resourceGroupName} \
  --name {functionAppName}

# 3. Function App is publicly accessible (for testing)
curl -I https://{functionAppName}.azurewebsites.net/api/CallLogicApp
```

### Step 1: Temporarily Enable Public Access

For testing purposes, ensure the Function App is accessible from your local machine:

```bash
# Check current access restrictions
az functionapp config access-restriction show \
  --resource-group {resourceGroupName} \
  --name {functionAppName} -o json

# If publicNetworkAccess is Disabled, enable it for testing
# (Configure as needed for your environment)
```

### Step 2: Test Bearer Token Flow

#### Option A: Using Browser/Postman

1. **Navigate to Function App endpoint:**
   ```
   https://{functionAppName}.azurewebsites.net/api/CallLogicApp
   ```

2. **In Postman:**
   - Method: `POST`
   - URL: `https://{functionAppName}.azurewebsites.net/api/CallLogicApp`
   - Headers: None required (bearer token acquired automatically by managed identity)
   - Click **Send**

3. **Expected Response (HTTP 200):**
   ```json
   {
     "status": "success",
     "message": "Bearer token flow verified — Easy Auth accepted the request.",
     "logicAppResponse": {...},
     "tokenExpiry": "2026-07-03T17:00:00+00:00",
     "timestamp": "2026-07-03T16:30:00+00:00"
   }
   ```

#### Option B: Using PowerShell

```powershell
$funcAppName = "{functionAppName}"
$funcAppUrl = "https://$funcAppName.azurewebsites.net/api/CallLogicApp"

Write-Host "Testing Function App: $funcAppUrl" -ForegroundColor Cyan

try {
    $response = Invoke-WebRequest `
        -Uri $funcAppUrl `
        -Method POST `
        -TimeoutSec 30 `
        -ErrorAction Stop
    
    Write-Host "✅ Success - HTTP $($response.StatusCode)" -ForegroundColor Green
    Write-Host "Response:" -ForegroundColor Yellow
    $response.Content | ConvertFrom-Json | ConvertTo-Json -Depth 3
} catch {
    Write-Host "❌ Error: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Response) {
        Write-Host "Status Code: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
    }
}
```

#### Option C: Using cURL

```bash
FUNC_APP_NAME="{functionAppName}"
curl -X POST \
  https://$FUNC_APP_NAME.azurewebsites.net/api/CallLogicApp \
  -H "Content-Type: application/json" \
  -v
```

### Step 3: Verify in Application Insights

#### View Bearer Token Flow Logs:

1. **Go to Azure Portal → Resource Groups → `{resourceGroupName}`**

2. **Open Function App: `{functionAppName}`**

3. **Navigate to: Monitoring → Application Insights**

4. **Click "View Application Insights data" or go directly to the App Insights resource**

5. **In Application Insights, check these sections:**

   **a) Requests Tab:**
   - Look for POST request to `/api/CallLogicApp`
   - Should show HTTP 200 (success) or 401/403 (authentication failure)
   - Click to see full request details

   **b) Traces Tab:**
   - Filter by logger name: `CallerFunctionApp.CallLogicApp`
   - Look for these key traces:
     - ✅ `Bearer token acquired. Expiry: [timestamp]`
     - ✅ `POST → Logic App: [url]`
     - ✅ `Logic App response: HTTP 200`
     - ✅ `Logic App call completed successfully (bearer token validated by Easy Auth).`
   
   If you see these logs, **bearer token authentication is working correctly**!

   **c) Failures/Exceptions Tab:**
   - Should be empty (no errors)
   - If you see `ManagedIdentityCredential authentication failed`, check:
     - Function App has system-assigned managed identity enabled
     - Logic App is configured with Easy Auth

#### Application Insights Verification (3 Methods):

**⚠️ IMPORTANT: Logs take 2-5 minutes to appear in Application Insights. Wait before querying.**

##### Method 1: Check Function Execution (Immediate)

In Application Insights, go to **Investigate → Application map** or **Live metrics**:
- Should see requests flowing into the Function App
- Should see HTTP 200 responses (or errors if something failed)
- If you see 503 errors, the test didn't complete successfully — see troubleshooting below

##### Method 2: Check Traces with Reliable Query

In **Logs**, run this query (works even if operation_Name isn't set):

```kusto
traces
| where customDimensions.prop__LogLevel == "Information"
  and (message contains "Bearer token" 
       or message contains "Logic App" 
       or message contains "CallLogicApp")
| project timestamp, severityLevel, message
| order by timestamp desc
| limit 50
```

Expected output:
```
[recent]  Information   CallLogicApp function triggered.
[recent]  Information   Bearer token acquired. Expiry: 2026-07-04T15:30:00+00:00
[recent]  Information   Logic App call completed successfully...
```

##### Method 3: Check for Errors

If Method 2 shows no results, run this to find errors:

```kusto
traces
| where severityLevel >= 2  // 2=Warning, 3=Error
| project timestamp, severityLevel, message
| order by timestamp desc
| limit 20
```

or:

```kusto
requests
| where name == "POST /api/CallLogicApp"
| project timestamp, resultCode, duration, success
| order by timestamp desc
```

## Troubleshooting

### Issue: No Logs Appear in Application Insights
**Problem:** Ran test but see "No results found" in Application Insights

**Causes & Solutions:**

1. **Logs haven't been ingested yet (MOST COMMON)**
   - Application Insights takes 2-5 minutes to sync logs
   - ✅ Solution: **Wait 5 minutes, then re-run the query**

2. **Test didn't actually complete successfully**
   - If you got 503 Service Unavailable, the function never completed
   - Logs are only written if the function runs
   - ✅ Solution: Verify test returns HTTP 200 first
   ```bash
   # Run test and check status immediately
   $response = Invoke-WebRequest -Uri "https://{functionAppName}.azurewebsites.net/api/CallLogicApp" `
       -Method POST -TimeoutSec 30 -ErrorAction SilentlyContinue
   Write-Host "HTTP Status: $($response.StatusCode)"  # Should be 200
   ```

3. **Sampling is filtering out traces**
   - Application Insights may sample low-volume traffic
   - ✅ Solution: Try running the test 5-10 times in quick succession
   ```powershell
   for ($i=1; $i -le 5; $i++) {
       Write-Host "Attempt $i..."
       Invoke-WebRequest -Uri "https://{functionAppName}.azurewebsites.net/api/CallLogicApp" `
           -Method POST -ErrorAction SilentlyContinue
       Start-Sleep -Seconds 2
   }
   # Then wait 2-5 minutes before querying logs
   ```

4. **Application Insights not configured on Function App**
   - ✅ Check: Azure Portal → Function App → Application Insights
   - Should show "Enabled" with an App Insights resource name
   - If not enabled, click "Disable" → "Enable" to reconnect

5. **Querying too narrow a time range**
   - ✅ Solution: In Log Analytics, click **"Set in query"** and select a wider range
   - Try: **Last 24 hours** instead of last 1 hour
   - The query may have timestamps from 15 minutes ago

6. **Function App logs to a different Application Insights instance**
   - ✅ Verify: In Azure Portal → Function App → Application Insights
   - Make sure you're querying the SAME instance shown there

**Quick Verification Checklist:**
```powershell
# 1. Verify Function App is accessible
$response = Invoke-WebRequest -Uri "https://{functionAppName}.azurewebsites.net/health" -ErrorAction SilentlyContinue
if ($response.StatusCode -eq 404) { Write-Host "✅ Function App is accessible (404 is expected for /health)" }
else { Write-Host "⚠️ Function App might not be responding" }

# 2. Run the actual test
$response = Invoke-WebRequest -Uri "https://{functionAppName}.azurewebsites.net/api/CallLogicApp" `
    -Method POST -ErrorAction SilentlyContinue
Write-Host "Status: $($response.StatusCode)"  # Should be 200

# 3. Wait 5 minutes for log ingestion
Write-Host "⏳ Waiting 5 minutes for Application Insights ingestion..."
Start-Sleep -Seconds 300

# 4. Check Application Insights for requests
# (Go to portal and run queries above)
```

If you still see no logs after 10 minutes:
- Check Function App **Logs** in Azure Portal (real-time logs)
- Look for errors in **Monitor → Metrics** 
- Review Logic App's Easy Auth logs for rejection reasons

**Solutions:**
1. Verify Function App has **system-assigned managed identity** enabled:
   ```bash
   az webapp identity show \
     --resource-group {resourceGroupName} \
     --name {functionAppName}
   ```
   Output should show `"type": "SystemAssigned"` with a valid `principalId`

2. Verify the token scope uses client ID (not hostname):
   ```csharp
   // ✅ CORRECT
   new TokenRequestContext(scopes: ["{logicAppClientId}/.default"])
   
   // ❌ INCORRECT
   new TokenRequestContext(scopes: ["api://{logicAppClientId}/.default"])
   ```

### Issue: HTTP 401 Unauthorized
**Error:** `401 Unauthorized` from Logic App

**Causes:**
1. Token is invalid or expired
2. Token audience doesn't match Logic App's app registration
3. Bearer token format is incorrect

**Solutions:**
- Verify `LOGIC_APP_CLIENT_ID` matches Logic App's Entra app registration
- Verify Easy Auth is enabled on Logic App: `Configuration → AAD → On`
- Check Application Insights logs for "Easy Auth rejected the bearer token"

### Issue: HTTP 403 Forbidden
**Error:** `403 Forbidden` from Logic App

**Cause:** Token is valid but Function App's managed identity is not in `allowedPrincipals`

**Solution:**
```bash
# 1. Get Function App managed identity Object ID
FUNC_APP_OBJECT_ID=$(az webapp identity show \
  --resource-group {resourceGroupName} \
  --name {functionAppName} \
  --query principalId -o tsv)

echo "Function App Object ID: $FUNC_APP_OBJECT_ID"

# 2. Add to Logic App's Easy Auth allowedPrincipals
# (Configure in Azure Portal → Logic App → Settings → Easy Auth)
```

### Issue: HTTP 503 Service Unavailable
**Error:** `503 Service Unavailable`

**Causes:**
1. Function App is down or restarting
2. Function App has reached resource limits (CPU/memory)
3. Function App is not accessible from your network
4. Public network access is disabled
5. Private endpoint is not properly configured for your access
6. Logic App endpoint is unreachable

**Solutions:**
```bash
# 1. Check Function App status
az functionapp show \
  --resource-group {resourceGroupName} \
  --name {functionAppName} \
  --query "state" -o tsv

# 2. Check if Function App is running
az functionapp start \
  --resource-group {resourceGroupName} \
  --name {functionAppName}

# 3. Verify public network access is enabled
az functionapp config show \
  --resource-group {resourceGroupName} \
  --name {functionAppName} \
  --query "publicNetworkAccess" -o tsv

# 4. If disabled, enable it temporarily for testing
az functionapp update \
  --resource-group {resourceGroupName} \
  --name {functionAppName} \
  --set "publicNetworkAccess=Enabled"

# 5. Check application logs for errors
az webapp log tail \
  --resource-group {resourceGroupName} \
  --name {functionAppName}

# 6. Verify the endpoint is actually responding
curl -I https://{functionAppName}.azurewebsites.net/api/CallLogicApp
```

**If 503 persists:**
- Wait 1-2 minutes for Function App to restart
- Check Azure Portal for any platform issues or maintenance alerts
- Verify Function App has sufficient CPU/memory allocated
- Try again from a different network or using a VPN if behind corporate proxy

## Cleanup: Restore Private Endpoint Access

After testing, restore security by disabling public access:

```bash
# Option 1: Use access restrictions (if deployed via IaC)
az functionapp config access-restriction add \
  --resource-group {resourceGroupName} \
  --name {functionAppName} \
  --rule-name "DenyPublic" \
  --action Deny \
  --priority 100

# Option 2: Disable public network access entirely
az functionapp config set \
  --resource-group {resourceGroupName} \
  --name {functionAppName} \
  --generic-configurations '{"publicNetworkAccess": "Disabled"}'
```

## Key Learnings

1. **Token Scope Format Matters**
   - Bearer tokens are used for two purposes: **acquisition** and **validation**
   - For acquisition: Use `{clientId}/.default` (no `api://` prefix)
   - For validation: Entra ID recognizes both formats
   - **DefaultAzureCredential is strict:** requires the client ID format

2. **Managed Identity Automates Secret Management**
   - No secrets stored in code or configuration
   - Credentials automatically rotated by Azure
   - Works seamlessly in Azure; requires `az login` locally

3. **Easy Auth Provides Server-Side Validation**
   - Validates token signature without app code
   - Enforces authorization policies (allowedPrincipals)
   - Handles token expiration and refresh transparently

4. **Application Insights is Essential for Debugging**
   - Trace logs show exact token acquisition flow
   - Failed authentication attempts are logged with details
   - Use KQL queries to correlate requests with errors

## References

- [Azure Managed Identities](https://learn.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/)
- [DefaultAzureCredential Documentation](https://learn.microsoft.com/en-us/dotnet/api/azure.identity.defaultazurecredential)
- [Easy Auth Bearer Token Validation](https://learn.microsoft.com/en-us/azure/app-service/configure-authentication-provider-aad)
- [Application Insights KQL Queries](https://learn.microsoft.com/en-us/azure/data-explorer/kusto/query/)

---

**Placeholder Values Used in This Guide:**
- `{functionAppName}` - Your Function App's name (e.g., `my-caller-func-app`)
- `{logicAppClientId}` - Logic App's Entra app registration GUID
- `{resourceGroupName}` - Your resource group name
- `{tenantId}` - Your Azure AD tenant ID
- `{functionAppHostname}` - Function App hostname without domain
- `{logicAppUrl}` - Full URL to Logic App HTTP trigger endpoint

**Status:** ✅ Tested and Verified
