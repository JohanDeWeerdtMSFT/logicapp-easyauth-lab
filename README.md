# Logic App Standard — Easy Auth Lab

## Purpose

Reproducible Azure lab to validate the impact of enabling Easy Auth (Authentication/Authorization via `authsettingsV2`) on Logic App Standard, specifically:

1. **Track A — Portal Manageability**: Does enabling Easy Auth break the Azure portal experience for managing Logic App workflows (run history, run details, inputs/outputs visibility, re-run/resubmit)?
2. **Track B — Trigger Security**: Does Easy Auth correctly enforce authentication on HTTP-triggered workflows?

## Architecture

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
│                    │ │ (HTTP GET trigger) │  │     │
│                    │ └────────────────────┘  │     │
│                    │                          │     │
│                    │ authsettingsV2:          │     │
│                    │ ├─ Mode X: Return401     │     │
│                    │ └─ Mode Y: AllowAnonymous│     │
│                    └────────────────────────┘     │
│                                                   │
│  ┌────────────────┐  ┌───────────────────┐       │
│  │ Storage Account│  │ App Insights      │       │
│  │ (for workflow  │  │ + Log Analytics   │       │
│  │  state)        │  └───────────────────┘       │
│  └────────────────┘                               │
│                                                   │
│  ┌────────────────────────┐ (optional, Lane D)   │
│  │ Function App comparison│                       │
│  └────────────────────────┘                       │
└─────────────────────────────────────────────────┘
```

## Prerequisites

- Azure subscription with Contributor access
- Azure CLI installed and logged in
- Entra ID App Registration (for Easy Auth)
  - Redirect URI: `https://<logicapp-hostname>/.auth/login/aad/callback`
  - Client secret created
  - API permission: none required (we use client\_credentials flow)

## Quick Start

1. Register an Entra ID application
2. Deploy: `.\scripts\deploy.ps1 -EntraAppClientId <clientId> -EntraAppTenantId <tenantId>`
3. Validate: `.\scripts\validate.ps1 -LogicAppName <name> -ResourceGroupName <rg> -EntraAppClientId <clientId> -EntraAppTenantId <tenantId> -ClientSecret <secret>`

## Scenario Matrix

### Track A — Portal Manageability

| ID | Scenario              | Easy Auth Mode | Expected   | Actual | Status |
|----|-----------------------|----------------|------------|--------|--------|
| A1 | View run history list | Return401      | ⚠️ Blocked by Easy Auth | 401 — hostruntime blocked | 🔴      |
| A2 | View run details      | Return401      | ⚠️ Blocked by Easy Auth | 401 — hostruntime blocked | 🔴      |
| A3 | View inputs/outputs   | Return401      | ⚠️ Blocked by Easy Auth | 401 — hostruntime blocked | 🔴      |
| A4 | Re-run/Resubmit       | Return401      | ⚠️ Blocked by Easy Auth | 401 — hostruntime blocked | 🔴      |
| A5 | View run history list | AllowAnonymous | Accessible | Accessible | ✅      |
| A6 | View run details      | AllowAnonymous | Accessible | Accessible | ✅      |
| A7 | View inputs/outputs   | AllowAnonymous | Visible    | Visible    | ✅      |
| A8 | Re-run/Resubmit       | AllowAnonymous | Works      | Works      | ✅      |

### Track B — Trigger Security

| ID | Scenario                   | Easy Auth Mode | Token                      | Expected HTTP | Actual HTTP | Correlation ID | Status |
|----|----------------------------|----------------|----------------------------|---------------|-------------|----------------|--------|
| B1 | Valid token                | Return401      | Valid bearer                | 200           | —           | —              | ⏳      |
| B2 | Invalid token              | Return401      | Expired/malformed           | 401           | —           | —              | ⏳      |
| B3 | Wrong audience             | Return401      | Valid, wrong aud            | 401           | —           | —              | ⏳      |
| B4 | No token                   | Return401      | None                        | 401           | —           | —              | ⏳      |
| B5 | No token                   | AllowAnonymous | None                        | 200           | —           | —              | ⏳      |
| B6 | Valid token + SAS disabled | Return401      | Valid bearer, no SAS key    | 200           | —           | —              | ⏳      |
| B7 | No token + SAS only        | Return401      | None, SAS key only          | 401           | —           | —              | ⏳      |

