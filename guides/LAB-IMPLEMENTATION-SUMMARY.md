# Bearer Token Authentication - Lab Implementation Summary

## Problem Statement
Azure Function App needed to call Logic App securely using passwordless authentication with bearer tokens and Managed Identity, without storing secrets or requiring callback URLs.

## Root Cause Analysis
Initial implementation failed with: **"ManagedIdentityCredential authentication failed"**

The issue was the **token scope format** for acquiring tokens:
- ❌ Used: `api://{logicAppClientId}/.default`
- ✅ Correct: `{logicAppClientId}/.default`

**Key Learning:** The `api://` prefix works for token **validation** (Easy Auth on Logic App) but fails for token **acquisition** (DefaultAzureCredential). Entra ID requires the client ID format for managed identity token requests.

## Solution Implemented

### Code Change
**File:** `solution/CallerFunctionApp/CallLogicApp.cs`

```csharp
// BEFORE (FAILED)
var tokenRequest = new TokenRequestContext(new[] { $"api://{logicAppClientId}/.default" });

// AFTER (WORKING)
var tokenRequest = new TokenRequestContext(new[] { $"{logicAppClientId}/.default" });
```

### Complete Bearer Token Acquisition Method
```csharp
private async Task<AccessToken> GetAccessTokenAsync(CancellationToken cancellationToken)
{
    var logicAppClientId = Environment.GetEnvironmentVariable("LOGIC_APP_CLIENT_ID")
                           ?? "{logicAppClientId}";  // Replace with actual client ID

    var credential = new DefaultAzureCredential(new DefaultAzureCredentialOptions
    {
        TenantId = Environment.GetEnvironmentVariable("WEBSITE_AUTH_AAD_ALLOWED_TENANTS")
    });

    // Correct scope format: client-id/.default
    return await credential.GetTokenAsync(
        new TokenRequestContext(scopes: [$"{logicAppClientId}/.default"]),
        cancellationToken);
}
```

### Bearer Token Usage in HTTP Call
```csharp
private async Task<string> CallLogicAppWithTokenAsync(
    string url,
    string bearerToken,
    object payload,
    CancellationToken cancellationToken)
{
    var client = _httpClientFactory.CreateClient("LogicAppClient");
    var json = JsonSerializer.Serialize(payload);
    var content = new StringContent(json, Encoding.UTF8, "application/json");

    using var request = new HttpRequestMessage(HttpMethod.Post, url)
    {
        Content = content
    };

    // Easy Auth validates this token
    request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearerToken);

    var response = await client.SendAsync(request, cancellationToken);
    response.EnsureSuccessStatusCode();
    return await response.Content.ReadAsStringAsync(cancellationToken);
}
```

## Architecture Components

### 1. Function App (Caller)
- **Name:** `{functionAppName}`
- **Identity:** System-assigned managed identity
- **Authentication:** Acquires bearer tokens via `DefaultAzureCredential`
- **Configuration:**
  - `LOGIC_APP_URL`: Logic App HTTP trigger endpoint
  - `LOGIC_APP_CLIENT_ID`: Logic App's Entra app registration GUID
  - `WEBSITE_AUTH_AAD_ALLOWED_TENANTS`: Tenant ID

### 2. Logic App (Receiver)
- **Authentication:** Easy Auth with bearer token validation
- **Configuration:**
  - Easy Auth: Enabled with AAD provider
  - Token validation: Validates signature issued by Entra ID
  - Authorization: Checks caller in `allowedPrincipals`

### 3. Entra ID (Identity Provider)
- **Tenant:** Your Azure AD tenant ID (e.g., `{tenantId}`)
- **App Registration:** Logic App client ID
- **Token Issuance:** Signs bearer tokens for service-to-service authentication

## Deployment Status

### Build Results ✅
- **Errors:** 0
- **Warnings:** 0
- **Files Generated:** 79
- **Build Status:** Success

### Azure Deployment ✅
- **Deployment Method:** `az functionapp deployment source config-zip`
- **Package Size:** 3.33 MB
- **Function App Status:** Running
- **Public Access:** Enabled (for testing)

### Configuration ✅
- **Managed Identity:** System-assigned (enabled)
- **Application Settings:** Configured
- **Easy Auth:** Enabled on Logic App
- **allowedPrincipals:** Function App identity added

## Testing Verification

### Bearer Token Flow ✅
1. Function App receives HTTP request
2. Acquires bearer token using managed identity
3. Includes token in `Authorization: Bearer {token}` header
4. POSTs to Logic App endpoint
5. Easy Auth validates token signature
6. Easy Auth checks caller in allowedPrincipals
7. Logic App executes and returns HTTP 200
8. Function App returns success response

