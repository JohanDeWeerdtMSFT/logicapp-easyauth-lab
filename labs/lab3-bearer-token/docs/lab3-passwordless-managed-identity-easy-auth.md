# Lab 3: Passwordless Managed Identity + Easy Auth Pattern

## Overview

This lab demonstrates **secure, passwordless communication** between an Azure Function App and an Azure Logic App Standard using:

- ✅ **Managed Identity** (no secrets, no connection strings)
- ✅ **Bearer Token Flow** (token-based authentication)
- ✅ **Easy Auth** (server-side token validation)
- ✅ **Entra ID** (identity provider)
- ❌ **NO callback URL signatures** (deprecated pattern)
- ❌ **NO shared secrets** (no SAS keys, no connection strings)
- ❌ **NO Function App keys** (no host keys)

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                      Entra ID Tenant                                │
│  (Token Authority)                                                  │
└─────────────────────┬───────────────────────────────────────────────┘
                      │
                      │ 1. Token Request
                      │ (Managed Identity credentials)
                      │
                      ▼
    ┌──────────────────────────────────────┐
    │  Azure Function App (S1 Plan)        │
    │  Name: la-easyauth-lab-dev-caller    │
    │                                      │
    │  ┌────────────────────────────────┐  │
    │  │ CallLogicApp.cs                │  │
    │  │ System-assigned MI: ENABLED    │  │
    │  │                                │  │
    │  │ 2. Acquire Bearer Token        │  │
    │  │    DefaultAzureCredential      │  │
    │  │    Audience: api://logicapp-id│  │
    │  │                                │  │
    │  │ 3. POST /api/workflows/...     │  │
    │  │    Authorization: Bearer <JWT> │  │
    │  └────────────────────────────────┘  │
    └──────────────────┬───────────────────┘
                       │
                       │ 4. HTTP POST with Bearer Token
                       │    (No SAS signature needed!)
                       │
                       ▼
    ┌──────────────────────────────────────────┐
    │  Azure Logic App Standard (WS1 Plan)     │
    │  Name: la-easyauth-lab-dev-la-daaq6t5x   │
    │                                          │
    │  ┌──────────────────────────────────┐   │
    │  │ Easy Auth Middleware              │   │
    │  │ (Protected by Entra ID)           │   │
    │  │                                   │   │
    │  │ 5. Validate Bearer Token:         │   │
    │  │    ✓ Token signature              │   │
    │  │    ✓ Audience (aud) matches       │   │
    │  │    ✓ Principal in allowedPrincipals   │   │
    │  │                                   │   │
    │  │ 6. Set X-MS-CLIENT-PRINCIPAL-*   │   │
    │  └──────────────────────────────────┘   │
    │                                          │
    │  ┌──────────────────────────────────┐   │
    │  │ httpTriggerWorkflow              │   │
    │  │ (HTTP-triggered workflow)        │   │
    │  │                                   │   │
    │  │ 7. Process request               │   │
    │  │    Return 200 + response JSON    │   │
    │  └──────────────────────────────────┘   │
    └──────────────────┬───────────────────────┘
                       │
                       │ 8. Response
                       │
                       ▼
    ┌──────────────────────────────────────┐
    │  Function App                        │
    │  (Displays success + token metadata) │
    └──────────────────────────────────────┘
```

## Required Azure Resources

### 1. Function App (Caller)
- **Name**: `la-easyauth-lab-dev-caller-*`
- **Plan**: S1 (Standard) or higher
- **Runtime**: .NET 8 isolated
- **System-assigned Managed Identity**: ENABLED
- **Easy Auth**: Microsoft Entra ID
  - Authentication: Required
  - Unauthenticated requests: Allow (HTTP trigger must accept, Easy Auth middleware validates)
  - allowedPrincipals: [Logic App's managed identity Object ID]
- **Network**: VNet integration (outbound) to reach Logic App private endpoint
- **Storage**: Identity-based (no shared keys)

### 2. Logic App Standard
- **Name**: `la-easyauth-lab-dev-la-*`
- **Plan**: WS1 (Workflow Standard)
- **System-assigned Managed Identity**: ENABLED
- **Easy Auth**: Microsoft Entra ID
  - Authentication: Required
  - Unauthenticated requests: Allow (HTTP trigger must accept)
  - allowedPrincipals: [Function App's managed identity Object ID]
- **Network**: Private endpoint + VNet integration
- **Entra ID App Registration**: Must exist with Easy Auth configuration
- **Workflow**: `httpTriggerWorkflow` (HTTP-triggered)
  - Trigger: GET/POST HTTP request
  - Returns: 200 OK + token metadata

### 3. Entra ID (Microsoft Entra)
- **Function App registration**: For token acquisition
- **Logic App registration**: For token validation
- **Tenant ID**: Used for token signing and validation

## Application Settings (Function App)

| Setting | Value | Purpose |
|---------|-------|---------|
| `LOGIC_APP_URL` | `https://<logicapp-name>.azurewebsites.net/api/workflows/httpTriggerWorkflow/triggers/manual/invoke?api-version=2022-05-01` | **No SAS signature!** Base invoke URL only |
| `LOGIC_APP_AUDIENCE` | `api://<logicapp-client-id>` | Token audience for Easy Auth validation |
| `WEBSITE_AUTH_AAD_ALLOWED_TENANTS` | `<tenant-id>` | Tenant for token acquisition and validation |

