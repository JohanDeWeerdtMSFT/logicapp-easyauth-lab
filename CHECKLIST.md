# Execution Checklist

## Access Gate (required)
1. Azure account context confirmed for subscription `6851693c-0b74-4462-8da8-cd498b088827`.
2. Azure MCP operations succeed (subscription/resource group list).
3. GitHub auth succeeds.
4. Repo exists: `logicapp-easyauth-lab` (private).

## Preflight
1. Region/SKU check for `westeurope`.
2. Fallback readiness for `swedencentral`.
3. Resource naming prefix selected.
4. Cleanup plan documented.

## Build and Merge Gate
1. Lane A complete.
2. Lane B complete.
3. Lane C complete.
4. Lane D optional.
5. Contract checks pass.

## Deploy Gate
1. What-if executed and reviewed.
2. Deployment completed.
3. Diagnostics and logging enabled.

## Validation Gate
### Track A - Portal manageability
1. Run history list behavior recorded.
2. Run details behavior recorded.
3. Inputs/outputs visibility recorded.
4. Re-run/resubmit behavior recorded.
5. Strict vs AllowAnonymous portal behavior compared.

### Track B - Trigger security
1. Valid token case validated.
2. Invalid token case validated.
3. Wrong audience/principal case validated.
4. No-token case validated.
5. SAS enabled/disabled behavior validated.

## Evidence Gate
1. HTTP status/result matrix complete.
2. Correlation IDs captured.
3. Screenshots and notes linked.
4. Customer-facing conclusion drafted.

## Finalization
1. README finalized.
2. Teardown instructions finalized.
3. Cost summary finalized.
4. Handoff notes published.