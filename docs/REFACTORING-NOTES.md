# Refactoring Summary: From SAS Signatures to Passwordless Managed Identity

## Overview

This lab has been refactored to be **completely passwordless**. The solution now uses **Managed Identity + Easy Auth** instead of callback URL signatures.

## What Changed

### ❌ REMOVED: SAS Signatures

**Before (Legacy Pattern):**
```powershell
# Deploy script required callback URL with SAS signature
.\deploy.ps1 `
  -LogicAppUrl "https://logic-app.azurewebsites.net/api/...?api-version=2022-05-01&sp=...&sv=...&sig=XXXXX_SECRET_XXXXX"
```

**Problems with SAS signatures:**
- Secret value embedded in configuration
- Only known after deployment
- Expires and requires manual rotation
- Must be stored and distributed securely
- Complicates automation and GitOps

### ✅ ADDED: Bearer Token Flow

**After (Passwordless Pattern):**
```powershell
# Deploy script requires only public information
.\deploy.ps1 `
  -LogicAppUrl "https://logic-app.azurewebsites.net/api/workflows/httpTriggerWorkflow/triggers/manual/invoke?api-version=2022-05-01" `
  -LogicAppAudience "api://786594a8-6b38-40cf-8c6b-d434b539dd46" `
  -TenantId "00922812-791e-41c8-a99e-45c3ed784cf5"
```

**Benefits:**
- ✅ No secrets in configuration
- ✅ Bearer tokens are issued on-demand by Entra ID
- ✅ Short-lived (typically 1 hour)
- ✅ Automatic rotation (no manual intervention)
- ✅ Managed Identity is transparent
- ✅ No Function App keys needed
- ✅ No Logic App shared keys exposed

## Files Changed

### 1. **solution/CallerFunctionApp/CallLogicApp.cs**
- Updated documentation to explain passwordless pattern
- Removed `MaskSasSignature()` helper (no longer needed)
- Added clarification that Bearer token IS the authentication mechanism
- Simplified logging (no SAS signature to mask)

**Key code:**
```csharp
// Acquire token using managed identity
var accessToken = await GetAccessTokenAsync(cancellationToken);

// Send to Logic App with Bearer token
request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearerToken);
```

### 2. **solution/CallerFunctionApp/local.settings.json**
- **REMOVED**: `&sig=<get-from-portal>` from LOGIC_APP_URL
- **ADDED**: Clear explanation of passwordless pattern
- **Updated**: Comments explaining each setting

**Before:**
```json
"LOGIC_APP_URL": "https://...?api-version=2022-05-01&sp=...&sv=...&sig=<get-from-portal>"
```

**After:**
```json
"LOGIC_APP_URL": "https://...?api-version=2022-05-01"
```

### 3. **solution/deploy.ps1**
- Updated `.PARAMETER LogicAppUrl` documentation
- **REMOVED**: Instruction to get callback URL from Portal
- **ADDED**: Explanation that no SAS signature is needed
- Updated example to show correct URL format
- **ADDED**: Console message highlighting "NO SECRETS" in settings

**Before:**
```
Find it: Azure Portal → Logic App → Workflows → httpTriggerWorkflow → Overview → Callback URL
```

**After:**
```
Base invoke URL of the Logic App HTTP trigger (no SAS signature needed!)
Format: https://<logicapp-name>.azurewebsites.net/api/workflows/...
Why no signature? Managed Identity bearer token provides authentication instead.
```

### 4. **docs/lab3-passwordless-managed-identity-easy-auth.md** (NEW)
- Comprehensive documentation of passwordless pattern
- Architecture diagram
- Step-by-step configuration
- Testing procedures
- Troubleshooting guide
- Comparison with legacy SAS signature pattern

### 5. **infra/modules/functionapp-caller.bicep** (Already Correct)
- Already sets `LOGIC_APP_URL` without SAS signature ✅
- No changes needed

## How It Works

### 1. Function App Acquires Bearer Token

```
Function App (with System-assigned MI)
    ↓
    Uses DefaultAzureCredential
    ↓
    Calls Entra ID Metadata Service (http://169.254.169.254)
    ↓
    Entra ID validates managed identity
    ↓
    Issues Bearer Token (JWT) with:
        - aud: Logic App's client ID
        - sub: Function App's identity
        - exp: 1 hour from now
```

### 2. Function App Calls Logic App

```
Function App
    ↓
    POST https://logic-app.azurewebsites.net/api/workflows/.../triggers/manual/invoke
    Authorization: Bearer <JWT>
    ↓
    Logic App receives request
```

### 3. Easy Auth Validates Bearer Token

```
Easy Auth Middleware
    ↓
    Extract Bearer token from Authorization header
    ↓
    Validate token signature using Entra ID public key
    ↓
    Validate audience (aud) matches Logic App's client ID
    ↓
    Validate token not expired
    ↓
    Validate caller principal in allowedPrincipals list
    ↓
    Accept ✅ or Reject ❌
```