## Code Flow

### Step 1: Acquire Bearer Token (Function App)

```csharp
// DefaultAzureCredential automatically uses system-assigned managed identity
var credential = new DefaultAzureCredential(new DefaultAzureCredentialOptions
{
    TenantId = tenantId
});

var accessToken = await credential.GetTokenAsync(
    new TokenRequestContext(scopes: [$"{audience}/.default"]),
    cancellationToken);
```

**What happens:**
- Managed identity's credentials are retrieved from Azure Metadata Service (`http://169.254.169.254`)
- Entra ID validates the managed identity and issues a Bearer token
- Token audience = Logic App's Entra ID app registration client ID
- Token audience ensures token is meant for the Logic App, not another service

### Step 2: Call Logic App with Bearer Token

```csharp
var request = new HttpRequestMessage(HttpMethod.Post, logicAppUrl)
{
    Content = new StringContent(payload)
};

// This is the authentication mechanism (not a SAS signature!)
request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearerToken);

var response = await client.SendAsync(request);
```

**What happens:**
- HTTP POST sent to Logic App trigger URL
- Authorization header contains Bearer token (JWT signed by Entra ID)
- No SAS signature or callback URL secret is needed

### Step 3: Easy Auth Validates Bearer Token (Logic App)

Easy Auth middleware intercepts the request before it reaches the workflow:

1. **Extract Bearer token** from Authorization header
2. **Validate token signature** using Entra ID public key
3. **Validate token audience (aud)** = Logic App's client ID
4. **Validate token expiry** (not expired)
5. **Validate caller principal** against allowedPrincipals list
6. **Accept or reject** request with 200/401/403

If validation passes:
- Request is forwarded to the workflow
- X-MS-CLIENT-PRINCIPAL-NAME and X-MS-CLIENT-PRINCIPAL-ID headers are set
- Workflow can inspect these headers if needed

## Configuration Steps

### 1. Deploy Infrastructure (via Bicep)

The infrastructure is already deployed. Verify:

```powershell
az resource list --resource-group rg-la-easyauth-lab-dev `
  --query "[].{name:name, type:type}" -o table
```

Expected resources:
- Logic App: `la-easyauth-lab-dev-la-daaq6t5xzrpaw`
- Function App: `la-easyauth-lab-dev-caller-daaq6t5xzrpaw`
- Storage Account (identity-based)
- App Service Plans
- Private endpoints + DNS zones
- Application Insights

### 2. Deploy Workflow to Logic App

⚠️ **The workflow file exists but needs to be deployed:**

**Option A: Azure Portal (Easiest)**
1. Go to [Azure Portal](https://portal.azure.com)
2. Search for Logic App: `la-easyauth-lab-dev-la-daaq6t5xzrpaw`
3. Click **Workflows** tab
4. Click **Add** button
5. Name: `httpTriggerWorkflow`
6. Open [src/httpTriggerWorkflow/workflow.json](../../src/httpTriggerWorkflow/workflow.json)
7. Copy the entire JSON content
8. Paste into Portal's workflow editor
9. Click **Save**

**Option B: VS Code Logic Apps Extension**
1. Install [Azure Logic Apps (Standard)](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-logic-apps) extension
2. Connect to Logic App resource
3. Create new workflow from JSON file

### 3. Add Function App to Logic App allowedPrincipals

Get Function App's managed identity Object ID:

```powershell
$functionAppObjectId = az functionapp identity show `
  --name "la-easyauth-lab-dev-caller-daaq6t5xzrpaw" `
  --resource-group "rg-la-easyauth-lab-dev" `
  --query principalId -o tsv

Write-Host "Function App Object ID: $functionAppObjectId"
```

Add to Logic App's Easy Auth:

```powershell
az rest --method patch `
  --uri "https://management.azure.com/subscriptions/6851693c-0b74-4462-8da8-cd498b088827/resourceGroups/rg-la-easyauth-lab-dev/providers/Microsoft.Web/sites/la-easyauth-lab-dev-la-daaq6t5xzrpaw/config/authsettingsv2?api-version=2023-12-01" `
  --body @-<<EOF
{
  "properties": {
    "identityProviders": {
      "azureActiveDirectory": {
        "validation": {
          "allowedPrincipals": {
            "identities": [
              "$functionAppObjectId"
            ]
          }
        }
      }
    }
  }
}
EOF
```

