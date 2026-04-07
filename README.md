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
| A1 | View run history list | Return401      | Accessible | —      | ⏳      |
| A2 | View run details      | Return401      | Accessible | —      | ⏳      |
| A3 | View inputs/outputs   | Return401      | Visible    | —      | ⏳      |
| A4 | Re-run/Resubmit       | Return401      | Works      | —      | ⏳      |
| A5 | View run history list | AllowAnonymous | Accessible | —      | ⏳      |
| A6 | View run details      | AllowAnonymous | Accessible | —      | ⏳      |
| A7 | View inputs/outputs   | AllowAnonymous | Visible    | —      | ⏳      |
| A8 | Re-run/Resubmit       | AllowAnonymous | Works      | —      | ⏳      |

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

## Conclusions

> _To be completed after validation runs._

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
