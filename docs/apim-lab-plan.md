# APIM Lab — Centralized Authentication for Logic Apps & Function Apps at Scale

## Document Info

| Field | Value |
|-------|-------|
| Lab | APIM Centralized Auth |
| Companion lab | [Easy Auth Lab](../README.md) |
| Status | Planning |
| Region | West Europe (primary), Sweden Central (fallback) |
| Last updated | 2025-07 |

---

## 1. Lab Purpose

### Problem Statement

The [Easy Auth lab](../README.md) proved that enabling `authsettingsV2` with `Return401` on Logic App Standard **breaks portal manageability** — run history, callback URLs, inputs/outputs, and re-run/resubmit all fail because Easy Auth intercepts `/hostruntime/*` data-plane requests before the runtime processes them.

The customer operates **hundreds of Logic Apps and Function Apps** and faces four compounding concerns:

1. **Easy Auth breaks portal visibility** — every app with `Return401` loses management operations (see findings: scenarios A1–A4).
2. **Private Endpoint per app exhausts IP address space** — each Private Endpoint consumes a `/32` from the VNet subnet. At 200 apps, that is 200 IPs just for PE NICs.
3. **Duplicated authentication logic** — each app carries its own `authsettingsV2` config, Entra app registration, and `excludedPaths` workarounds. Configuration drift at scale is inevitable.
4. **Networking cost and subnet sizing** — per-app Private Endpoints require oversized subnets, additional DNS zones, and more NSG rules.

### Lab Objective

Deploy an **APIM-fronted architecture** that:

- Centralizes Entra ID JWT validation at the API Management gateway layer
- Eliminates the need for Easy Auth on individual app hosts
- Preserves full portal and management API access to Logic Apps / Function Apps
- Reduces IP address consumption from _N_ (one per app) to a small fixed number
- Provides a **side-by-side comparison** with the Easy Auth lab results

### Success Criteria

| # | Criterion | Measurement |
|---|-----------|-------------|
| 1 | Portal run history works | A1–A4 scenarios pass (no 401 on hostruntime) |
| 2 | Valid Entra token → 200 through APIM | curl with bearer token returns 200 |
| 3 | Missing/invalid token → 401 at APIM | APIM rejects before reaching Logic App |
| 4 | Logic App is unreachable directly | Access restrictions block non-APIM traffic |
| 5 | IP consumption documented | Comparison table populated for 10–200 apps |

---

## 2. Architecture

### Scenario 1 — Regional Private (App Gateway + APIM Internal)

Best for single-region deployments where all consumers are within the corporate network or connected via ExpressRoute/VPN.

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│  Azure Region: West Europe                                                   │
│                                                                              │
│  ┌─────────────────┐     ┌──────────────────────────┐                       │
│  │  Client          │     │  Application Gateway     │                       │
│  │  (browser / app) │────▶│  WAF v2                  │                       │
│  │                  │     │  ┌────────────────────┐  │                       │
│  └─────────────────┘     │  │ WAF policy          │  │                       │
│                           │  │ (OWASP 3.2)        │  │                       │
│                           │  └────────────────────┘  │                       │
│                           └──────────┬───────────────┘                       │
│                                      │ Private IP (VNet)                     │
│                           ┌──────────▼───────────────┐                       │
│                           │  API Management           │                       │
│                           │  (Internal VNet mode)     │                       │
│                           │                           │                       │
│                           │  ┌────────────────────┐  │                       │
│                           │  │ validate-jwt policy │  │                       │
│                           │  │ • aud = {client_id} │  │                       │
│                           │  │ • iss = tenant       │  │                       │
│                           │  │ • exp check          │  │                       │
│                           │  └────────────────────┘  │                       │
│                           │                           │                       │
│                           │  APIs:                    │                       │
│                           │  ├─ logic-app-orders      │                       │
│                           │  ├─ logic-app-invoices    │                       │
│                           │  └─ func-app-notify       │                       │
│                           └──────────┬───────────────┘                       │
│                                      │ APIM subnet                           │
│                           ┌──────────▼───────────────┐                       │
│                           │  Logic Apps / Function    │                       │
│                           │  Apps (multiple)          │                       │
│                           │                           │                       │
│                           │  ┌────────────────────┐  │                       │
│                           │  │ Access Restrictions │  │                       │
│                           │  │ Allow: APIM subnet  │  │                       │
│                           │  │ Deny:  all others   │  │                       │
│                           │  └────────────────────┘  │                       │
│                           │                           │                       │
│                           │  Easy Auth: NOT enabled   │                       │
│                           │  Portal access: ✅ Full   │                       │
│                           │  hostruntime:   ✅ Works  │                       │
│                           └───────────────────────────┘                       │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

