# Execution Checklist

## Access Gate (required)
1. Azure account context confirmed for subscription `6851693c-0b74-4462-8da8-cd498b088827`.
2. Azure MCP operations succeed (subscription/resource group list).
3. GitHub auth succeeds.
4. Repo exists: `logicapp-easyauth-lab` (private).

## Preflight
1. Region/SKU check for `westeurope`.
2. Fallback readiness for `swedencentral`.
3. Resource naming prefix selected (both labs).
4. Cleanup plan documented (both resource groups).

## Build and Merge Gate
1. Lane A complete (IaC for both labs).
2. Lane B complete (Lab 1: Easy Auth AllowAnonymous + SAS disable).
3. Lane C complete (Lab 2: APIM-centric security).
4. Lane D complete (Evidence and customer artifacts).
5. Lane E optional (Architecture diagrams).
6. Contract checks pass.

## Deploy Gate
1. What-if executed and reviewed for Lab 1 (`rg-la-easyauth-lab-dev`).
2. What-if executed and reviewed for Lab 2 (`rg-la-easyauth-lab-apim-dev`).
3. Lab 1 deployment completed.
4. Lab 2 deployment completed.
5. Diagnostics and logging enabled for both.

## Validation Gate — Lab 1 (Easy Auth)

### Track A — Portal Manageability (AllowAnonymous)
1. Run history list behavior recorded (expect: ✅ accessible).
2. Run details behavior recorded (expect: ✅ accessible).
3. Inputs/outputs visibility recorded (expect: ✅ visible).
4. Re-run/resubmit behavior recorded (expect: ✅ works).

### Track B — Trigger Security (AllowAnonymous + allowedPrincipals)
1. Valid Entra token → 200 (token validated by Easy Auth).
2. Invalid/expired token → 401 (Easy Auth rejects).
3. Wrong audience/principal → 401 or 403 (Easy Auth rejects).
4. No token, no SAS key → SAS key required (no auth bypass).
5. No token, with SAS key → 200 (SAS keys remain active).
6. Confirm: requests WITH Authorization header are always validated.

## Validation Gate — Lab 2 (APIM)

### Track C — APIM JWT Validation
1. Valid Entra token through APIM → 200 from Logic App.
2. Invalid/expired token through APIM → 401 at APIM.
3. No token through APIM → 401 at APIM.
4. Wrong audience token through APIM → 401 at APIM.

### Track D — Backend Isolation
1. Direct call to Logic App (bypassing APIM) → blocked by access restrictions.
2. APIM managed identity authentication to backend confirmed.

### Track E — Portal Manageability (No Easy Auth)
1. Run history list works (expect: ✅).
2. Run details work (expect: ✅).
3. Inputs/outputs visible (expect: ✅).
4. Re-run/resubmit works (expect: ✅).

## Evidence Gate
1. HTTP status/result matrix complete for all tracks (A–E).
2. Correlation IDs captured.
3. Screenshots and notes linked.
4. Customer-facing conclusions drafted for both labs.

## Cross-Lab Comparison Gate
1. Decision guidance document (`docs/decision-guidance.md`) complete.
2. Trade-off analysis covers: identity strictness, operational simplicity, IP scalability, portal manageability.
3. Side-by-side scenario comparison table populated.
4. Customer recommendation framework documented.

## Finalization
1. README finalized (Lab 1 focus).
2. APIM lab plan finalized (Lab 2 focus).
3. Decision guidance finalized (cross-lab).
4. Teardown instructions for both resource groups.
5. Cost summary for both labs.
6. Handoff notes published.