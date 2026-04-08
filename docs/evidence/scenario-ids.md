# Scenario ID Reference

This file is the single source of truth for scenario IDs used across all lanes.

## Track A — Portal Manageability (Lab 1)

- **A1**: View run history list (Return401 → 🔴 Blocked; AllowAnonymous → ✅)
- **A2**: View run details (Return401 → 🔴 Blocked; AllowAnonymous → ✅)
- **A3**: View inputs/outputs (Return401 → 🔴 Blocked; AllowAnonymous → ✅)
- **A4**: Re-run/Resubmit (Return401 → 🔴 Blocked; AllowAnonymous → ✅)

## Track B — Trigger Security (Lab 1 — AllowAnonymous + allowedPrincipals)

- **B1**: Valid mgmt token (user identity) → 403 (not in allowedPrincipals) ✅
- **B2**: Invalid/expired token → 401 ✅
- **B3**: Wrong audience token (Graph) → 401 ✅
- **B4**: No token, no SAS key → 401 ✅
- **B5**: No token + SAS key → 200 (SAS remains active) ✅

## Track C — APIM JWT Validation (Lab 2)

- **C1**: Valid Entra token through APIM → expect 200 (⏳ requires APIM MI token)
- **C2**: Invalid token through APIM → 401 ✅
- **C3**: No token through APIM → 401 ✅
- **C4**: Wrong audience through APIM → expect 401 (⏳)

## Track D — Backend Isolation (Lab 2)

- **D1**: Direct call to Logic App (bypass APIM) → 401 (access restriction) ✅
- **D2**: APIM managed identity to backend → expect 200 (⏳ requires MI auth policy)

## Track E — Portal Manageability (Lab 2 — No Easy Auth)

- **E1**: List workflow runs (hostruntime) → 200 ✅
- **E2**: listCallbackUrl (hostruntime) → 200 ✅
- **E3**: View inputs/outputs → ✅ (confirmed via portal)
- **E4**: Re-run/Resubmit → ✅ (confirmed via portal)

## Endpoint Classification

Logic App Standard operations use two distinct endpoint classes. This classification determines whether Easy Auth (`Return401`) blocks the operation.

### ARM-Only Operations (✅ Work with Easy Auth)

These operations are served entirely by the Azure Resource Manager and **do not** pass through the app host. Easy Auth has no impact.

| Scenario ID | Operation | ARM Path |
|-------------|-----------|----------|
| _(infra)_ | Get Logic App properties | `Microsoft.Web/sites/{name}` |
| _(infra)_ | List workflows | `Microsoft.Web/sites/{name}/workflows` |
| _(partial)_ | List workflow runs | `Microsoft.Web/sites/{name}/workflows/{wf}/runs` |
| _(partial)_ | Get workflow run | `Microsoft.Web/sites/{name}/workflows/{wf}/runs/{id}` |

> **Note**: While some run-level ARM queries succeed, the portal combines them with hostruntime calls for full detail rendering. A successful ARM run-list does not mean the portal can display full run details.

### hostruntime Data-Plane Operations (❌ Blocked by Easy Auth Return401)

These operations are **served by the app host itself** on `/hostruntime/runtime/webhooks/workflow/api/management/...` paths. Even when invoked via ARM (`management.azure.com`), the ARM provider proxies the call to the app host, where Easy Auth intercepts it.

| Scenario ID | Operation | Why Blocked |
|-------------|-----------|-------------|
| **A1** | View run history list | Portal fetches run history via hostruntime for enriched data (trigger info, action counts) |
| **A2** | View run details | Run detail view loads action statuses, durations, and error info via hostruntime |
| **A3** | View inputs/outputs | Input/output payloads are retrieved via hostruntime content links |
| **A4** | Re-run/Resubmit | Requires `listCallbackUrl` which is a POST to a hostruntime path |
| **B1** | Valid token trigger call | HTTP trigger endpoint is served by the app host; Easy Auth validates the token at this layer |
| **B4** | No token trigger call | HTTP trigger call with no token — Easy Auth returns 401 (expected/correct behavior) |

### AllowAnonymous Operations (✅ Work, but no auth enforcement)

| Scenario ID | Operation | Note |
|-------------|-----------|------|
| **A5–A8** | All portal management ops | AllowAnonymous does not intercept hostruntime; portal works fully |
| **B5** | No token trigger call | AllowAnonymous passes request through to runtime without auth check |

### Summary

```text
Easy Auth Return401 impact by endpoint class:

  ARM control-plane ──────────► ✅ Unaffected (AAD auth handled by ARM)
  ARM workflow entities ───────► ✅ Unaffected (pure ARM operations)
  hostruntime data-plane ──────► ❌ BLOCKED (Easy Auth intercepts at app host)
  HTTP trigger endpoints ──────► ✅ Protected (Easy Auth enforces Entra — intended)
```
