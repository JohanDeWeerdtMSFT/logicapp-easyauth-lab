# Decision Guidance: Easy Auth Lab and APIM-Based Lab Working Side by Side

## Purpose

This document explains **why two different security labs exist** in this repository and how they should be used **together** to support customer decision-making.

The goal is **not** to force a single "correct" pattern, but to:

- Explain trade-offs clearly
- Align architecture choices with customer constraints
- Avoid accidental misconfiguration by mixing patterns unintentionally

---

## Why There Are Two Labs

Azure Logic Apps Standard can be secured in multiple valid ways.

Each approach optimizes for **different priorities**, such as:

- Identity strictness
- Operational simplicity
- Network scalability
- Platform manageability

Because no single pattern optimizes for all of these at once, this repository intentionally contains **two complementary labs**.

---

## Lab 1: Easy Auth on the Logic App Host

**Resource Group**: `{resourceGroupName}`

### What This Lab Demonstrates

- Entra ID authentication enforced directly on the Logic App via `authsettingsV2`
- The **AllowAnonymous + allowedPrincipals** pattern (from [azcloudsecurity.io](https://azcloudsecurity.io/posts/logic-app-standard-easy-auth/)):
  - `unauthenticatedClientAction: AllowAnonymous` — preserves portal manageability
  - Requests **with** an Authorization header are still validated against Entra requirements
  - Only the APIM managed identity is allowed via `allowedPrincipals`
  - `platform.enabled: true` and `runtimeVersion: ~1` are required (underdocumented)
- Strong app-level identity validation
- SAS keys remain available as a fallback trigger mechanism

### What This Lab Optimizes For

- Strict identity enforcement at the application boundary
- Defense-in-depth (gateway + app host)
- Clear "only this identity may call this app" semantics
- Preserved portal manageability (unlike `Return401`)

### What This Lab Requires Careful Handling

- Configuration must follow the exact pattern — `Return401` breaks portal management
- `platform.enabled: true` and `runtimeVersion: ~1` are mandatory but underdocumented
- `WEBSITE_AUTH_AAD_ALLOWED_TENANTS` environment variable needed for tenant restriction
- SAS keys remain active alongside Entra auth — consider this in your threat model

### Key Finding: Return401 vs AllowAnonymous

Our initial lab testing with `Return401` confirmed that Easy Auth blocks all `/hostruntime/*` data-plane endpoints, breaking portal manageability (scenarios A1–A4). This is now confirmed by **multiple official and community references**:

> **Microsoft Learn** ([Method 2 — Easy Auth](https://learn.microsoft.com/en-us/community/content/secure-integration-workflows-azure-logic-apps-api-management#method-2-security-using-easy-auth)): *"When `unauthenticatedClientAction` is set to `AllowAnonymous`, all successful and failed calls are routed to the Azure Logic Apps runtime. If a request fails Easy Auth with `Return401`, the request doesn't get routed to the Azure Logic Apps runtime and fails with the 401 error from Azure App Service. With this error, you also get a broken Azure portal experience."*

> **azcloudsecurity.io** ([Excuse me, allow unauthenticated requests???](https://azcloudsecurity.io/posts/logic-app-standard-easy-auth/#excuse-me-allow-unauthenticated-requests)): *"It turns out that this setting is required if you want to manage Logic App workflows through the Azure Portal."*

The solution is `AllowAnonymous` combined with SAS-disable:

| Configuration | Portal Works | Token Enforced | SAS Still Works |
|---|---|---|---|
| `Return401` | ❌ | ✅ | ✅ |
| `AllowAnonymous` (default) | ✅ | ⚠️ Only when token present | ✅ |
| **`AllowAnonymous` + `allowedPrincipals`** | **✅** | **✅** | **✅** |

This lab is valuable for understanding **how to configure Easy Auth correctly for Logic Apps Standard**.

---

## Lab 2: API Management–Centric Security (No Easy Auth on Host)

**Resource Group**: `rg-la-easyauth-lab-apim-dev`

### What This Lab Demonstrates

- Centralized authentication and authorization at API Management via `validate-jwt` policy
- Logic Apps remain runtime-native (no Easy Auth configured)
- Backend apps protected using network access restrictions
- Reduced reliance on per-app Private Endpoints

### What This Lab Optimizes For

- Platform scalability (many Logic Apps / Function Apps behind one APIM)
- Reduced IP address consumption (1 APIM vs N Private Endpoints)
- Preserved Azure Portal visibility and diagnostics
- Simpler operational model at scale

### What This Lab Trades Off

- Identity enforcement is centralized, not duplicated at app level
- Backend relies on gateway trust and network controls
- Defense-in-depth is achieved differently (network + gateway, not app-level auth)

> Some references combine API Management and Easy Auth for defense‑in‑depth identity enforcement. While valid, enabling Easy Auth on Logic Apps Standard can introduce operational complexity and runtime manageability risks. This lab demonstrates an alternative pattern where API Management enforces identity centrally, and backend Logic Apps are protected using network-level access restrictions, reducing the need for per-app Private Endpoints and preserving portal functionality.

This lab is valuable for **platform and integration landscapes**, not single apps.

## Alternative Approaches for Lab 1

### Option A: AllowAnonymous + allowedPrincipals (current implementation)

This is the pattern validated in Lab 1 and recommended by [Microsoft Learn](https://learn.microsoft.com/en-us/community/content/secure-integration-workflows-azure-logic-apps-api-management#method-2-security-using-easy-auth) and [azcloudsecurity.io](https://azcloudsecurity.io/posts/logic-app-standard-easy-auth/).

| Aspect | Behavior |
|---|---|
| Portal management | ✅ Works — unauthenticated management requests pass through |
| Token enforcement | ✅ Requests with Authorization header validated by Easy Auth |
| SAS keys | Active — can be used to trigger workflows without Entra token |
| Strictness | Medium — unauthenticated requests without tokens reach runtime |

### Option B: Return401 + excludedPaths (alternative — to be tested)

An alternative approach keeps `Return401` for maximum strictness but exempts management endpoints via `excludedPaths`:

```json
{
  "globalValidation": {
    "unauthenticatedClientAction": "Return401",
    "excludedPaths": [
      "/runtime/*",
      "/hostruntime/*"
    ]
  }
}
```

| Aspect | Behavior |
|---|---|
| Portal management | ✅ Expected to work — excluded paths bypass Easy Auth |
| Token enforcement | ✅ Stricter — ALL requests to non-excluded paths require Entra token |
| SAS keys | Blocked for non-excluded paths — only Entra tokens accepted |
| Strictness | High — but excluded paths lose Easy Auth protection |

**Trade-offs**:
- **Pro**: Stricter than AllowAnonymous — even requests without Authorization header are rejected (except on excluded paths)
- **Pro**: SAS key bypass is effectively blocked on Easy Auth–protected paths
- **Con**: Excluded paths (`/runtime/*`, `/hostruntime/*`) are unprotected by Easy Auth — they rely on ARM/SAS token security
- **Con**: Requires testing to confirm supported glob patterns and which paths need excluding
- **Con**: If Logic App serves other hostruntime paths that should be protected, additional path-level controls are needed

**Status**: Not yet validated. Planned for future testing.

---

| Dimension | Lab 1 (Easy Auth) | Lab 2 (APIM) |
|---|---|---|
| **Auth enforcement location** | App host (Easy Auth middleware) | API Management gateway |
| **Auth mechanism** | `authsettingsV2` + `AllowAnonymous` + SAS disable | `validate-jwt` APIM policy |
| **Portal manageability** | ✅ (with AllowAnonymous) | ✅ (no Easy Auth) |
| **Token validation** | At app host for requests with Authorization header | At APIM before reaching backend |
| **SAS key handling** | SAS keys remain active alongside Entra auth | N/A (no SAS exposure — access restricted) |
| **Network isolation** | Optional (can add Private Endpoints) | Recommended (access restrictions on backend) |
| **IP address consumption** | 1 Private Endpoint per app | 1 APIM instance for N apps |
| **Configuration complexity** | Medium (per-app authsettingsV2 + SAS disable + env vars) | Lower per-app (centralized at APIM) |
| **Scale suitability** | ✅ Small number of apps | ✅ Hundreds of apps |
| **Defense-in-depth** | App-level + optional gateway | Gateway + network-level |
| **Operational risk** | Medium (Easy Auth gotchas on Logic Apps) | Low (standard APIM pattern) |
| **Cost (lab)** | ~€133/month (WS1 + storage) | ~€180/month (WS1 + storage + APIM Developer) |

---

## Why Some References Combine APIM and Easy Auth

Some external references intentionally use **both APIM and Easy Auth** to achieve:

- Maximum identity strictness
- Explicit prevention of backend bypass
- Strong defense-in-depth

However, this comes with:

- Increased configuration complexity
- Higher operational risk for Logic Apps Standard (Easy Auth gotchas)
- Greater sensitivity to platform changes

Those references are **not wrong** — they simply optimize for a different set of constraints.

---

## How to Use Both Labs with a Customer

When discussing architecture with a customer:

1. **Walk through both labs conceptually** — explain what each optimizes for
2. **Ask which constraints matter most**:
   - Identity strictness vs operational simplicity?
   - Small number of apps vs hundreds?
   - IP address availability a concern?
   - Portal manageability critical?
3. **Explain the trade-offs explicitly** using the comparison table above
4. **Decide whether**:
   - Lab 1 fits best (few apps, max identity strictness)
   - Lab 2 fits best (many apps, centralized governance)
   - Or elements of both are required, consciously and carefully

The labs are **conversation tools**, not prescriptions.

---

## Validation Tracks

### Lab 1 Tracks

| Track | Purpose | Key Scenarios |
|---|---|---|
| **Track A** | Portal manageability with AllowAnonymous + SAS disable | A1–A4: run history, details, I/O, re-run |
| **Track B** | Trigger security despite AllowAnonymous | B1–B7: valid token, invalid, wrong aud, no token, SAS bypass |

### Lab 2 Tracks

| Track | Purpose | Key Scenarios |
|---|---|---|
| **Track C** | APIM JWT validation | C1–C4: valid/invalid/missing/wrong-audience token |
| **Track D** | Backend isolation | D1: direct call blocked, D2: APIM-only access confirmed |
| **Track E** | Portal manageability (no Easy Auth) | E1–E4: run history, details, I/O, re-run |

---

## Key Message for Customers

There is no single "best" pattern.

There are:

- Different security layers
- Different operational costs
- Different scaling implications

The right design is the one that aligns with the customer's **risk tolerance, scale, and operational model**.

---

## Recommendation for This Repository

- Keep both labs maintained and documented
- Avoid merging them implicitly
- Use this guidance to explain *why* both exist
- Let customers make informed decisions, not forced ones

---

## References

- [Microsoft Learn — Secure Integration Workflows with Azure Logic Apps and API Management](https://learn.microsoft.com/en-us/community/content/secure-integration-workflows-azure-logic-apps-api-management) — **primary reference**: Method 1 (SAS) and Method 2 (Easy Auth) patterns with full Bicep examples
- [azcloudsecurity.io — Logic App Standard Easy Auth](https://azcloudsecurity.io/posts/logic-app-standard-easy-auth/) — detailed analysis of AllowAnonymous pattern, platform.enabled gotcha, SAS disable option
- [Microsoft Learn — App Service Authentication Overview](https://learn.microsoft.com/en-us/azure/app-service/overview-authentication-authorization#considerations-for-using-built-in-authentication) — Easy Auth middleware architecture and authorization behavior
- [Microsoft Learn — Secure Logic Apps with VNet and Private Endpoints](https://learn.microsoft.com/en-us/azure/logic-apps/secure-single-tenant-workflow-virtual-network-private-endpoint) — private endpoint and VNet integration setup
- [Microsoft AIS Blog — Trigger Workflows with Easy Auth](https://techcommunity.microsoft.com/blog/integrationsonazureblog/trigger-workflows-in-standard-logic-apps-with-easy-auth/3207378) — original Microsoft guidance on AllowAnonymous requirement
- [GitHub Issue #1114](https://github.com/Azure/logicapps/issues/1114) — managed identity storage support tracking
- Lab 1 findings: [`docs/evidence/findings.md`](evidence/findings.md)
- Lab 2 plan: [`docs/apim-lab-plan.md`](apim-lab-plan.md)