### 4. Configure Function App Settings

Using the deployment script:

```powershell
cd solution

.\deploy.ps1 `
  -FunctionAppName "la-easyauth-lab-dev-caller-daaq6t5xzrpaw" `
  -ResourceGroupName "rg-la-easyauth-lab-dev" `
  -LogicAppUrl "https://la-easyauth-lab-dev-la-daaq6t5xzrpaw.azurewebsites.net/api/workflows/httpTriggerWorkflow/triggers/manual/invoke?api-version=2022-05-01" `
  -LogicAppAudience "api://786594a8-6b38-40cf-8c6b-d434b539dd46" `
  -TenantId "00922812-791e-41c8-a99e-45c3ed784cf5"
```

**Important**: No SAS signature or callback URL secret is passed!

### 5. Deploy Function App Code

The script above also publishes and deploys the code. Verify:

```powershell
az functionapp config appsettings list `
  --name "la-easyauth-lab-dev-caller-daaq6t5xzrpaw" `
  --resource-group "rg-la-easyauth-lab-dev" `
  --query "[?name=='LOGIC_APP_URL' || name=='LOGIC_APP_AUDIENCE' || name=='WEBSITE_AUTH_AAD_ALLOWED_TENANTS']" `
  -o table
```

## Testing

### Test 1: Verify Bearer Token Flow

```bash
# Get Function App URL
FUNC_URL=$(az functionapp show \
  --name "la-easyauth-lab-dev-caller-daaq6t5xzrpaw" \
  --resource-group "rg-la-easyauth-lab-dev" \
  --query defaultHostName -o tsv)

# Invoke the function
curl -X POST "https://$FUNC_URL/api/CallLogicApp"
```

**Expected response:**
```json
{
  "status": "success",
  "message": "Bearer token flow verified — Easy Auth accepted the request.",
  "logicAppResponse": "{...}",
  "tokenExpiry": "2026-07-03T15:30:00.000000Z"
}
```

### Test 2: Check Application Insights Logs

In Application Insights, search for `CallLogicApp`:

```kusto
traces
| where message contains "Bearer token"
| project timestamp, message, severityLevel
```

Expected log entries:
- "Bearer token acquired"
- "POST → Logic App: https://..."
- "Logic App response: HTTP 200"

### Test 3: Verify Easy Auth Accepted the Token

Check Application Insights for authentication events:

```kusto
customEvents
| where name == "Easy Auth Validation"
| project timestamp, customDimensions
```

## Troubleshooting

| Error | Cause | Solution |
|-------|-------|----------|
| **401 Unauthorized** | Bearer token is invalid or expired | Verify LOGIC_APP_AUDIENCE matches Logic App's Entra ID app registration client ID |
| **403 Forbidden** | Function App principal not in allowedPrincipals | Add Function App's managed identity Object ID to Logic App's allowedPrincipals list |
| **Missing app settings** | LOGIC_APP_URL, LOGIC_APP_AUDIENCE, or WEBSITE_AUTH_AAD_ALLOWED_TENANTS not configured | Run deploy.ps1 or set manually in Portal |
| **Credential unavailable** | System-assigned managed identity not enabled | Enable in Portal: Function App → Identity → System assigned → On |
| **Workflow not found** | httpTriggerWorkflow not deployed | Deploy workflow via Portal or VS Code extension |

## Why No Callback URL Signature?

### Legacy Pattern (Not Used Here)
```
https://logic-app.azurewebsites.net/api/...?api-version=2022-05-01&sp=...&sv=...&sig=XXXXX
├─ sig = SAS (Shared Access Signature)
├─ Derived from Logic App's shared key
├─ Expires after deployment
├─ Must be regenerated and redistributed
├─ Secret embedded in configuration
```

### Modern Pattern (Used Here) ✅
```
https://logic-app.azurewebsites.net/api/...?api-version=2022-05-01
├─ Authorization: Bearer <JWT>
├─ JWT issued by Entra ID
├─ Signed with Entra ID private key
├─ Validated with Entra ID public key
├─ Short-lived (typically 1 hour)
├─ No secrets in configuration
├─ No manual rotation needed
```

## Key Takeaways

1. **No Secrets in Code or Config** — Bearer tokens are issued on-demand by Entra ID
2. **Managed Identity is Transparent** — Just use `DefaultAzureCredential`
3. **Easy Auth Validates Server-Side** — Not in the Function App code
4. **Token Audience Matters** — Ensures token is meant for the right service
5. **allowedPrincipals Acts as an ACL** — Only specific identities are allowed
6. **Passwords Never Needed** — Managed identities are cryptographic and never expire

This pattern is the foundation of Zero Trust security in Azure.
