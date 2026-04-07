# Findings Log — Logic App Standard Easy Auth Lab

## Metadata

- Lab version: 1.0
- Subscription: 6851693c-0b74-4462-8da8-cd498b088827
- Region: westeurope
- Date started: _(auto-filled on first run)_

## Observations

### Track A — Portal Manageability

| Timestamp | Scenario ID | Observation | Evidence |
|-----------|-------------|-------------|----------|
| 2025-07 | A1 | ⚠️ **Blocked** — Run history list relies on hostruntime data-plane endpoint. Easy Auth intercepts the request before it reaches the Logic App runtime. Returns "Unauthorized (You do not have permission to view this directory or page.)" | `az rest` against hostruntime path returns 401 |
| 2025-07 | A2 | ⚠️ **Blocked** — Run details use hostruntime path `/hostruntime/runtime/webhooks/workflow/api/management/workflows/{name}/runs/{runId}`. Easy Auth blocks this. | Same 401 pattern as A1 |
| 2025-07 | A3 | ⚠️ **Blocked** — Inputs/outputs retrieval proxied via hostruntime; blocked by Easy Auth. | Same 401 pattern as A1 |
| 2025-07 | A4 | ⚠️ **Blocked** — Re-run/Resubmit requires `listCallbackUrl` via hostruntime; Easy Auth blocks the POST. Error: "You do not have permission to view this directory or page." | `az rest --method POST --url ".../hostruntime/.../listCallbackUrl"` → 401 |
| 2025-07 | A5 | ✅ Accessible — AllowAnonymous does not block hostruntime endpoints. | Portal loads run history normally |
| 2025-07 | A6 | ✅ Accessible — AllowAnonymous mode. | Run details visible |
| 2025-07 | A7 | ✅ Visible — AllowAnonymous mode. | Inputs/outputs rendered |
| 2025-07 | A8 | ✅ Works — AllowAnonymous mode, re-run succeeds. | Callback URL retrieval succeeds |

#### Critical Finding: Easy Auth Return401 Blocks hostruntime Data-Plane

When `authsettingsV2` is configured with `unauthenticatedClientAction: Return401`, **all hostruntime-proxied management operations fail** with HTTP 401.

**Root cause**: Logic App Standard has two classes of endpoints:

| Endpoint Class | Path Pattern | Served By | Easy Auth Impact |
|----------------|-------------|-----------|-----------------|
| ARM control-plane | `management.azure.com/.../providers/Microsoft.Web/sites/...` | Azure Resource Manager | ✅ None — ARM authenticates via AAD token directly |
| Workflow entity (ARM) | `.../workflows/{name}`, `.../workflows/{name}/runs` | ARM provider | ✅ None — pure ARM operations |
| hostruntime data-plane | `.../hostruntime/runtime/webhooks/workflow/api/management/...` | **App host itself** | ❌ **Blocked** — Easy Auth intercepts before runtime |

Even when called through ARM (`management.azure.com`), operations like `listCallbackUrl` are **proxied to the app host** by the ARM provider. The ARM layer forwards the call to the Logic App's `/hostruntime/...` endpoint, and Easy Auth intercepts it there.

**Test matrix results**:

| Operation | Endpoint Type | Easy Auth Return401 | Easy Auth AllowAnonymous |
|-----------|--------------|--------------------|-----------------------|
| Get Logic App properties | ARM basic read | ✅ Works | ✅ Works |
| List workflows | ARM workflow entity | ✅ Works | ✅ Works |
| List workflow runs | ARM workflow entity | ✅ Works | ✅ Works |
| Get workflow run details | ARM workflow entity | ✅ Works | ✅ Works |
| listCallbackUrl | hostruntime (proxied via ARM) | ❌ **401 Unauthorized** | ✅ Works |
| Run history (portal) | hostruntime | ❌ **Blocked** | ✅ Works |
| Run inputs/outputs (portal) | hostruntime | ❌ **Blocked** | ✅ Works |
| Re-run/Resubmit (portal) | hostruntime | ❌ **Blocked** | ✅ Works |

**Error message observed**:
```
ERROR: Unauthorized(You do not have permission to view this directory or page.)
```

### Track B — Trigger Security

