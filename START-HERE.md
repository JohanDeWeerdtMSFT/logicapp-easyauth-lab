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
| 5 | Validate | Follow [labs/lab3-bearer-token/docs/lab3-testing-and-verification.md](labs/lab3-bearer-token/docs/lab3-testing-and-verification.md) and check [docs/evidence/scenario-ids.md](docs/evidence/scenario-ids.md) |
| 6 | Troubleshoot | Use [docs/troubleshooting.md](docs/troubleshooting.md) |

## Step 0 - If Using GitHub Codespaces

1. Open this repo in Codespaces.
2. Wait for devcontainer setup to finish.
3. Run `az login --use-device-code`.
4. Copy `.env.example` to `.env` and fill values.

## Step 1 - Understand the Goal

1. Read [README.md](README.md), especially the **Before you deploy** prerequisites and the private networking warning.
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
2. Read [docs/lab3-testing-evidence-summary.md](docs/lab3-testing-evidence-summary.md).

## Step 4 - Deploy Infrastructure

Run:

```powershell
./scripts/deploy.ps1 -EntraAppClientId "{clientId}" -EntraAppTenantId "{tenantId}"
```

Then confirm resource group `rg-la-easyauth-lab-dev` is created.

## Step 5 - Deploy and Validate App Flow

1. Follow [labs/lab3-bearer-token/docs/lab3-testing-and-verification.md](labs/lab3-bearer-token/docs/lab3-testing-and-verification.md).
   > **Note:** Some steps in that guide still reference a SAS-signed callback URL
   > (`sp`, `sv`, `sig` parameters) as an example `LOGIC_APP_URL` value. The active
   > learner path in this lab authenticates with an Entra access token, not a SAS
   > signature; treat the callback URL in that guide as an illustrative endpoint
   > format only, not as a required SAS-based authentication step.
2. Validate outcomes in [docs/evidence/scenario-ids.md](docs/evidence/scenario-ids.md).

## Step 6 - Confirm Success

1. Check Application Insights traces for token acquisition and the outbound call.
2. Check Logic App run history for successful execution.

## Step 7 - Troubleshoot If Needed

Use [docs/troubleshooting.md](docs/troubleshooting.md), then [DEPLOYMENT-FAQ.md](DEPLOYMENT-FAQ.md).

## Common Questions

| Question | Answer |
| --- | --- |
| How do I deploy quickly? | Complete steps 1-2, then run `scripts/deploy.ps1` in Step 4. |
| Where are expected scenarios? | [docs/evidence/scenario-ids.md](docs/evidence/scenario-ids.md) |
| Where is troubleshooting? | [docs/troubleshooting.md](docs/troubleshooting.md) |
| Where are the identity concepts explained? | [docs/lab3-managed-identity-bearer-token-flow.md](docs/lab3-managed-identity-bearer-token-flow.md) |
| How do I clean up resources? | [DEPLOYMENT-FAQ.md](DEPLOYMENT-FAQ.md#clean-up--undeploy) |
| Is Codespaces supported? | Yes, via `.devcontainer/devcontainer.json`. |

## Recommended Reading Order

1. [README.md](README.md)
2. [docs/lab3-managed-identity-bearer-token-flow.md](docs/lab3-managed-identity-bearer-token-flow.md)
3. [docs/lab3-passwordless-managed-identity-easy-auth.md](docs/lab3-passwordless-managed-identity-easy-auth.md)
4. [labs/lab3-bearer-token/docs/lab3-testing-and-verification.md](labs/lab3-bearer-token/docs/lab3-testing-and-verification.md)
5. [docs/evidence/findings.md](docs/evidence/findings.md)

## Optional Background Reading

- [documentation/architecture/background-apim-alternative.html](documentation/architecture/background-apim-alternative.html)
- [documentation/architecture/background-waf-caf-alignment.html](documentation/architecture/background-waf-caf-alignment.html)

These are architecture best-practice pages and are not required for Lab 3 completion.
They provide context related to earlier lab patterns and enterprise design choices.
