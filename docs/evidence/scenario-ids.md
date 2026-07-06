# Scenario ID Reference

This file is the source of truth for scenario IDs used in the current Lab 3-focused flow.

## Track A - Portal Manageability

- **A1**: View run history list -> expected success
- **A2**: View run details -> expected success
- **A3**: View inputs/outputs -> expected success
- **A4**: Re-run/Resubmit -> expected success

## Track B - Trigger Security

- **B1**: Valid caller identity token -> expected success
- **B2**: Invalid or expired token -> expected failure (401)
- **B3**: Wrong audience token -> expected failure (401)
- **B4**: No token and no authorized trigger context -> expected failure
- **B5**: Authorized request path for configured trigger flow -> expected success

## How To Use This Matrix

1. Select a scenario ID.
2. Execute the matching test from the lab guide.
3. Compare actual status/log behavior to expected behavior.
4. Save evidence (status code, log query output, and run-history proof).