| Timestamp | Scenario ID | HTTP Status | Correlation ID | Notes |
|-----------|-------------|-------------|----------------|-------|
|           | B1          |             |                |       |
|           | B2          |             |                |       |
|           | B3          |             |                |       |
|           | B4          |             |                |       |
|           | B5          |             |                |       |
|           | B6          |             |                |       |
|           | B7          |             |                |       |

## Key Findings

1. **Easy Auth `Return401` blocks hostruntime management endpoints.** Logic App Standard serves its management API on `/hostruntime/runtime/webhooks/workflow/api/management/...` paths from the app host itself. Easy Auth sits in front of the host and rejects these calls with 401 before the Logic App runtime can process them.

2. **ARM-only operations are unaffected.** Pure ARM calls (get site properties, list workflows, list runs) go through `management.azure.com` and are authenticated by AAD independently of Easy Auth. These continue to work.

3. **Portal manageability is severely impacted.** The Azure portal relies on hostruntime endpoints for:
   - Run history listing
   - Run detail inspection (inputs, outputs, action results)
   - Callback URL retrieval (`listCallbackUrl`)
   - Re-run / Resubmit operations
   All of these fail when Easy Auth is Return401.

4. **The pattern is consistent**: any call that ARM proxies to the app host's `/hostruntime/...` path is blocked, regardless of whether the caller is the portal, `az rest`, or any other ARM-authenticated client.

5. **AllowAnonymous mode does not block hostruntime endpoints**, but it also does not enforce Entra authentication on HTTP triggers, making it unsuitable as a security control for inbound workflow invocations.

## Recommendations

### Mitigation 1 (Preferred): Excluded Paths in authsettingsV2

Configure `excludedPaths` in the `authsettingsV2` resource to exempt management endpoints from Easy Auth:

```json
{
  "properties": {
    "globalValidation": {
      "unauthenticatedClientAction": "Return401",
      "excludedPaths": [
        "/runtime/*",
        "/hostruntime/*"
      ]
    }
  }
}
```

| | |
|---|---|
| **Pros** | Surgical fix; API trigger routes still require Entra token; single resource change; no extra infrastructure |
| **Cons** | Excludes entire hostruntime path space; requires testing to confirm supported glob patterns; if Logic App serves other hostruntime paths that should be protected, additional path-level controls needed |

### Mitigation 2 (Recommended for production): Gateway-Fronted Auth (APIM / Application Gateway)

Do **not** enable Easy Auth on the Logic App host at all. Instead:
- Place APIM or Application Gateway in front of the Logic App
- Enforce Entra ID validation at the gateway (JWT validation policy)
- Use Private Endpoints so the Logic App is not reachable except via the gateway

```text
Client → APIM (Entra JWT validate) → Private Endpoint → Logic App Standard
                                                         (no Easy Auth)
```

| | |
|---|---|
| **Pros** | Clean separation of auth and runtime; no interference with portal/management; supports rate limiting, caching, transformation at gateway; production-proven pattern |
| **Cons** | Additional infrastructure cost (APIM or AppGW); more complex deployment; requires Private Endpoint + VNet integration |

### Mitigation 3: Use Logic App Native Auth (SAS + Managed Identity)

Rely on the built-in SAS-based callback URLs for security. For callers that must authenticate with Entra:
- Use APIM with Managed Identity to call the Logic App
- Or use `authentication` action within the workflow to validate tokens

| | |
|---|---|
| **Pros** | No Easy Auth needed; SAS URLs are already secure (time-limited, per-workflow); no portal impact |
| **Cons** | SAS is not Entra-based; key rotation management; does not satisfy "Entra-only" compliance requirements without additional controls |

### Mitigation 4: Temporary Disable (Emergency Break-Glass Only)

Switch Easy Auth to `AllowAnonymous` or disable it entirely when portal access is needed.

| | |
|---|---|
| **Pros** | Immediate unblock |
| **Cons** | Removes authentication on HTTP triggers; not suitable for production; manual toggling is error-prone and not auditable |

### Architecture Recommendation

For production workloads, **Mitigation 2 (APIM-fronted)** is recommended. It provides:
- Entra ID enforcement without Easy Auth interference
- Full portal manageability retained
- Network-level isolation via Private Endpoints
- Centralized API governance

For dev/test or quick proof-of-concept, **Mitigation 1 (excludedPaths)** is the fastest path to unblock portal access while keeping Easy Auth active on API trigger routes.

## Appendix

- Screenshots: `docs/evidence/screenshots/`
- Raw API responses: `docs/evidence/api-responses/`
