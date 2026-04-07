# Fleet Lanes for Copilot CLI

## Lane A - IaC Foundation (blocking)
Goal: Produce modular Bicep baseline and parameter sets.

Tasks:
1. Create `infra/main.bicep` and module references.
2. Create modules for foundation, logic app standard, easy auth, and private networking variant.
3. Create `infra/params/dev-westeurope.bicepparam` and `infra/params/dev-swedencentral.bicepparam`.
4. Expose outputs required by validation scripts.

Exit criteria:
1. Bicep compiles.
2. Parameters are environment-ready.
3. Module interfaces documented.

## Lane B - Logic App Easy Auth (blocking)
Goal: Implement the reproducible auth behavior matrix on Logic App Standard.

Tasks:
1. Define HTTP-trigger workflow for reproducible calls.
2. Configure `authsettingsV2` with Microsoft Entra provider.
3. Implement mode toggle:
- Mode X: `Return401`.
- Mode Y: `AllowAnonymous`.
4. Add allowed audience, tenant restriction, and allowed principal settings.
5. Add optional SAS disable/hardening toggles.

Exit criteria:
1. Mode switching works by parameter.
2. Scenario IDs are documented for Track A and Track B.

## Lane C - Evidence and Customer Artifacts (blocking)
Goal: Build evidence package in parallel from day one.

Tasks:
1. Create `README.md` skeleton with architecture and runbook.
2. Create findings log template and scenario matrix.
3. Add placeholders for screenshots, status table, and correlation IDs.
4. Keep evidence updated during each run.

Exit criteria:
1. Matrix has both tracks and expected outcomes.
2. Findings log can be shared directly with customer.

## Lane D - Function App Comparison (optional, non-blocking)
Goal: Provide platform reference behavior only.

Tasks:
1. Deploy control Function App (no Easy Auth).
2. Deploy Easy Auth Function App variant.
3. Record comparative outcomes only.

Exit criteria:
1. Results recorded without blocking Logic App conclusions.

## Merge Gate Contract
Before merge/deploy:
1. Shared scenario IDs match across lanes.
2. Outputs referenced in scripts exist in Bicep outputs.
3. Naming and regions are consistent (`westeurope` primary, `swedencentral` fallback).
4. No lane introduces hard dependency on optional Lane D.