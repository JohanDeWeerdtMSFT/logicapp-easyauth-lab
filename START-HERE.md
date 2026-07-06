# START HERE - Active Lab (Lab 3) Quick Navigation

This repository is now focused on one trainee path:

- Lab 3: secure Function App to Logic App calls with managed identity + Easy Auth.

Lab 1 and Lab 2 material is now background context only and is not required for completion of the active hands-on path.

## Fast 15-Minute Path

1. Read [docs/lab3-quick-reference-card.md](docs/lab3-quick-reference-card.md).
2. Deploy with `./scripts/deploy.ps1 -EntraAppClientId "{clientId}" -EntraAppTenantId "{tenantId}"`.
3. Run [labs/lab3-bearer-token/docs/lab3-testing-and-verification.md](labs/lab3-bearer-token/docs/lab3-testing-and-verification.md).
4. Confirm expected outcomes in [docs/evidence/scenario-ids.md](docs/evidence/scenario-ids.md).

## Fastest Path

### Step 0 - If Using GitHub Codespaces

1. Open this repo in Codespaces.
2. Wait for devcontainer setup to finish.
3. Run `az login --use-device-code`.
4. Copy `.env.example` to `.env` and fill values.

### Step 1 - Understand the Goal

1. Read [README.md](README.md).
2. Read [docs/lab3-quick-reference-card.md](docs/lab3-quick-reference-card.md).

### Step 2 - Review What Gets Deployed

1. Read [docs/lab3-testing-evidence-summary.md](docs/lab3-testing-evidence-summary.md).

### Step 3 - Deploy Infrastructure

1. Run:

```powershell
./scripts/deploy.ps1 -EntraAppClientId "{clientId}" -EntraAppTenantId "{tenantId}"
```

1. Confirm resource group `rg-la-easyauth-lab-dev` is created.

### Step 4 - Deploy and Validate App Flow

1. Follow [labs/lab3-bearer-token/docs/lab3-testing-and-verification.md](labs/lab3-bearer-token/docs/lab3-testing-and-verification.md).
2. Validate outcomes in [docs/evidence/scenario-ids.md](docs/evidence/scenario-ids.md).

### Step 5 - Confirm Success

1. Check Application Insights traces for token acquisition and outbound call.
2. Check Logic App run history for successful execution.

## Common Questions

| Question | Answer |
| --- | --- |
| How do I deploy quickly? | Use Step 3 and run `scripts/deploy.ps1`. |
| Where are expected scenarios? | [docs/evidence/scenario-ids.md](docs/evidence/scenario-ids.md) |
| Where is troubleshooting? | [docs/troubleshooting.md](docs/troubleshooting.md) |
| How do I clean up resources? | [DEPLOYMENT-FAQ.md](DEPLOYMENT-FAQ.md#clean-up--undeploy) |
| Is Codespaces supported? | Yes, via `.devcontainer/devcontainer.json`. |

## Recommended Reading Order

1. [README.md](README.md)
2. [docs/lab3-passwordless-managed-identity-easy-auth.md](docs/lab3-passwordless-managed-identity-easy-auth.md)
3. [labs/lab3-bearer-token/docs/lab3-testing-and-verification.md](labs/lab3-bearer-token/docs/lab3-testing-and-verification.md)
4. [docs/evidence/findings.md](docs/evidence/findings.md)

## Optional Background Reading

- [documentation/architecture/background-apim-alternative.html](documentation/architecture/background-apim-alternative.html)
- [documentation/architecture/background-waf-caf-alignment.html](documentation/architecture/background-waf-caf-alignment.html)

These are architecture best-practice pages and are not required for Lab 3 completion.
They provide context related to earlier lab patterns and enterprise design choices.