**Flow**:
1. Client sends request with Entra ID bearer token to Application Gateway public IP.
2. App Gateway WAF inspects for OWASP threats, forwards to APIM backend pool.
3. APIM `validate-jwt` inbound policy validates the token (audience, issuer, expiry, signature).
4. If valid, APIM forwards to the Logic App / Function App backend.
5. Logic App has **no Easy Auth** — accepts the request, runs the workflow.
6. Access restrictions on the Logic App ensure only traffic from the APIM subnet is accepted; direct calls are rejected.

### Scenario 2 — Global (Front Door Premium + APIM)

Best for multi-region or global deployments where consumers are geographically distributed.

```text
┌─────────────────────────────────────────────────────────────────────────┐
│  Global                                                                  │
│                                                                          │
│  ┌─────────────────┐     ┌──────────────────────────┐                   │
│  │  Client          │     │  Azure Front Door        │                   │
│  │  (global users)  │────▶│  Premium                 │                   │
│  │                  │     │  ┌────────────────────┐  │                   │
│  └─────────────────┘     │  │ WAF policy          │  │                   │
│                           │  │ (managed rules)    │  │                   │
│                           │  └────────────────────┘  │                   │
│                           └──────────┬───────────────┘                   │
│                                      │ Private Link                      │
│                                      │                                   │
│  ┌───────────────────────────────────▼───────────────────────────────┐   │
│  │  Azure Region: West Europe                                        │   │
│  │                                                                    │   │
│  │  ┌──────────────────────────┐                                     │   │
│  │  │  API Management           │                                     │   │
│  │  │  (Internal or External)   │                                     │   │
│  │  │                           │                                     │   │
│  │  │  ┌────────────────────┐  │                                     │   │
│  │  │  │ validate-jwt policy │  │                                     │   │
│  │  │  └────────────────────┘  │                                     │   │
│  │  │                           │                                     │   │
│  │  └──────────┬───────────────┘                                     │   │
│  │             │                                                      │   │
│  │  ┌──────────▼───────────────┐                                     │   │
│  │  │  Logic Apps / Functions   │                                     │   │
│  │  │  (access-restricted)      │                                     │   │
│  │  │  Easy Auth: NOT enabled   │                                     │   │
│  │  └───────────────────────────┘                                     │   │
│  │                                                                    │   │
│  └────────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

**Flow**:
1. Client connects to Front Door Premium global endpoint.
2. Front Door WAF applies managed rules, then routes via Private Link to APIM.
3. APIM validates JWT and forwards to backend Logic App / Function App.
4. Access restrictions on apps allow only APIM subnet traffic.

### Lab Scope (Simplified for Developer SKU)

For this lab, we deploy the **minimal reproducible version** of Scenario 1 without Application Gateway:

```text
  Client (curl / Postman)
       │
       │  Entra bearer token
       ▼
  ┌──────────────────────────┐
  │  APIM (Developer SKU)    │
  │  External VNet mode      │
  │  validate-jwt policy     │
  └──────────┬───────────────┘
             │
  ┌──────────▼───────────────┐
  │  Logic App Standard      │
  │  (same as Easy Auth lab) │
  │  NO authsettingsV2       │
  │  Access restrictions:    │
  │   allow APIM subnet only │
  └───────────────────────────┘
