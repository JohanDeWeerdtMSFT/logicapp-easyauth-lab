# Fleet Lanes for Copilot CLI

## Lane A — IaC Foundation (blocking)

Goal: Produce modular Bicep baselines for **both labs**.

Tasks:
1. Maintain `infra/main.bicep` and modules for Lab 1 (Easy Auth).
2. Maintain `infra/apim-lab/main.bicep` for Lab 2 (APIM-centric).
3. Create/update parameter sets for both labs.
4. Expose outputs required by validation scripts.

Exit criteria:
1. Both Bicep templates compile.
2. Parameters are environment-ready for both resource groups.
3. Module interfaces documented.

## Lane B — Lab 1: Easy Auth on Logic App Standard (blocking)

Goal: Implement the AllowAnonymous + allowedPrincipals pattern on Logic App Standard.

Reference: [azcloudsecurity.io — Logic App Standard Easy Auth](https://azcloudsecurity.io/posts/logic-app-standard-easy-auth/)

Tasks:
1. Define HTTP-trigger workflow for reproducible calls.
2. Configure `authsettingsV2` with:
   - `unauthenticatedClientAction: AllowAnonymous`
   - `platform.enabled: true` and `runtimeVersion: ~1`
   - `allowedAudiences` set to App Registration client ID
   - `allowedPrincipals.identities` set to APIM managed identity object ID
3. Add `WEBSITE_AUTH_AAD_ALLOWED_TENANTS` environment variable.
4. Validate Track A: portal manageability with AllowAnonymous.
5. Validate Track B: trigger security (token enforcement despite AllowAnonymous).

Exit criteria:
1. Portal management works (A1–A4 pass).
2. Requests WITH valid Entra token → 200.
3. Requests WITH invalid/missing token → rejected when Authorization header is present.
4. SAS key triggers still work (expected — not disabled).

## Lane C — Lab 2: APIM-Centric Security (blocking)

Goal: Deploy APIM-fronted architecture where JWT validation is centralized at the gateway.

Tasks:
1. Deploy APIM (Developer SKU) with `validate-jwt` inbound policy.
2. Deploy Logic App Standard **without** Easy Auth.
3. Configure APIM backend pointing to Logic App.
4. Add access restrictions on Logic App to allow only APIM traffic.
5. Validate Track C: APIM JWT validation (valid/invalid/missing token).
6. Validate Track D: Logic App unreachable directly (only via APIM).
7. Validate Track E: Portal manageability (full access, no Easy Auth interference).

Exit criteria:
1. Valid Entra token through APIM → 200 from Logic App.
2. Invalid/missing token → 401 at APIM (never reaches Logic App).
3. Direct call to Logic App → blocked by access restrictions.
4. Portal management fully operational.

## Lane D — Evidence and Customer Artifacts (blocking)

Goal: Build evidence package and customer-facing documentation.

Tasks:
1. Maintain `README.md` with Lab 1 architecture and findings.
2. Maintain `docs/apim-lab-plan.md` with Lab 2 architecture and findings.
3. Create `docs/decision-guidance.md` — side-by-side comparison.
4. Update findings log with all track results.
5. Keep evidence updated during each validation run.

Exit criteria:
1. Both labs have complete scenario matrices with outcomes.
2. Decision guidance document covers trade-offs and recommendations.
3. Findings log can be shared directly with customer.

## Lane E — Architecture Diagrams and Visuals (non-blocking)

Goal: Generate rich visual documentation for customer presentations.

Tasks:
1. Create architecture diagrams for both labs.
2. Generate comparison visuals (Easy Auth vs APIM pattern).
3. Create flow diagrams for each validation track.

Exit criteria:
1. Diagrams embedded in documentation.
2. Mermaid source preserved for editability.

## Merge Gate Contract

Before merge/deploy:
1. Shared scenario IDs match across lanes.
2. Outputs referenced in scripts exist in Bicep outputs.
3. Naming and regions are consistent (`westeurope` primary, `swedencentral` fallback).
4. Both labs use separate resource groups with distinct resource names.
5. Decision guidance document references findings from both labs.