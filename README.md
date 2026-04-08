# Logic App Standard — Security Labs

## Purpose

Two complementary Azure labs to validate different security patterns for Logic App Standard HTTP triggers:

1. **Lab 1 — Easy Auth** (`rg-la-easyauth-lab-dev`): Validates that Easy Auth can enforce Entra ID authentication **without breaking portal manageability** using the `AllowAnonymous` + `allowedPrincipals` pattern.
2. **Lab 2 — APIM-Centric** (`rg-la-easyauth-lab-apim-dev`): Demonstrates centralized JWT validation at API Management, with backend Logic Apps protected via network restrictions instead of Easy Auth.

> See [`docs/decision-guidance.md`](docs/decision-guidance.md) for a detailed comparison of when to use which pattern.

### References

- [Microsoft Learn — Secure Integration Workflows (Method 2: Easy Auth)](https://learn.microsoft.com/en-us/community/content/secure-integration-workflows-azure-logic-apps-api-management#method-2-security-using-easy-auth) — primary reference for Lab 1
- [azcloudsecurity.io — Logic App Standard Easy Auth](https://azcloudsecurity.io/posts/logic-app-standard-easy-auth/) — AllowAnonymous pattern analysis
- [Microsoft Learn — App Service Authentication Overview](https://learn.microsoft.com/en-us/azure/app-service/overview-authentication-authorization#considerations-for-using-built-in-authentication) — Easy Auth middleware architecture
- [Microsoft Learn — Secure Logic Apps with VNet and Private Endpoints](https://learn.microsoft.com/en-us/azure/logic-apps/secure-single-tenant-workflow-virtual-network-private-endpoint) — network isolation patterns

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
# Lab 1
az group delete --name rg-la-easyauth-lab-dev --yes --no-wait
# Lab 2
az group delete --name rg-la-easyauth-lab-apim-dev --yes --no-wait
```

## Cost Estimate

| Resource         | Lab 1 (Easy Auth) | Lab 2 (APIM) |
|------------------|-------------------|---------------|
| App Service Plan | WS1 ~€130/mo      | WS1 ~€130/mo  |
| Storage Account  | ~€1/mo            | ~€1/mo        |
| Log Analytics    | ~€2/mo            | ~€2/mo        |
| APIM Developer   | —                 | ~€45/mo       |
| **Total**        | **~€133/mo**      | **~€178/mo**  |

> ⚠️ Delete resources after testing to avoid ongoing charges.
