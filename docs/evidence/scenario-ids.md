# Scenario ID Reference

This file is the single source of truth for scenario IDs used across all lanes.

## Track A — Portal Manageability

- **A1**: View run history list (Return401)
- **A2**: View run details (Return401)
- **A3**: View inputs/outputs (Return401)
- **A4**: Re-run/Resubmit (Return401)
- **A5**: View run history list (AllowAnonymous)
- **A6**: View run details (AllowAnonymous)
- **A7**: View inputs/outputs (AllowAnonymous)
- **A8**: Re-run/Resubmit (AllowAnonymous)

## Track B — Trigger Security

- **B1**: Valid token + Return401 → expect 200
- **B2**: Invalid/expired token + Return401 → expect 401
- **B3**: Wrong audience token + Return401 → expect 401
- **B4**: No token + Return401 → expect 401
- **B5**: No token + AllowAnonymous → expect 200
- **B6**: Valid token + SAS disabled + Return401 → expect 200
- **B7**: No token + SAS key only + Return401 → expect 401
