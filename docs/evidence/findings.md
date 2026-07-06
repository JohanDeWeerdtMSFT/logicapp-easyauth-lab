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

## Key Findings

### 1) `Return401` breaks portal manageability for Logic App Standard hostruntime paths

When Easy Auth is configured with `unauthenticatedClientAction: Return401`, several portal/runtime operations can fail because requests are blocked before they reach the Logic App runtime.

What this means for trainees:

- You may deploy successfully but still lose important run-management capabilities.
- Debugging becomes harder because run details and replay-related actions can fail.

### 2) `AllowAnonymous + allowedPrincipals` is the working lab pattern

Using `AllowAnonymous` with strict `allowedPrincipals` and token validation preserves manageability while still enforcing identity checks on bearer-token calls.

What this means for trainees:

- Portal operations remain usable.
- Bearer-token requests are still validated by Easy Auth.
- You can complete both learning goals: secure call path + operational visibility.

### 3) Network isolation and identity controls work together

The lab uses private endpoints, VNet integration, and managed identity.

What this means for trainees:

- Security is not only token-based; network boundaries are also enforced.
- The final pattern reflects enterprise deployment expectations.

---

## Practical Impact

For this lab implementation, use this default direction:

1. Keep Easy Auth enabled on the app host.
2. Use `AllowAnonymous` with `allowedPrincipals` (as documented in the lab).
3. Validate behavior using the scenario IDs in [scenario-ids.md](scenario-ids.md).

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
