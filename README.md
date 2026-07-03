# Logic App Standard — Security Labs

## Purpose

Two complementary Azure labs to validate different security patterns for Logic App Standard HTTP triggers:

1. **Lab 1 — Easy Auth** (`rg-la-easyauth-lab-dev`): Validates that Easy Auth can enforce Entra ID authentication **without breaking portal manageability** using the `AllowAnonymous` + `allowedPrincipals` pattern.
2. **Lab 2 — APIM-Centric** (`rg-la-easyauth-lab-apim-dev`): Demonstrates centralized JWT validation at API Management, with backend Logic Apps protected via network restrictions instead of Easy Auth.
3. **Lab 3 — Function App Caller with Easy Auth** (`rg-la-easyauth-lab-dev` — extends Lab 1): Demonstrates a Function App calling a Logic App via private endpoints with **managed identity-based authentication** (no shared secrets).

> See [`docs/decision-guidance.md`](docs/decision-guidance.md) for a detailed comparison of when to use which pattern.

### References

- [Microsoft Learn — Secure Integration Workflows (Method 2: Easy Auth)](https://learn.microsoft.com/en-us/community/content/secure-integration-workflows-azure-logic-apps-api-management#method-2-security-using-easy-auth) — primary reference for Lab 1
- [azcloudsecurity.io — Logic App Standard Easy Auth](https://azcloudsecurity.io/posts/logic-app-standard-easy-auth/) — AllowAnonymous pattern analysis
- [Microsoft Learn — App Service Authentication Overview](https://learn.microsoft.com/en-us/azure/app-service/overview-authentication-authorization#considerations-for-using-built-in-authentication) — Easy Auth middleware architecture
- [Microsoft Learn — Secure Logic Apps with VNet and Private Endpoints](https://learn.microsoft.com/en-us/azure/logic-apps/secure-single-tenant-workflow-virtual-network-private-endpoint) — network isolation patterns
- [Microsoft Learn — Managed Identities for Azure Resources](https://learn.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/overview) — foundation for Lab 3 identity-based auth
- **[📖 Lab 3 Technical Deep-Dive: Managed Identity Bearer Token Flow](docs/lab3-managed-identity-bearer-token-flow.md)** — ⭐ **Complete guide to Lab 3 authentication pattern** (no SAS tokens, C# code examples, mermaid diagrams, error handling)

## Lab 1 — Easy Auth (AllowAnonymous Pattern)

### Architecture

```text
┌─────────────────────────────────────────────────┐
│  Resource Group: rg-la-easyauth-lab-dev          │
│                                                   │
│  ┌─────────────┐  ┌────────────────────────┐     │
│  │ App Service  │  │ Logic App Standard      │     │
│  │ Plan (WS1)  │──│ (la-easyauth-lab-xxx)  │     │
│  └─────────────┘  │                          │     │
│                    │ ┌────────────────────┐  │     │
│                    │ │ httpTriggerWorkflow│  │     │
│                    │ └────────────────────┘  │     │
│                    │                          │     │
│                    │ authsettingsV2:          │     │
│                    │ ├─ AllowAnonymous        │     │
│                    │ ├─ allowedPrincipals     │     │
│                    │ └─ platform.enabled: true│     │
│                    └────────────────────────┘     │
│                                                   │
│  ┌────────────────┐  ┌───────────────────┐       │
│  │ Storage Account│  │ App Insights      │       │
│  │ (managed ID)   │  │ + Log Analytics   │       │
│  └────────────────┘  └───────────────────┘       │
└─────────────────────────────────────────────────┘
```

### Key Insight: AllowAnonymous is Required

> **Microsoft Learn** ([Method 2](https://learn.microsoft.com/en-us/community/content/secure-integration-workflows-azure-logic-apps-api-management#method-2-security-using-easy-auth)): *"If `unauthenticatedClientAction` is set to `Return401`, the request doesn't get routed to the Azure Logic Apps runtime and fails with the 401 error from Azure App Service. With this error, you also get a broken Azure portal experience."*

- **Portal management**: ✅ Works with AllowAnonymous
- **Token enforcement**: ✅ Requests with Authorization header are validated against Entra requirements
- **SAS keys**: Remain available as a trigger mechanism

## Lab 3 — Function App Caller with Easy Auth (Managed Identity Pattern)

### Architecture

```text
┌──────────────────────────────────────────────────────────────────┐
│ Resource Group: rg-la-easyauth-lab-dev (extends Lab 1)            │
│                                                                    │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ Virtual Network (10.0.0.0/16)                               │ │
│  │                                                              │ │
│  │  Subnet 1: App Integration (10.0.0.0/24)                    │ │
│  │  ├─ VNet-integrated Function App (caller)                   │ │
│  │  │  ├─ System-Assigned MI (bearer token → Logic App)        │ │
│  │  │  └─ Easy Auth (AllowAnonymous + allowedPrincipals)       │ │
│  │  │                                                           │ │
│  │  Subnet 2: Private Endpoint (10.0.1.0/24)                   │ │
│  │  ├─ PE for Logic App                                        │ │
│  │  │  └─ Private DNS zone (privatelink.azurewebsites.net)    │ │
│  │  │                                                           │ │
│  │  │     ┌──────────────────────────────┐                    │ │
│  │  │     │ Logic App Standard (WS1)      │                    │ │
│  │  │     │ la-easyauth-lab-xxx-la       │                    │ │
│  │  │     │                               │                    │ │
│  │  │     │ authsettingsV2:               │                    │ │
│  │  │     │ ├─ AllowAnonymous             │                    │ │
│  │  │     │ ├─ allowedPrincipals:         │                    │ │
│  │  │     │ │  [Function App's MI PID]    │                    │ │
│  │  │     │ └─ platform.enabled: true     │                    │ │
│  │  │     │                               │                    │ │
│  │  │     │ publicNetworkAccess: Disabled │                    │ │
│  │  │     └──────────────────────────────┘                    │ │
│  │                                                              │ │
│  │ ┌─────────────────┐         ┌──────────────────────┐        │ │
│  │ │ Shared Storage  │         │ App Insights + LAW   │        │ │
│  │ │ (managed ID)    │         │                      │        │ │
│  │ └─────────────────┘         └──────────────────────┘        │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                    │
│  Request Flow:                                                     │
│  1. Caller (Function App) → SystemMI acquires token               │
│  2. Token includes aud=Logic App Entra app ID                     │
│  3. HTTPS call to Logic App private endpoint                      │
│  4. Private DNS resolves *.azurewebsites.net → PE IP              │
│  5. Private endpoint routes to Logic App (public disabled)        │
│  6. Easy Auth validates token, checks allowedPrincipals           │
│  7. Workflow executes (if principal ID matches)                   │
└──────────────────────────────────────────────────────────────────┘
```

### Key Insight: Managed Identity + Private Endpoints = Zero Secrets

> **📖 DETAILED EXPLANATION:** See [`docs/lab3-managed-identity-bearer-token-flow.md`](docs/lab3-managed-identity-bearer-token-flow.md) for a complete technical deep-dive:
> - How Function App acquires bearer tokens without SAS tokens
> - Step-by-step token flow with C# code examples
> - Easy Auth validation process explained
> - Mermaid diagrams showing request routing
> - Troubleshooting scenarios and error handling
> - Microsoft Learn documentation references

> **🧪 TESTING & VERIFICATION:** See [`docs/lab3-testing-and-verification.md`](docs/lab3-testing-and-verification.md) for complete step-by-step testing guide:
> - How to create and deploy a test Function App with bearer token code
> - How to verify infrastructure is configured correctly
> - How to invoke the function and monitor in Application Insights
> - How to collect evidence (JWT token, logs, execution history)
> - How to troubleshoot 6 common error scenarios

**Lab 3 eliminates all shared secrets:**
- Function App acquires access token using its **system-assigned managed identity** (no credentials to rotate)
- Token is presented as `Authorization: Bearer <token>` to Logic App private endpoint
- Logic App Easy Auth validates token and restricts access to **only the Function App's principal ID**
- Network isolation via private endpoints prevents public internet exposure

**Benefits:**
- ✅ **No secrets** to manage or rotate (managed identity is automatic)
- ✅ **Network isolation** via private endpoints (VNet-integrated caller, PE-protected receiver)
- ✅ **Fine-grained access** via Easy Auth `allowedPrincipals` (only specific identities can call)
- ✅ **Audit trail** via Azure AD sign-in logs (token acquisition is logged)
- ✅ **Portal management** preserved (AllowAnonymous + bearer token validation)

### When to Use Lab 3 Pattern

- **Self-contained workloads**: Function App and Logic App are part of the same solution (not multi-tenant)
- **Secure by default**: Want identity-based auth without APIM complexity
- **Ephemeral integration**: Temporary or service-to-service calls (not a stable API)
- **Few callers**: Only a handful of apps need access (use allowedPrincipals for each)

### Deployment

Lab 3 is deployed as an extension to Lab 1 by setting `deployFuncCallerDemo = true` in the bicep parameters:

```powershell
$params = @{
  environmentName = "dev"
  location = "westeurope"
  deployFuncCallerDemo = $true
  easyAuthMode = "AllowAnonymous"
  entraAppClientId = "<Logic App Entra client ID>"
  entraAppTenantId = "<Tenant ID>"
  funcCallerEntraClientId = "<Function App Entra client ID>"
}

az deployment group create `
  --resource-group rg-la-easyauth-lab-dev `
  --template-file infra/main.bicep `
  --parameters $params
```

**Deployed Resources:**
- Virtual Network (la-easyauth-lab-dev-vnet)
- Two subnets (app integration, private endpoints)
- Private DNS zone (privatelink.azurewebsites.net)
- Private endpoint for Logic App
- Dedicated Function App with S1 plan (required for VNet integration)
- System-assigned managed identity on Function App
- RBAC role assignments (Storage Blob Data Contributor for managed identity)

### Verification Steps

1. **Check Function App connectivity**:
   ```bash
   az webapp log stream --resource-group rg-la-easyauth-lab-dev \
     --name la-easyauth-lab-dev-caller-daaq6t5xzrpaw
   ```

2. **Review Easy Auth configuration**:
   ```bash
   az resource show --resource-group rg-la-easyauth-lab-dev \
     --resource-type "Microsoft.Web/sites/config" \
     --name la-easyauth-lab-dev-la-daaq6t5xzrpaw/authsettingsv2
   ```

3. **Test token acquisition** (from Function App code):
   ```csharp
   var credential = new DefaultAzureCredential();
   var token = await credential.GetTokenAsync(
     new TokenRequestContext(new[] { $"api://{logicAppEntraClientId}/.default" })
   );
   ```

4. **Monitor in Application Insights**:
   - Track token acquisition attempts
   - Watch for Easy Auth 401/403 responses
   - Verify request flow end-to-end

## Prerequisites

- Azure subscription with Contributor access
- Azure CLI installed and logged in
- Entra ID App Registration (for Easy Auth / APIM JWT validation)
  - Only a **blank** App Registration is needed — no redirect URIs, secrets, or scopes required for the basic setup
  - For Easy Auth (Lab 1): client secret stored via `MICROSOFT_PROVIDER_AUTHENTICATION_SECRET` (Key Vault reference recommended)
  - Reference: [azcloudsecurity.io — Creating the App Registration](https://azcloudsecurity.io/posts/logic-app-standard-easy-auth/#creating-the-app-registration)

## Quick Start

### Lab 1 (Easy Auth)
```powershell
.\scripts\deploy.ps1 -EntraAppClientId <clientId> -EntraAppTenantId <tenantId>
```

### Lab 3 (Function App Caller with Easy Auth)
```powershell
.\scripts\deploy.ps1 -EntraAppClientId <logic-app-client-id> `
  -EntraAppTenantId <tenantId> `
  -DeployFuncCallerDemo $true `
  -FuncCallerEntraClientId <function-app-client-id>
```

### Lab 2 (APIM)
```powershell
az deployment group create --resource-group rg-la-easyauth-lab-apim-dev `
  --template-file infra/apim-lab/main.bicep `
  --parameters infra/apim-lab/params.bicepparam
```

## Scenario Matrix

### Track A — Portal Manageability (Return401 vs AllowAnonymous)

| ID | Scenario              | Return401 | AllowAnonymous | Status |
|----|-----------------------|-----------|----------------|--------|
| A1 | View run history list | 🔴 Blocked | ✅ Accessible   | Confirmed |
| A2 | View run details      | 🔴 Blocked | ✅ Accessible   | Confirmed |
| A3 | View inputs/outputs   | 🔴 Blocked | ✅ Visible      | Confirmed |
| A4 | Re-run/Resubmit       | 🔴 Blocked | ✅ Works        | Confirmed |

### Track B — Trigger Security (AllowAnonymous + allowedPrincipals)

| ID | Scenario                   | Token                      | Expected HTTP | Status |
|----|----------------------------|----------------------------|---------------|--------|
| B1 | Valid token (right aud/principal) | Valid bearer           | 403           | ✅ `allowedPrincipals` restricts to APIM MI |
| B2 | Invalid token              | Expired/malformed           | 401           | ✅ Rejected by Easy Auth |
| B3 | Wrong audience             | Valid, wrong aud            | 401           | ✅ Rejected by Easy Auth |
| B4 | No token (no SAS)          | None                        | 401           | ✅ Rejected |
| B5 | No token + SAS key         | None, SAS key present       | 200           | ✅ SAS keys remain active |

### Track C — APIM JWT Validation (Lab 2)

| ID | Scenario                   | Token                      | Expected HTTP | Status |
|----|----------------------------|----------------------------|---------------|--------|
| C1 | Valid token through APIM   | Valid bearer                | 200           | ⏳ (requires MI auth)     |
| C2 | Invalid token through APIM | Expired/malformed           | 401           | ✅ Rejected by APIM |
| C3 | No token through APIM      | None                        | 401           | ✅ Rejected by APIM |
| C4 | Wrong audience through APIM| Valid, wrong aud            | 401           | ⏳      |

## Findings Log

See [`docs/evidence/findings.md`](docs/evidence/findings.md) for detailed observations.

## Key Findings

> **Critical: Easy Auth `Return401` breaks Logic App Standard portal — use `AllowAnonymous` instead.**

1. **`Return401` blocks hostruntime endpoints** — portal loses run history, details, re-run. Confirmed by [Microsoft Learn](https://learn.microsoft.com/en-us/community/content/secure-integration-workflows-azure-logic-apps-api-management#method-2-security-using-easy-auth) and lab testing.
2. **`AllowAnonymous` resolves this** — requests with Authorization header are still validated; portal management works.
3. **ARM-only operations are unaffected** regardless of Easy Auth mode.
4. **Two valid production patterns**: Easy Auth (Lab 1) for few apps with strict identity, APIM-centric (Lab 2) for scale.

## Recommended Architectures

See [`docs/decision-guidance.md`](docs/decision-guidance.md) for the full comparison.

## Conclusions

Two valid patterns exist, confirmed by [Microsoft Learn](https://learn.microsoft.com/en-us/community/content/secure-integration-workflows-azure-logic-apps-api-management) and [azcloudsecurity.io](https://azcloudsecurity.io/posts/logic-app-standard-easy-auth/):

- **Lab 1 — Easy Auth with `AllowAnonymous` + `allowedPrincipals`**: Best for limited numbers of apps where app-level identity enforcement is required. Portal management works. APIM authenticates via managed identity bearer token. SAS keys remain active.
- **Lab 2 — APIM-centric (no Easy Auth)**: Best at scale (hundreds of apps). Centralized JWT validation via `validate-jwt` policy, reduced IP consumption, simpler operations.

> Some references combine API Management and Easy Auth for defense‑in‑depth identity enforcement. While valid, enabling Easy Auth on Logic Apps Standard can introduce operational complexity and runtime manageability risks. Lab 2 demonstrates an alternative pattern where API Management enforces identity centrally, and backend Logic Apps are protected using network-level access restrictions, reducing the need for per-app Private Endpoints and preserving portal functionality.

See [`docs/decision-guidance.md`](docs/decision-guidance.md) for the full trade-off analysis.

## Teardown

```powershell
# Lab 1 + Lab 3 (same resource group)
az group delete --name rg-la-easyauth-lab-dev --yes --no-wait

# Lab 2 (separate resource group)
az group delete --name rg-la-easyauth-lab-apim-dev --yes --no-wait
```

## Cost Estimate

| Resource              | Lab 1 (Easy Auth) | Lab 2 (APIM) | Lab 3 (Func Caller) |
|-----------------------|-------------------|--------------|---------------------|
| App Service Plan      | WS1 ~€130/mo      | WS1 ~€130/mo | WS1 + S1 ~€235/mo   |
| Storage Account       | ~€1/mo            | ~€1/mo       | ~€1/mo              |
| Log Analytics         | ~€2/mo            | ~€2/mo       | ~€2/mo              |
| Virtual Network       | —                 | —            | ~€6/mo              |
| Private Endpoint      | —                 | —            | ~€0.50/mo           |
| APIM Developer        | —                 | ~€45/mo      | —                   |
| **Total**             | **~€133/mo**      | **~€178/mo** | **~€245/mo**        |

> ⚠️ **Lab 3 shares the same resource group as Lab 1** — enabling Lab 3 adds Function App and networking costs on top of Lab 1.
> ⚠️ Delete resources after testing to avoid ongoing charges.