```

This is sufficient to prove:
- JWT validation works at the APIM layer
- Portal/hostruntime endpoints remain accessible
- Direct access to the Logic App is blocked

---

## 3. Bicep Modules Needed

### New Modules

| Module | Path | Purpose | Key Parameters |
|--------|------|---------|----------------|
| APIM Instance | `infra/modules/apim.bicep` | Deploy APIM Developer SKU with VNet integration | `sku`, `subnetId`, `publisherEmail`, `publisherName` |
| APIM API Definition | `infra/modules/apim-api.bicep` | Define API operations pointing to Logic App backend | `apiName`, `logicAppHostname`, `policyXml` |
| Access Restrictions | `infra/modules/access-restrictions.bicep` | Lock down Logic App to accept traffic only from APIM subnet | `appName`, `allowedSubnetId`, `priority` |

### Existing Modules (Reused from Easy Auth Lab)

| Module | Path | Modification |
|--------|------|-------------- |
| Foundation | `infra/modules/foundation.bicep` | Add APIM subnet to VNet (if VNet exists), or add VNet |
| Logic App | `infra/modules/logicapp.bicep` | Deploy **without** Easy Auth; reuse as-is with `easyAuthEnabled: false` |
| Easy Auth | `infra/modules/easyauth.bicep` | **Not used** in APIM lab — this is the point |

### Module Dependency Graph

```text
foundation.bicep
  ├─▶ logicapp.bicep (no Easy Auth)
  ├─▶ apim.bicep (needs VNet/subnet from foundation)
  │     └─▶ apim-api.bicep (needs APIM instance + Logic App hostname)
  └─▶ access-restrictions.bicep (needs Logic App + APIM subnet ID)
```

### Parameter File

A new parameter file `infra/params/apim-lab-dev.bicepparam` will provide:

```
param location = 'westeurope'
param environmentName = 'apim-lab-dev'
param apimSku = 'Developer'
param apimPublisherEmail = 'lab@contoso.com'
param apimPublisherName = 'ORES Lab'
param entraAppClientId = '<from-easyauth-lab-registration>'
param entraAppTenantId = '<tenant-id>'
param enableEasyAuth = false   // explicitly disabled
```

---

## 4. APIM JWT Validation Policy

### Inbound Policy — `validate-jwt`

This policy is applied at the API level in APIM. It validates Entra ID v2.0 tokens before forwarding to the Logic App backend.

```xml
<policies>
    <inbound>
        <base />

        <!-- Validate JWT from Entra ID -->
        <validate-jwt
            header-name="Authorization"
            failed-validation-httpcode="401"
            failed-validation-error-message="Unauthorized. A valid Entra ID bearer token is required."
            require-expiration-time="true"
            require-scheme="Bearer"
            require-signed-tokens="true"
            output-token-variable-name="jwt">

            <!-- Entra ID v2.0 OpenID Connect metadata -->
            <openid-config
                url="https://login.microsoftonline.com/{{tenant-id}}/v2.0/.well-known/openid-configuration" />

            <!-- Audience must match the app registration client ID -->
            <audiences>
                <audience>{{client-id}}</audience>
            </audiences>

            <!-- Issuer must be the customer's Entra tenant -->
            <issuers>
                <issuer>https://login.microsoftonline.com/{{tenant-id}}/v2.0</issuer>
                <!-- Include v1.0 issuer format for backward compatibility -->
                <issuer>https://sts.windows.net/{{tenant-id}}/</issuer>
            </issuers>

            <!-- Optional: require specific roles or scopes -->
            <!--
            <required-claims>
                <claim name="roles" match="any">
                    <value>LogicApp.Invoke</value>
                </claim>
            </required-claims>
            -->

        </validate-jwt>

        <!-- Forward caller identity to backend via headers -->
        <set-header name="X-Authenticated-User" exists-action="override">
            <value>@(context.Request.Headers.GetValueOrDefault("Authorization","").AsJwt()?.Subject)</value>
        </set-header>

    </inbound>

    <backend>
        <base />
    </backend>

    <outbound>
        <base />
    </outbound>

    <on-error>
        <base />
    </on-error>
