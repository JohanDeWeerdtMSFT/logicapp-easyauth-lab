# Lab Findings (Trainee Summary)

This page summarizes the most important findings from lab validation runs in trainee-friendly language.

If you want raw scan artifacts, see the latest generated evidence under `documentation/azure-scan/`.

---

## Why This Page Exists

Use this page to quickly understand:

1. What behavior was observed in testing.
2. Why that behavior matters for implementation.
3. What configuration pattern to use in this lab.

---

## Current finding

The public classroom path was validated end to end on 2026-08-04 with Logic App `Return401`, workflow method `POST`, and the Function App system-assigned managed identity in `allowedPrincipals`. See [current validation and drift](current-validation-and-drift.md).

## Portal manageability findings

### 1) `Return401` requires a runtime-path exclusion for portal run history

When Easy Auth is configured with `unauthenticatedClientAction: Return401`, portal run-history requests fail unless `/runtime/*` is excluded from Easy Auth. The classroom baseline now deploys that narrow exclusion.

What this means for trainees:

- Run-history requests reach the Logic Apps runtime and use its own authorization.
- Workflow trigger calls under `/api/*` remain protected by Easy Auth.
- An unsigned trigger call still returns HTTP 401.

### 2) `AllowAnonymous + allowedPrincipals` was a historical manageability experiment

Using `AllowAnonymous` can preserve some portal/runtime operations, but an anonymous request is not rejected at the Easy Auth edge. It is not the current secured classroom baseline.

What this means for trainees:

- Portal operations remain usable.
- Bearer-token requests are still validated by Easy Auth.
- You can complete both learning goals: secure call path + operational visibility.

### 3) Private storage and identity controls work together

The classroom lab uses private storage endpoints, VNet integration, and managed identity while app endpoints remain public.

What this means for trainees:

- Security is not only token-based; network boundaries are also enforced.
- The final pattern reflects enterprise deployment expectations.

---

## Practical Impact

For this lab implementation, use this default direction:

1. Keep Easy Auth enabled on the app host.
2. Use `Return401`, the Logic App audience, and `allowedPrincipals` for the classroom security proof.
3. Treat `AllowAnonymous` and private app ingress as optional advanced investigations.
4. Validate behavior using the scenario IDs in [scenario-ids.md](scenario-ids.md).

---

## Evidence Sources

- Scenario matrix and expected outcomes: [scenario-ids.md](scenario-ids.md)
- Latest generated scan findings: `documentation/azure-scan/lab3-scan-evidence/findings.md`

---

## Is This Page Still Necessary?

Yes, because it provides a short, trainee-focused interpretation layer between:

- low-level scan outputs, and
- step-by-step lab execution content.

If your goal is only deployment, you can skip this page.
If your goal is understanding *why* specific Easy Auth settings are used, this page is recommended.
