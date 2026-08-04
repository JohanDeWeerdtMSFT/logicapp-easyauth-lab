# START HERE - Active Lab (Lab 3) Quick Navigation

This repository is now focused on one trainee path:

- Lab 3: secure Function App to Logic App calls with managed identity + Easy Auth.

Lab 1 and Lab 2 material is now background context only and is not required for completion of the active hands-on path.

## How To Use This Page

Do the steps in order. Do not skip ahead: steps 1 and 2 give you the vocabulary you need to
understand the deployment output and to diagnose 401 versus 403 responses later.

| Order | Stage | Do this |
| --- | --- | --- |
| 1 | Understand the goal | Read [README.md](README.md), including **Before you deploy** |
| 2 | Learn the concepts | Read [docs/lab3-managed-identity-bearer-token-flow.md](docs/lab3-managed-identity-bearer-token-flow.md) |
| 3 | Review the walkthrough | Read [docs/lab3-passwordless-managed-identity-easy-auth.md](docs/lab3-passwordless-managed-identity-easy-auth.md) |
| 4 | Deploy | Run `scripts/deploy.ps1` (Step 4 below) |
| 5 | Validate | Follow [docs/lab3-testing-and-verification.md](docs/lab3-testing-and-verification.md) and check [docs/evidence/scenario-ids.md](docs/evidence/scenario-ids.md) |
| 6 | Troubleshoot | Start with [Troubleshooting the identity flow](docs/lab3-managed-identity-bearer-token-flow.md#troubleshooting-the-identity-flow), then [docs/troubleshooting.md](docs/troubleshooting.md) |

## Step 0 - If Using GitHub Codespaces

1. Open this repo in Codespaces.
2. Wait for devcontainer setup to finish.
3. Run `az login --use-device-code`.
4. Copy `.env.example` to `.env` and fill values.

## Step 1 - Understand the Goal

1. Read [README.md](README.md), especially the **Before you deploy** prerequisites and classroom networking choice.
2. Skim [docs/lab3-quick-reference-card.md](docs/lab3-quick-reference-card.md).

## Step 2 - Learn the Identity Concepts

Read [docs/lab3-managed-identity-bearer-token-flow.md](docs/lab3-managed-identity-bearer-token-flow.md).

After reading it you should be able to explain, in your own words:

- What Easy Auth is and where it runs.
- What Microsoft Entra ID, an app registration, and a managed identity are.
- What an access token, audience, resource, and scope are.
- The difference between authentication (401) and authorization (403).
- Why this lab uses an Entra access token instead of a SAS-signed callback URL.

## Step 3 - Review What Gets Deployed

1. Read [docs/lab3-passwordless-managed-identity-easy-auth.md](docs/lab3-passwordless-managed-identity-easy-auth.md).
2. Read [the current validation and drift register](docs/evidence/current-validation-and-drift.md).

## Step 4 - Deploy Infrastructure

Run:

```powershell
./scripts/deploy.ps1 -EntraAppClientId "{clientId}" -EntraAppTenantId "{tenantId}" `
  -DeployFuncCallerDemo -FuncCallerEntraClientId "{callerClientId}"
```

`-DeployFuncCallerDemo` creates the caller Function App, the virtual network and private storage
connectivity, and the caller principal allow-list. App endpoints remain public in the classroom default. Without it the deployment only creates the
Logic App and its Easy Auth configuration, and Steps 5 and 6 below cannot be completed.
`{callerClientId}` is the client ID of the **second** Entra app registration, the one that represents
the caller Function App.

For the optional private-ingress exercise, add `-EnablePrivateAppNetworking` and use a VNet-connected
deployment executor. See [Private networking and CI/CD](docs/07-private-networking-and-cicd.md).

Then confirm resource group `rg-la-easyauth-lab-dev` is created.

## Step 5 - Deploy and Validate App Flow

1. Follow [docs/lab3-testing-and-verification.md](docs/lab3-testing-and-verification.md). It deploys the workflow and caller code, validates selected access-token claims without exposing the token, and proves Easy Auth behavior.
2. Validate outcomes in [docs/evidence/scenario-ids.md](docs/evidence/scenario-ids.md).
3. Compare the deployment with [the current validation and drift register](docs/evidence/current-validation-and-drift.md).

## Step 6 - Confirm Success

1. Check Application Insights traces for token acquisition and the outbound call.
2. Check Logic App run history for successful execution.

## Step 7 - Troubleshoot If Needed

Start with [Troubleshooting the identity flow](docs/lab3-managed-identity-bearer-token-flow.md#troubleshooting-the-identity-flow) for 401, 403, invalid audience, and missing managed identity issues. Then use [docs/troubleshooting.md](docs/troubleshooting.md) and [DEPLOYMENT-FAQ.md](DEPLOYMENT-FAQ.md).

## Common Questions

| Question | Answer |
| --- | --- |
| How do I deploy quickly? | Complete steps 1-2, then run `scripts/deploy.ps1` in Step 4. |
| Where are expected scenarios? | [docs/evidence/scenario-ids.md](docs/evidence/scenario-ids.md) |
| Where is troubleshooting? | [docs/troubleshooting.md](docs/troubleshooting.md) |
| Where are the identity concepts explained? | [docs/lab3-managed-identity-bearer-token-flow.md](docs/lab3-managed-identity-bearer-token-flow.md) |
| How do I clean up resources? | [DEPLOYMENT-FAQ.md](DEPLOYMENT-FAQ.md#question-2-is-there-an-undeploy-option) |
| Is Codespaces supported? | Yes, via `.devcontainer/devcontainer.json`. |

## Recommended Reading Order

1. [README.md](README.md)
2. [docs/lab3-managed-identity-bearer-token-flow.md](docs/lab3-managed-identity-bearer-token-flow.md)
3. [docs/lab3-passwordless-managed-identity-easy-auth.md](docs/lab3-passwordless-managed-identity-easy-auth.md)
4. [docs/lab3-testing-and-verification.md](docs/lab3-testing-and-verification.md)
5. [docs/evidence/findings.md](docs/evidence/findings.md)

## Optional Background Reading

- [documentation/architecture/background-apim-alternative.html](documentation/architecture/background-apim-alternative.html)
- [documentation/architecture/background-waf-caf-alignment.html](documentation/architecture/background-waf-caf-alignment.html)

These are architecture best-practice pages and are not required for Lab 3 completion.
They provide context related to earlier lab patterns and enterprise design choices.