## Configuration Required

### Before Deployment:

1. **Function App Managed Identity**: Must be system-assigned and enabled ✅
2. **Logic App Managed Identity**: Must be system-assigned and enabled ✅
3. **Easy Auth**: Must be configured on both apps ✅
4. **allowedPrincipals**: Function App's Object ID must be added to Logic App's allowedPrincipals ✅

### Settings (No Secrets!):

| Setting | Example Value |
|---------|---------------|
| LOGIC_APP_URL | `https://la-easyauth-lab-dev-la-daaq6t5xzrpaw.azurewebsites.net/api/workflows/httpTriggerWorkflow/triggers/manual/invoke?api-version=2022-05-01` |
| LOGIC_APP_AUDIENCE | `api://786594a8-6b38-40cf-8c6b-d434b539dd46` |
| WEBSITE_AUTH_AAD_ALLOWED_TENANTS | `00922812-791e-41c8-a99e-45c3ed784cf5` |

**None of these values are secrets!** They're all:
- Publicly discoverable (via Azure Portal)
- Non-sensitive
- No expiration
- No rotation needed

## Deployment

### Old Way (Not Used)
```powershell
# Had to manually get callback URL with SAS signature from Portal
Get-LogicAppCallbackUrl  # From Portal ← requires manual steps
.\deploy.ps1 -LogicAppUrl "<URL with SAS signature>"
```

### New Way
```powershell
# All values are discoverable and non-sensitive
.\deploy.ps1 `
  -FunctionAppName "la-easyauth-lab-dev-caller-daaq6t5xzrpaw" `
  -ResourceGroupName "rg-la-easyauth-lab-dev" `
  -LogicAppUrl "https://la-easyauth-lab-dev-la-daaq6t5xzrpaw.azurewebsites.net/api/workflows/httpTriggerWorkflow/triggers/manual/invoke?api-version=2022-05-01" `
  -LogicAppAudience "api://786594a8-6b38-40cf-8c6b-d434b539dd46" `
  -TenantId "00922812-791e-41c8-a99e-45c3ed784cf5"
```

## Security Implications

### Authentication Method
- ✅ **Managed Identity** — Secure, cryptographic credentials
- ✅ **Bearer Token** — JWT signed by Entra ID
- ✅ **Short-lived** — 1 hour expiration
- ✅ **Server-side Validation** — Easy Auth validates on Logic App

### Authorization Method
- ✅ **allowedPrincipals ACL** — Whitelist of allowed identities
- ✅ **Principal Validation** — Token subject verified
- ✅ **Entra ID Integration** — Claims validation by Entra ID

### Secret Management
- ✅ **Zero Secrets** — No passwords, keys, or SAS signatures
- ✅ **No Credential Distribution** — Each service has its own identity
- ✅ **No Rotation Needed** — Tokens auto-rotated by Entra ID
- ✅ **Audit Trail** — All token requests logged

## Testing

### Quick Test
```powershell
# Invoke Function App (unauthenticated HTTP trigger)
curl -X POST "https://<func-app>.azurewebsites.net/api/CallLogicApp"

# Expected: 200 OK + success message
```

### Application Insights
```kusto
traces
| where message contains "Bearer token"
| project timestamp, message
```

## Comparison: SAS Signature vs Bearer Token

| Aspect | SAS Signature | Bearer Token |
|--------|---------------|--------------|
| **Secret?** | Yes (sig=...) | No |
| **Expires?** | After deployment | 1 hour (auto-renews) |
| **Rotation** | Manual (get new callback URL) | Automatic |
| **Storage** | In config (risky!) | Issued on-demand |
| **Validation** | URL signature check | Entra ID signature + claims |
| **Standard** | Azure-specific | OAuth 2.0 / OpenID Connect |
| **Zero Trust** | ❌ No | ✅ Yes |

## Key Takeaways

1. **The code was already correct** — It implemented managed identity bearer token flow
2. **The documentation was misleading** — It suggested using SAS signatures (legacy)
3. **Refactoring was minimal** — Updated docs and removed dead code
4. **Result is truly passwordless** — No secrets anywhere
5. **Security is improved** — Bearer tokens are better than SAS signatures
6. **Pattern is cloud-native** — Uses industry-standard OAuth 2.0

## Next Steps

1. ✅ Deploy workflow to Logic App (via Portal or VS Code)
2. ✅ Run deployment script without any secrets
3. ✅ Test bearer token flow
4. ✅ Review Application Insights logs
5. ✅ Demonstrate to stakeholders

See [lab3-passwordless-managed-identity-easy-auth.md](lab3-passwordless-managed-identity-easy-auth.md) for complete setup instructions.