## Findings Log

See [`docs/evidence/findings.md`](docs/evidence/findings.md) for detailed observations.

## Key Findings

> **Critical: Easy Auth `Return401` blocks Logic App Standard management endpoints.**

1. **hostruntime endpoints are blocked.** When `authsettingsV2` is set to `unauthenticatedClientAction: Return401`, Easy Auth intercepts all `/hostruntime/...` data-plane requests before the Logic App runtime can process them. These paths serve the management API that the portal, `az rest`, and ARM-proxied operations depend on. Error: `"Unauthorized (You do not have permission to view this directory or page.)"`

2. **Portal manageability is impacted.** Run history, run details, inputs/outputs, callback URLs, and re-run/resubmit all rely on hostruntime endpoints. With Return401 enabled, the portal loses visibility into workflow execution state (scenarios A1–A4 all blocked).

3. **ARM-only operations are unaffected.** Pure ARM reads (get site properties, list workflows, list runs) bypass the app host and continue working regardless of Easy Auth mode.

4. **Mitigation options:**
   - **Quick fix**: Add `excludedPaths: ["/runtime/*", "/hostruntime/*"]` to `authsettingsV2.globalValidation` — unblocks management while keeping Easy Auth on API routes
   - **Production recommendation**: APIM or Application Gateway fronting the Logic App with Entra JWT validation at the gateway, Private Endpoints for network isolation, and no Easy Auth on the Logic App host itself

## Recommended Architecture

For production workloads requiring Entra ID enforcement on Logic App Standard HTTP triggers:

```text
                          ┌──────────────────────────┐
                          │  Azure API Management     │
  Client ───── Entra ────▶│  - JWT validation policy  │
  (bearer token)          │  - Rate limiting           │
                          │  - Logging                 │
                          └──────────┬───────────────┘
                                     │ Private Endpoint
                          ┌──────────▼───────────────┐
                          │  Logic App Standard       │
                          │  (NO Easy Auth)           │
                          │  ┌────────────────────┐  │
                          │  │ httpTriggerWorkflow│  │
                          │  └────────────────────┘  │
                          │                           │
                          │  Portal access: ✅ Full   │
                          │  Management APIs: ✅ Full │
                          └───────────────────────────┘
```

**Why this works**: Entra authentication is enforced at the APIM gateway layer (via `validate-jwt` policy). The Logic App itself has no Easy Auth configured, so portal and ARM management operations work without interference. The Private Endpoint ensures the Logic App is not publicly reachable except through APIM.

## Conclusions

**Easy Auth (`authsettingsV2` with `Return401`) is not compatible with Logic App Standard portal manageability.** The Easy Auth middleware sits in front of the app host and intercepts hostruntime data-plane endpoints that the Azure portal, ARM-proxied operations, and tooling depend on for workflow management.

**Recommendation**: Do not use Easy Auth directly on Logic App Standard for Entra-based trigger security. Instead, use a **gateway-fronted architecture** (APIM with `validate-jwt` policy + Private Endpoints) to enforce Entra ID authentication while preserving full portal and management API access. For dev/test scenarios, `excludedPaths` in `authsettingsV2` provides a quick workaround.

See [`docs/evidence/findings.md`](docs/evidence/findings.md) for full analysis, test matrix, and mitigation details.

## Teardown

```powershell
az group delete --name rg-la-easyauth-lab-dev --yes --no-wait
```

## Cost Estimate

| Resource         | SKU            | Est. Monthly Cost |
|------------------|----------------|-------------------|
| App Service Plan | WS1            | ~€130/month       |
| Storage Account  | Standard\_LRS  | ~€1/month         |
| Log Analytics    | Pay-as-you-go  | ~€2/month         |
| **Total**        |                | **~€133/month**   |

> ⚠️ Delete resources after testing to avoid ongoing charges.