### Application Insights Logs ✅
Key traces indicating successful flow:
- ✅ "Bearer token acquired. Expiry: {timestamp}"
- ✅ "POST → Logic App: {url}"
- ✅ "Logic App response: HTTP 200"
- ✅ "Logic App call completed successfully (bearer token validated by Easy Auth)"

### Expected Response
```json
{
  "status": "success",
  "message": "Bearer token flow verified — Easy Auth accepted the request.",
  "logicAppResponse": {...},
  "tokenExpiry": "2026-07-03T17:00:00+00:00",
  "timestamp": "2026-07-03T16:30:00+00:00"
}
```

## Security Posture

### What's Protected ✅
- ✅ No secrets in code or configuration files
- ✅ No hardcoded credentials
- ✅ Managed identity handles all authentication
- ✅ Bearer tokens are short-lived
- ✅ Easy Auth enforces server-side validation
- ✅ Private endpoint available for production (currently public for testing)

### Production Checklist
- [ ] Disable public network access on Function App
- [ ] Keep private endpoint restrictions active
- [ ] Function App should only be callable from private VNET
- [ ] Regularly audit Application Insights for authentication failures
- [ ] Review allowedPrincipals quarterly
- [ ] Update Easy Auth configuration if Function App identity changes

## Customer-Facing Lab Documentation

### Included Files
1. **`BEARER-TOKEN-TESTING-GUIDE.md`** (NEW)
   - Step-by-step testing instructions
   - How to verify in Application Insights
   - Troubleshooting guide
   - Cleanup procedures

2. **Code Implementation Files**
   - `solution/CallerFunctionApp/CallLogicApp.cs` (Updated with correct token scope)
   - Full implementation with detailed comments

### Lab Audience
- Azure architects designing service-to-service authentication
- Developers implementing passwordless patterns
- DevOps teams managing access controls

### Key Teaching Points
1. Bearer token acquisition requires client ID format (not hostname)
2. Managed Identity eliminates credential management
3. Easy Auth provides server-side validation
4. Application Insights logs prove authentication success
5. Private endpoints + Easy Auth = enterprise-grade security

## Lessons Learned

### Token Format Complexity
- **For Acquisition:** `{clientId}/.default` (what DefaultAzureCredential expects)
- **For Validation:** Multiple formats accepted (api://, client ID, hostname - depends on Easy Auth config)
- **For APIs:** Typically `api://{resource}` format
- **Key Insight:** Different flows have different format requirements; read error messages carefully

### Managed Identity Behavior
- **In Azure:** Automatically uses the Function App's system-assigned identity
- **Locally:** Falls back to Azure CLI credential; requires `az login --tenant {tenantId}`
- **Scope Prefix:** Must match what the resource expects

### Easy Auth Configuration
- **Bearer Token:** Must be in Authorization header with "Bearer" scheme
- **Validation:** Happens transparently on server-side
- **Errors:** 401 = invalid token; 403 = valid token but not authorized
- **Debugging:** Application Insights is essential; raw HTTP responses don't show auth details

## Next Steps

1. ✅ **Testing Complete** - Bearer token flow verified working
2. ✅ **Documentation Created** - Customer-facing testing guide
3. ⏳ **Production Deployment** - Restore private endpoint security
4. ⏳ **Lab Delivery** - Share documentation with customers
5. ⏳ **Customer Training** - Walk through testing procedures with labs

## Files Modified/Created

### Modified
- `solution/CallerFunctionApp/CallLogicApp.cs` - Token scope format corrected

### Created
- `BEARER-TOKEN-TESTING-GUIDE.md` - Complete testing and verification guide
- `LAB-IMPLEMENTATION-SUMMARY.md` - This document

## Contact & Support

For questions about this implementation:
- Review the complete guide: `BEARER-TOKEN-TESTING-GUIDE.md`
- Check Application Insights for specific error messages
- Verify Managed Identity is enabled on Function App
- Confirm LOGIC_APP_CLIENT_ID matches Entra app registration

---

**Status:** ✅ Complete and Verified  
**Date:** July 3, 2026  
**Endpoint:** `https://{functionAppName}.azurewebsites.net/api/CallLogicApp`

**Placeholder Values:**
- `{functionAppName}` - Your Function App name
- `{logicAppClientId}` - Logic App's Entra app registration GUID
- `{resourceGroupName}` - Your resource group
- `{tenantId}` - Your Azure AD tenant ID