</policies>
```

### Named Values Required

| Named Value | Value | Purpose |
|-------------|-------|---------|
| `tenant-id` | Customer's Entra tenant GUID | Issuer and OIDC metadata URL |
| `client-id` | Entra app registration client ID | Audience validation |

### What This Achieves

| Check | Handled By |
|-------|-----------|
| Token present in `Authorization` header | `header-name="Authorization"` |
| Token is a signed JWT | `require-signed-tokens="true"` |
| Token has not expired | `require-expiration-time="true"` |
| Token audience matches app | `<audiences>` |
| Token issuer is correct tenant | `<issuers>` |
| OIDC signing keys validated | `<openid-config>` (fetches JWKS automatically) |
| Invalid/missing token → 401 | `failed-validation-httpcode="401"` |

---

## 5. Validation Matrix — Side-by-Side Comparison

### Portal & Management Operations (Track A)

| # | Test | Easy Auth Lab (`Return401`) | APIM Lab (No Easy Auth on host) | Notes |
|---|------|----------------------------|--------------------------------|-------|
| A1 | View run history list | ❌ Blocked (401 on hostruntime) | ✅ Works | Easy Auth intercepts `/hostruntime/*`; APIM does not |
| A2 | View run details | ❌ Blocked | ✅ Works | Same root cause |
| A3 | View inputs/outputs | ❌ Blocked | ✅ Works | |
| A4 | Re-run / Resubmit | ❌ Blocked (listCallbackUrl 401) | ✅ Works | |
| A5 | ARM: Get Logic App properties | ✅ Works | ✅ Works | ARM control-plane unaffected in both |
| A6 | ARM: List workflows | ✅ Works | ✅ Works | |
| A7 | ARM: List workflow runs | ✅ Works | ✅ Works | |

### Trigger Security (Track B)

| # | Test | Easy Auth Lab (`Return401`) | APIM Lab | Notes |
|---|------|----------------------------|----------|-------|
| B1 | Valid Entra token → 200 | ✅ 200 | ✅ 200 (via APIM) | Both enforce Entra auth |
| B2 | Invalid/expired token → 401 | ✅ 401 (Easy Auth) | ✅ 401 (APIM validate-jwt) | Rejection point differs |
| B3 | Wrong audience → 401 | ✅ 401 | ✅ 401 | |
| B4 | No token → 401 | ✅ 401 | ✅ 401 | |
| B5 | Direct call to Logic App (bypass APIM) | N/A | ❌ 403 (access restriction) | APIM lab blocks at network level |
| B6 | Valid token to Logic App directly | ✅ 200 (Easy Auth validates) | ❌ 403 (access restriction) | APIM lab is stricter: network + auth |

### Operational Characteristics

| Dimension | Easy Auth Lab | APIM Lab |
|-----------|--------------|----------|
| Auth config location | Per app (`authsettingsV2`) | Centralized (APIM policy) |
| Config drift risk | High (N apps × N configs) | Low (single policy, N API definitions) |
| Portal manageability | ❌ Broken with `Return401` | ✅ Fully preserved |
| Management endpoint access | ❌ hostruntime blocked | ✅ hostruntime accessible |
| Network isolation | Requires Private Endpoint per app | Access restrictions + APIM subnet |
| Token rejection point | App host (Easy Auth middleware) | APIM gateway (before reaching app) |
| Additional infra cost | None (built-in) | APIM instance required |
| WAF capability | None | APIM + App Gateway or Front Door |
| Rate limiting | None | APIM policy |
| API versioning | None | APIM built-in |
| Centralized logging | Per-app App Insights | APIM diagnostics + per-app App Insights |

---

## 6. IP Address Consumption Comparison

### The Problem

Each Private Endpoint consumes one IP address from the subnet. With Easy Auth, Private Endpoints are the primary network isolation mechanism. As the number of apps scales, IP address consumption becomes a VNet design constraint.

### Comparison Table

| Number of Apps | Easy Auth + Private Endpoint per App | APIM Centralized + Access Restrictions |
|:--------------:|:------------------------------------:|:--------------------------------------:|
| 10 | **10 IPs** (10 PE NICs) | **~5 IPs** (APIM subnet: 3–5 IPs) |
| 50 | **50 IPs** (requires /26 subnet) | **~5 IPs** (same APIM instance) |
| 100 | **100 IPs** (requires /25 subnet) | **~5 IPs** (same APIM instance) |
| 200 | **200 IPs** (requires /24 subnet) | **~5 IPs** (same APIM instance) |
| 500 | **500 IPs** (requires /23 subnet) | **~5 IPs** (APIM Premium with 2 units) |

### Notes

- **Easy Auth model**: Each Logic App / Function App gets its own Private Endpoint. Each PE creates a NIC consuming 1 IP. At 200 apps, you need a `/24` subnet just for PE NICs — a full Class C block.
- **APIM model**: A single APIM instance in a dedicated subnet (recommended `/27` = 32 IPs, of which APIM uses 3–5 depending on scale units). All apps sit behind access restrictions referencing the APIM subnet — **zero Private Endpoints on the app side**.
- **APIM subnet requirement**: APIM requires a dedicated subnet. For Developer SKU, a `/29` (8 IPs) is technically sufficient. For Premium with VNet integration, Microsoft recommends `/27` (32 IPs).
- **DNS zones**: Easy Auth + PE model requires a Private DNS zone entry per app. APIM model requires only the APIM endpoint DNS entry.

### Subnet Sizing Impact

| Model | Apps = 200 | Subnet Size Needed | Remaining IPs (in a /24) |
|-------|:----------:|:------------------:|:------------------------:|
| Easy Auth + PE | 200 PEs | `/24` (256 IPs) | **56** |
| APIM centralized | 1 APIM subnet | `/27` (32 IPs) | **224** |
| **Savings** | | | **168 IPs reclaimed** |

---

## 7. Cost Considerations

### Lab Costs (Developer SKU)

| Resource | SKU | Est. Monthly Cost | Notes |
|----------|-----|:-----------------:|-------|
| APIM | Developer | ~€45/month | No SLA, single instance, sufficient for lab |
| Logic App (reused) | WS1 | ~€130/month | Same as Easy Auth lab |
| Storage Account | Standard_LRS | ~€1/month | Reused from Easy Auth lab |
| Log Analytics | Pay-as-you-go | ~€2/month | Reused |
| App Insights | — | ~€0/month (free tier) | Reused |
| **Lab Total** | | **~€178/month** | |

### Production Cost Considerations

| Tier | APIM SKU | Est. Monthly | VNet Support | SLA | Notes |
|------|----------|:------------:|:------------:|:---:|-------|
| Lab | Developer | ~€45 | External only | None | **This lab** |
| Standard | Standard v2 | ~€150 | VNet integration | 99.95% | Good for non-VNet-isolated workloads |
| Premium | Premium | ~€2,800+ | Full VNet (internal) | 99.99% | Required for internal VNet mode |
| Premium v2 | Premium v2 | ~€2,800+ | Full VNet (internal) | 99.99% | Newer, improved perf |

> **Important**: APIM Developer SKU does **not** support internal VNet mode. The lab uses External VNet mode or no VNet. Production deployments requiring internal VNet mode (Scenario 1) need Premium SKU. Evaluate the cost against the savings from eliminating per-app Private Endpoints and the operational benefits of centralized auth.

### Cost Comparison at Scale (200 Apps)

| Cost Element | Easy Auth + PE Model | APIM Centralized |
|-------------|:--------------------:|:----------------:|
| APIM | €0 | ~€2,800/month (Premium) |
| Private Endpoints (200× PE) | ~€2,000/month (200 × ~€10) | €0 |
| Private DNS Zones | ~€100/month | ~€1/month |
| Operational overhead (config drift, per-app auth debug) | High (unquantified) | Low |
| **Total incremental infra** | **~€2,100/month** | **~€2,801/month** |

> At 200 apps, the infra cost is roughly comparable. The operational savings from centralized management, zero config drift, and preserved portal access tip the balance toward APIM. At 300+ apps, APIM becomes cheaper on infra alone.

---

## 8. Implementation Phases

### Phase 1 — Deploy APIM + Logic App Baseline

**Goal**: Stand up APIM Developer SKU alongside the existing Easy Auth lab Logic App, but **without Easy Auth enabled** on the Logic App.

**Tasks**:
1. Create `infra/modules/apim.bicep` — APIM Developer SKU, external mode
2. Update `infra/modules/foundation.bicep` — add APIM subnet if VNet is present (or create VNet)
3. Deploy Logic App **without** `authsettingsV2` (reuse `logicapp.bicep`, skip `easyauth.bicep`)
4. Verify Logic App is directly callable (no auth barrier)
5. Verify portal run history, callback URLs, re-run all work (baseline proof)
6. Create `infra/params/apim-lab-dev.bicepparam`

**Exit criteria**:
- [ ] APIM instance is deployed and reachable
- [ ] Logic App is deployed without Easy Auth
- [ ] Portal scenarios A1–A4 pass on the bare Logic App

### Phase 2 — Add JWT Validation Policy

**Goal**: Configure APIM to front the Logic App with Entra ID JWT validation.

**Tasks**:
1. Create `infra/modules/apim-api.bicep` — API definition with Logic App as backend
2. Create APIM named values for `tenant-id` and `client-id` (from existing Entra app registration)
3. Apply `validate-jwt` inbound policy (see section 4)
4. Test: valid token → 200 through APIM
5. Test: invalid token → 401 at APIM
6. Test: no token → 401 at APIM
7. Test: wrong audience → 401 at APIM

**Exit criteria**:
- [ ] APIM correctly validates JWTs
- [ ] Scenarios B1–B4 pass through APIM
- [ ] Logic App is still directly callable (access restrictions not yet applied)

### Phase 3 — Lock Down Logic App

**Goal**: Apply access restrictions so the Logic App only accepts traffic from the APIM subnet.

**Tasks**:
1. Create `infra/modules/access-restrictions.bicep`
2. Apply access restriction: allow APIM subnet, deny all others
3. Test: direct call to Logic App → 403 Forbidden
4. Test: call through APIM with valid token → 200
5. Test: call through APIM with invalid token → 401

**Exit criteria**:
- [ ] Direct access to Logic App is blocked (403)
- [ ] APIM-routed traffic with valid token succeeds
- [ ] Portal scenarios A1–A4 still pass (access restrictions do not affect ARM/portal)

### Phase 4 — Run Full Validation Matrix

**Goal**: Execute the complete validation matrix and document results side-by-side with Easy Auth lab.

**Tasks**:
1. Adapt `scripts/validate.ps1` or create `scripts/validate-apim.ps1`
2. Run Track A scenarios (portal manageability) — document results
3. Run Track B scenarios (trigger security via APIM) — document results
4. Run network isolation tests (direct access blocked)
5. Populate the comparison matrix (section 5)
6. Capture evidence: screenshots, API response bodies, correlation IDs

**Exit criteria**:
- [ ] All matrix cells populated with actual results
- [ ] Evidence saved to `docs/evidence/apim-lab/`
- [ ] Comparison with Easy Auth lab is complete

### Phase 5 — Document Findings & Recommendation

**Goal**: Produce a customer-ready findings document and recommendation.

**Tasks**:
1. Update `docs/evidence/findings.md` with APIM lab results (or create `docs/evidence/apim-findings.md`)
2. Write customer recommendation (see section 9)
3. Update main `README.md` to reference APIM lab plan and findings
4. Create architecture decision record if needed
5. Prepare presentation-ready summary (optional)

**Exit criteria**:
- [ ] Customer-ready recommendation document exists
- [ ] All findings are evidence-backed
- [ ] Repository links are consistent

### Phase Summary

```text
Phase 1 ──▶ Phase 2 ──▶ Phase 3 ──▶ Phase 4 ──▶ Phase 5
Deploy       JWT         Lock down    Validate     Document
APIM +       policy      Logic App    full         & recommend
Logic App    on APIM     (access      matrix
(no auth)                restrict)
```

Estimated duration: 2–3 days for all phases (APIM Developer SKU deploys in ~30–45 minutes; Premium can take 30–60 minutes).

---

## 9. Customer Recommendation Summary

### Executive Recommendation

Based on the combined results of the Easy Auth lab and APIM lab:

---

#### ❌ Easy Auth on Logic Apps Standard is NOT Recommended for Portal-Critical Workloads

Easy Auth (`authsettingsV2` with `Return401`) **breaks Azure portal management capabilities** on Logic App Standard. The Easy Auth middleware intercepts `/hostruntime/*` data-plane requests — the same endpoints the portal uses for run history, run details, callback URLs, and re-run/resubmit.

**Impact**: Operations teams lose visibility into workflow execution. Troubleshooting requires CLI workarounds. Portal-based management becomes impossible for Return401-configured apps.

**Evidence**: Easy Auth Lab scenarios A1–A4 — all blocked with HTTP 401.

---

#### ✅ APIM-Based Centralized Auth is the Preferred Pattern at Enterprise Scale

For organizations with **tens to hundreds** of Logic Apps and Function Apps:

| Benefit | Detail |
|---------|--------|
| **Portal access preserved** | No Easy Auth on app host → hostruntime endpoints work normally |
| **Centralized auth** | Single APIM `validate-jwt` policy covers all backend apps |
| **Reduced IP consumption** | ~5 IPs for APIM vs. _N_ IPs for _N_ Private Endpoints |
| **Operational simplicity** | One auth config to audit, update, and monitor |
| **Additional capabilities** | Rate limiting, API versioning, caching, analytics — included |
| **Network isolation** | Access restrictions on apps + APIM subnet = no direct access |

---

#### ⚠️ For Small / Isolated Workloads, Easy Auth with `excludedPaths` is Acceptable

If the workload is:
- A **single** Logic App or small set of apps
- Not portal-management-critical (e.g., fire-and-forget, no operational monitoring)
- In a dev/test environment

Then Easy Auth with `excludedPaths` is a reasonable lightweight option:

```json
{
  "globalValidation": {
    "unauthenticatedClientAction": "Return401",
    "excludedPaths": ["/runtime/*", "/hostruntime/*"]
  }
}
```

**Trade-off**: The `/hostruntime/*` exclusion means management endpoints are not protected by Easy Auth. This is acceptable because ARM RBAC already protects them — but it should be documented as a conscious decision.

---

#### 🏢 Enterprise-Scale Recommendation

For the customer's environment (hundreds of Logic Apps and Function Apps):

```
┌──────────────────────────────────────────────────────────────┐
│  RECOMMENDED ARCHITECTURE                                     │
│                                                                │
│  Internet / Corporate Network                                 │
│       │                                                        │
│       ▼                                                        │
│  App Gateway WAF  or  Front Door Premium                      │
│       │                                                        │
│       ▼                                                        │
│  Azure API Management (Premium, Internal VNet)                │
│  ┌────────────────────────────────────────┐                   │
│  │ validate-jwt (Entra ID)                │                   │
│  │ rate-limit-by-key                      │                   │
│  │ cors                                   │                   │
│  │ log-to-eventhub (audit trail)          │                   │
│  └────────────────────────────────────────┘                   │
│       │                                                        │
│       ▼                                                        │
│  Logic Apps / Function Apps (100s)                             │
│  ┌────────────────────────────────────────┐                   │
│  │ Access restrictions: APIM subnet only  │                   │
│  │ Easy Auth: NOT enabled                 │                   │
│  │ Portal management: ✅ Full             │                   │
│  │ Private Endpoints: NOT needed          │                   │
│  └────────────────────────────────────────┘                   │
│                                                                │
│  IP addresses consumed: ~5 (APIM) instead of 200+ (PEs)      │
│  Auth configs to manage: 1 (APIM policy) instead of 200+     │
└──────────────────────────────────────────────────────────────┘
```

### Decision Matrix

| Factor | Easy Auth (`Return401`) | Easy Auth + `excludedPaths` | APIM Centralized |
|--------|:-----------------------:|:---------------------------:|:----------------:|
| Portal manageability | ❌ | ✅ | ✅ |
| Entra auth enforced | ✅ | ✅ (API routes only) | ✅ |
| Centralized config | ❌ | ❌ | ✅ |
| IP address efficiency | ❌ (1 PE per app) | ❌ (1 PE per app) | ✅ (~5 IPs total) |
| Operational simplicity | ❌ | ⚠️ | ✅ |
| Additional cost | None | None | APIM Premium ~€2,800/mo |
| Scale suitability | Small only | Small–medium | Medium–enterprise |
| **Recommendation** | **❌ Avoid** | **⚠️ Acceptable (small)** | **✅ Recommended** |

---

## 10. Open Questions & Risks

| # | Question / Risk | Status | Owner |
|---|----------------|--------|-------|
| 1 | Does APIM Developer SKU support sufficient VNet features for the lab, or do we need Standard v2? | Open | Lab team |
| 2 | Can access restrictions reference an APIM subnet in a different resource group / subscription? | Open | Lab team |
| 3 | What is the APIM deploy time for Developer SKU vs. Premium? (affects lab iteration speed) | Open | Lab team |
| 4 | Should the lab test with v1.0 and v2.0 Entra tokens, or v2.0 only? | Open | Customer |
| 5 | Are there Logic Apps using Consumption SKU that cannot use access restrictions? | Open | Customer |
| 6 | Does the customer have existing APIM infrastructure to leverage? | Open | Customer |

---

## Appendix A — File Structure (Planned)

```
EasyAuth/
├── docs/
│   ├── apim-lab-plan.md              ← This document
│   └── evidence/
│       ├── findings.md               ← Easy Auth lab findings (existing)
│       └── apim-lab/                 ← APIM lab evidence (Phase 4)
│           ├── screenshots/
│           ├── api-responses/
│           └── apim-findings.md
├── infra/
│   ├── main.bicep                    ← Update to support APIM lab mode
│   ├── modules/
│   │   ├── foundation.bicep          ← Update: add APIM subnet
│   │   ├── logicapp.bicep            ← Reuse as-is (no Easy Auth)
│   │   ├── easyauth.bicep            ← NOT used in APIM lab
│   │   ├── apim.bicep                ← NEW: APIM instance
│   │   ├── apim-api.bicep            ← NEW: API definition + policy
│   │   └── access-restrictions.bicep ← NEW: Logic App access restrictions
│   └── params/
│       ├── dev-westeurope.bicepparam      ← Easy Auth lab params (existing)
│       └── apim-lab-dev.bicepparam        ← NEW: APIM lab params
└── scripts/
    ├── deploy.ps1                    ← Existing Easy Auth deploy
    ├── validate.ps1                  ← Existing Easy Auth validate
    ├── deploy-apim.ps1              ← NEW: APIM lab deploy
    └── validate-apim.ps1            ← NEW: APIM lab validate
```

## Appendix B — References

- [APIM validate-jwt policy reference](https://learn.microsoft.com/en-us/azure/api-management/validate-jwt-policy)
- [APIM VNet integration](https://learn.microsoft.com/en-us/azure/api-management/virtual-network-concepts)
- [Logic App access restrictions](https://learn.microsoft.com/en-us/azure/app-service/app-service-ip-restrictions)
- [Entra ID v2.0 token reference](https://learn.microsoft.com/en-us/entra/identity-platform/access-tokens)
- [Easy Auth lab findings](./evidence/findings.md)
