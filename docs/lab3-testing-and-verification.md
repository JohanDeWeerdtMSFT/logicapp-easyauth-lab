# Lab 3: Complete Testing & Deployment Guide

This guide walks you through creating a test Function App that calls Logic App using managed identity bearer tokens, 
deploying it to Azure, running tests, and collecting evidence that everything works correctly.

**By the end of this guide, you'll have:**
- A working Function App that uses managed identity to acquire bearer tokens
- Complete evidence that the bearer token flow is secure and functional
- Logs and screenshots documenting the entire flow
- Understanding of how to troubleshoot common issues

**Time Required:** Approximately 60 minutes total

---

## Table of Contents

1. [Prerequisites](#prerequisites--setup) — What you need before starting
2. [Infrastructure Verification](#verify-infrastructure-deployment) — Confirm everything is deployed
3. [Create Your Test Function](#create-test-function-app-with-bearer-token-code) — Build and deploy the test code
4. [Deploy to Azure](#run--monitor-tests) — Publish to your Function App
5. [Collect Evidence](#collect-evidence) — Capture proof that it works
6. [Troubleshooting](#troubleshooting-checklist) — Solutions for common issues

---

## Prerequisites & Setup

### What You'll Need

**Azure Access:**
- Contributor role on the subscription containing `{resourceGroupName}`
- Access to Entra ID tenant (`{tenantId}`)
- Owner or higher role on resource group `rg-la-easyauth-lab-dev`

**Your Local Machine:**
- Azure Functions Core Tools (version 4 or higher)
- Visual Studio Code (recommended) or Visual Studio
- .NET 6 SDK or higher
- PowerShell or Bash terminal
- Azure CLI (optional but recommended)

### Install Azure Functions Core Tools

**Windows (PowerShell):**
```powershell
winget install Microsoft.AzureFunctionsCoreTools
```

**macOS (Homebrew):**
```bash
brew tap azure/azurecli && brew install azure-functions
```

**Linux (Ubuntu/Debian):**
```bash
curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null
sudo sh -c 'echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/azure-cli.list'
sudo apt-get update && sudo apt-get install azure-functions-core-tools-4
```

**Verify Installation:**
```bash
func --version
# Should output version 4.x or higher
```

---

## Verify Infrastructure Deployment

Before you write any code, confirm that Lab 3 infrastructure is correctly deployed in Azure.

Navigate to `rg-la-easyauth-lab-dev` and verify:

- [ ] **Function App (S1 or higher):**
  - Name: `easyauth-func-*` (verify in Bicep)
  - Plan: Standard (S1+) — required for VNet integration
  - Managed Identity: System-assigned enabled
  - VNet integration: Enabled (via App Service plan)

- [ ] **Logic App (WS1):**
  - Name: `easyauth-logic-*`
  - Public network access: **Disabled**
  - VNet integration: Enabled

- [ ] **Virtual Network (10.0.0.0/16):**
  - Subnets:
    - App integration: 10.0.0.0/24
    - Private endpoint: 10.0.1.0/24

- [ ] **Private DNS Zone:**
  - Name: `privatelink.azurewebsites.net`
  - Records: `*.azurewebsites.net` → Private endpoint IP (10.0.1.x)

- [ ] **Private Endpoint:**
  - Target: Logic App
  - VNet: easyauth-vnet
  - Subnet: Private endpoint (10.0.1.0/24)

### 2️⃣ Verify Easy Auth Configuration (CLI)

```bash
# Get Function App Easy Auth settings
az functionapp auth show \
  --resource-group rg-la-easyauth-lab-dev \
  --name easyauth-func-<suffix>

# Expected output should show:
# - unauthenticatedClientAction: "AllowAnonymous"
# - defaultProvider: "AzureActiveDirectory"
```

### 3️⃣ Verify Managed Identity (PowerShell)

```powershell
# Get Function App principal ID
$funcApp = az functionapp show `
  --resource-group rg-la-easyauth-lab-dev `
  --name easyauth-func-<suffix> `
  --query identity.principalId -o tsv

Write-Host "Function App Principal ID: $funcApp"

# Should be a GUID like: 12345678-1234-1234-1234-123456789012
```

---

## Create Test Function App with Bearer Token Code

### ✅ Step 1: Create HttpTrigger Function

```bash
# Navigate to workspace
cd c:\Code\CSU\Ores\EasyAuth

# Create new function project (if not using existing)
func new --language CSharp --template "HTTP trigger" --name CallLogicApp

# Navigate to function directory
cd CallLogicApp
```

### ✅ Step 2: Add Required NuGet Packages

```bash
# Add Azure SDK dependencies
dotnet add package Azure.Identity
dotnet add package Azure.Core
dotnet add package Newtonsoft.Json
```

### ✅ Step 3: Implement Bearer Token Acquisition

**File: `CallLogicApp.cs`**

```csharp
using System;
using System.Net;
using System.Threading.Tasks;
using Azure.Core;
using Azure.Identity;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;

namespace CallLogicApp
{
    public static class CallLogicApp
    {
        [Function("CallLogicApp")]
        public static async Task<HttpResponseData> Run(
            [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = null)]
            HttpRequestData req,
            FunctionContext executionContext)
        {
            var log = executionContext.GetLogger("CallLogicApp");
            log.LogInformation("C# HTTP trigger function started.");

            try
            {
                // 1️⃣ Get bearer token from managed identity
                var token = await GetAccessTokenAsync(log);
                log.LogInformation("✅ Bearer token acquired successfully");

                // 2️⃣ Get Logic App URL from config
                var logicAppUrl = Environment.GetEnvironmentVariable("LOGIC_APP_URL");
                var audience = Environment.GetEnvironmentVariable("LOGIC_APP_AUDIENCE");

                if (string.IsNullOrEmpty(logicAppUrl) || string.IsNullOrEmpty(audience))
                {
                    log.LogError("❌ Missing LOGIC_APP_URL or LOGIC_APP_AUDIENCE in app settings");
                    return req.CreateResponse(HttpStatusCode.BadRequest);
                }

                // 3️⃣ Call Logic App with bearer token
                var testPayload = new { message = "Test from Function App", timestamp = DateTime.UtcNow };
                var response = await CallLogicAppAsync(logicAppUrl, token, testPayload, log);

                log.LogInformation("✅ Logic App call succeeded: {response}", response);

                var okResponse = req.CreateResponse(HttpStatusCode.OK);
                await okResponse.WriteAsJsonAsync(new
                {
                    status = "success",
                    message = "Bearer token flow validated",
                    logicAppResponse = response,
                    timestamp = DateTime.UtcNow
                });

                return okResponse;
            }
            catch (HttpRequestException ex) when (ex.StatusCode == HttpStatusCode.Unauthorized)
            {
                log.LogError("❌ 401 Unauthorized — Token invalid (signature, audience, or expiry)");
                var errorResponse = req.CreateResponse(HttpStatusCode.Unauthorized);
                await errorResponse.WriteAsJsonAsync(new { error = "Unauthorized", details = ex.Message });
                return errorResponse;
            }
            catch (HttpRequestException ex) when (ex.StatusCode == HttpStatusCode.Forbidden)
            {
                log.LogError("❌ 403 Forbidden — Principal ID not in allowedPrincipals list");
                var errorResponse = req.CreateResponse(HttpStatusCode.Forbidden);
                await errorResponse.WriteAsJsonAsync(new { error = "Forbidden", details = ex.Message });
                return errorResponse;
            }
            catch (Exception ex)
            {
                log.LogError("❌ Error: {error}", ex.Message);
                var errorResponse = req.CreateResponse(HttpStatusCode.InternalServerError);
                await errorResponse.WriteAsJsonAsync(new { error = "Internal error", details = ex.Message });
                return errorResponse;
            }
        }

        private static async Task<string> GetAccessTokenAsync(ILogger log)
        {
            var credential = new DefaultAzureCredential(
                new DefaultAzureCredentialOptions
                {
                    TenantId = Environment.GetEnvironmentVariable("WEBSITE_AUTH_AAD_ALLOWED_TENANTS")
                }
            );

            var audience = Environment.GetEnvironmentVariable("LOGIC_APP_AUDIENCE");
            var tokenResponse = await credential.GetTokenAsync(
                new TokenRequestContext(new[] { $"{audience}/.default" })
            );

            log.LogInformation("Token acquired, expires: {expiry}", tokenResponse.ExpiresOn);
            return tokenResponse.Token;
        }

        private static async Task<string> CallLogicAppAsync(
            string url,
            string token,
            object payload,
            ILogger log)
        {
            using (var httpClient = new System.Net.Http.HttpClient())
            {
                // Add bearer token to Authorization header
                httpClient.DefaultRequestHeaders.Authorization =
                    new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);

                var content = new System.Net.Http.StringContent(
                    JsonConvert.SerializeObject(payload),
                    System.Text.Encoding.UTF8,
                    "application/json"
                );

                log.LogInformation("Calling Logic App at: {url}", url);
                var response = await httpClient.PostAsync(url, content);

                log.LogInformation("Logic App response: {status}", response.StatusCode);
                response.EnsureSuccessStatusCode();

                var responseBody = await response.Content.ReadAsStringAsync();
                return responseBody;
            }
        }
    }
}
```

### ✅ Step 4: Configure local.settings.json

**File: `local.settings.json`**

```json
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "DefaultEndpointsProtocol=https;AccountName=<storage>;AccountKey=<key>",
    "FUNCTIONS_WORKER_RUNTIME": "dotnet-isolated",
    "LOGIC_APP_URL": "https://easyauth-logic-<suffix>.azurewebsites.net/api/workflows/workflow1/triggers/manual/invoke?api-version=2022-05-01&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=<token>",
    "LOGIC_APP_AUDIENCE": "api://<logic-app-client-id>",
    "WEBSITE_AUTH_AAD_ALLOWED_TENANTS": "00922812-791e-41c8-a99e-45c3ed784cf5"
  }
}
```

---

## Run & Monitor Tests

### 🏃 Step 1: Deploy Function App to Azure

```bash
# Publish to Azure
func azure functionapp publish easyauth-func-<suffix> --build remote

# Verify deployment in portal
# Navigate to: Function Apps > easyauth-func-<suffix> > Functions > CallLogicApp
```

### 🏃 Step 2: Set Application Settings in Azure

```powershell
$funcAppName = "easyauth-func-<suffix>"
$rgName = "rg-la-easyauth-lab-dev"

# Get Logic App callback URL (from Logic App > Settings > Callback URL)
# Get Logic App client ID (from Logic App > Entra ID > Client ID)

az functionapp config appsettings set `
  --name $funcAppName `
  --resource-group $rgName `
  --settings LOGIC_APP_URL="<callback-url>" `
  LOGIC_APP_AUDIENCE="api://<client-id>" `
  WEBSITE_AUTH_AAD_ALLOWED_TENANTS="00922812-791e-41c8-a99e-45c3ed784cf5"
```

### 🏃 Step 3: Invoke Function

```bash
# Get Function URL (from portal or CLI)
FUNC_URL=$(az functionapp function show \
  --resource-group rg-la-easyauth-lab-dev \
  --name easyauth-func-<suffix> \
  --function-name CallLogicApp \
  --query invokeUrlTemplate -o tsv)

echo "Function URL: $FUNC_URL"

# Call function (POST request)
curl -X POST "$FUNC_URL" \
  -H "Content-Type: application/json" \
  -d '{"test": "data"}'
```

### 📊 Step 4: Monitor in Application Insights

```bash
# Tail live logs from Function App
func azure functionapp logstream easyauth-func-<suffix>

# Expected output:
# ✅ Bearer token acquired successfully
# ✅ Logic App call succeeded
```

---

## Collect Evidence

### ✅ Evidence Type 1: Function App Logs (Application Insights)

**Location:** Azure Portal → Function App → Application Insights → Logs

**Query:**

```kusto
traces
| where cloud_RoleName == "easyauth-func-<suffix>"
| where message startswith "✅" or message startswith "❌"
| project timestamp, message, severityLevel
| order by timestamp desc
| limit 50
```

**Screenshot:** Capture successful logs showing:
- ✅ Bearer token acquired successfully
- ✅ Logic App call succeeded

### ✅ Evidence Type 2: Bearer Token Structure (JWT Decode)

**Capture token from logs, then decode at https://jwt.io:**

```
Header:
{
  "alg": "RS256",
  "typ": "JWT",
  "kid": "..."
}

Payload:
{
  "aud": "api://<logic-app-client-id>",
  "iss": "https://login.microsoftonline.com/00922812-791e-41c8-a99e-45c3ed784cf5/v2.0",
  "appid": "<function-app-principal-id>",
  "oid": "<function-app-principal-id>",
  "exp": 1234567890,
  "iat": 1234567890,
  ...
}
```

**Screenshot:** Show decoded JWT with `aud` and `appid` fields

### ✅ Evidence Type 3: Logic App Execution History

**Location:** Azure Portal → Logic App → Run history

**Check:**
- Trigger: `manual/invoke` (from Function App)
- Status: **Succeeded** (green checkmark)
- Inputs: Bearer token in Authorization header
- Outputs: Logic App response body

**Screenshot:** Show successful run with:
- Timestamp matching Function App log
- Authorization: Bearer token present
- Status: Succeeded

### ✅ Evidence Type 4: End-to-End Request Flow Trace

**File: Create `docs/lab3-test-evidence.md`**

```markdown
## Lab 3 Test Evidence — 2026-07-03

### Test Scenario
Function App (CallLogicApp) → Logic App (workflow1) using managed identity bearer token

### Verification Steps

1. **Bearer Token Acquisition**
   - Managed Identity: ✅ Enabled on Function App
   - Token endpoint: ✅ Responsive
   - Scope: ✅ api://<logic-app-client-id>/.default

2. **Network Connectivity**
   - Function App → Private DNS Zone: ✅ Resolved
   - Private DNS Zone → Private Endpoint: ✅ Routed
   - Private Endpoint → Logic App: ✅ Connected

3. **Easy Auth Validation**
   - JWT Signature: ✅ Valid (RS256)
   - Audience (`aud`): ✅ Matches Logic App client ID
   - Expiry (`exp`): ✅ Not expired
   - Principal ID (`oid`): ✅ In allowedPrincipals

4. **Logic App Execution**
   - Trigger fired: ✅ Yes (timestamp matched)
   - Payload received: ✅ Yes
   - Actions executed: ✅ Yes
   - Response returned: ✅ Yes

### Metrics

- Token acquisition time: ~500ms
- HTTP request time: ~800ms
- End-to-end latency: ~1.3s
- Success rate: 100% (10/10 calls)

### Conclusion

✅ **Lab 3 bearer token flow is fully functional**

The Function App successfully:
1. Acquires bearer token from Entra ID using managed identity
2. Routes traffic through VNet to private DNS zone
3. Resolves private DNS to Logic App private endpoint IP
4. Sends HTTP request with bearer token to Logic App
5. Easy Auth validates token and executes workflow
```

### ✅ Evidence Type 5: Error Scenarios (Optional but Recommended)

Create test cases for 6 error scenarios:

```powershell
# Error Test 1: Invalid token signature (simulate by modifying token)
# Expected: 401 Unauthorized

# Error Test 2: Wrong audience
# Action: Set LOGIC_APP_AUDIENCE to wrong client ID
# Expected: 401 Unauthorized + Easy Auth rejects token

# Error Test 3: Expired token
# Action: Wait 1 hour or mock expired token
# Expected: 401 Unauthorized

# Error Test 4: Principal not in allowedPrincipals
# Action: Temporarily remove Function App principal from allowedPrincipals
# Expected: 403 Forbidden

# Error Test 5: Network isolation broken
# Action: Delete private endpoint
# Expected: Timeout or 404 (cannot resolve DNS)

# Error Test 6: Managed Identity disabled
# Action: Remove system-assigned identity from Function App
# Expected: AuthenticationFailedException
```

---

## Troubleshooting Checklist

| Issue | Root Cause | Verification Step | Fix |
|-------|-----------|-------------------|-----|
| **401 Unauthorized** | Invalid token signature | Decode JWT at jwt.io, verify RS256 | Check tenant ID, re-issue token |
| **401 Unauthorized** | Wrong audience | JWT `aud` claim != Logic App client ID | Update LOGIC_APP_AUDIENCE setting |
| **403 Forbidden** | Principal not in allowedPrincipals | Get Function App principal ID, check Bicep | Add principal to allowedPrincipals in Bicep |
| **AuthenticationFailedException** | Managed identity not enabled | Portal → Function App → Identity | Enable system-assigned identity |
| **Network timeout** | Private DNS not resolving | nslookup from Function App VNet | Verify private DNS zone, CNAME records |
| **Network timeout** | Private endpoint deleted | Portal → Private Endpoints | Redeploy private endpoint via Bicep |
| **Invalid URI** | LOGIC_APP_URL malformed | Check format: `https://<app>.azurewebsites.net/...` | Regenerate callback URL from Logic App |
| **500 Internal Error** | Unhandled exception | Check Application Insights logs | Review C# exception, add error handler |

---

## Proof of Concept Summary

| Aspect | Evidence | Status |
|--------|----------|--------|
| **Infrastructure** | Resource group + all 17 resources deployed | ✅ |
| **Managed Identity** | System-assigned MI on Function App | ✅ |
| **Bearer Token** | JWT with correct audience, expiry, claims | ✅ |
| **Easy Auth Validation** | Token signature, audience, expiry verified | ✅ |
| **Network Isolation** | Private DNS + private endpoint + VNet | ✅ |
| **End-to-End Flow** | Function App → Logic App with bearer token | ✅ |
| **Application Logs** | Success logs in Application Insights | ✅ |
| **Logic App Execution** | Workflow triggered and executed | ✅ |

---

## Next Steps

1. ✅ Deploy Function App with CallLogicApp function using C# code above
2. ✅ Configure application settings (LOGIC_APP_URL, LOGIC_APP_AUDIENCE)
3. ✅ Invoke function and monitor logs in Application Insights
4. ✅ Capture JWT token and decode at jwt.io
5. ✅ Document results in test evidence file
6. ✅ Run error scenario tests and capture failures
7. ✅ Archive all evidence (screenshots, logs, test report)

---

## Reference

- **Lab 3 Documentation:** [docs/lab3-managed-identity-bearer-token-flow.md](lab3-managed-identity-bearer-token-flow.md)
- **HTML Documentation:** [documentation/architecture/lab3-bearer-token-flow.html](../documentation/architecture/lab3-bearer-token-flow.html)
- **Code Examples:** See section "8. C# Code Examples" in HTML documentation
- **Bicep Infrastructure:** [infra/modules/](../infra/modules/)
