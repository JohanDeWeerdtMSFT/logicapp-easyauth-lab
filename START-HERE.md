# START HERE - Active Lab (Lab 3) Quick Navigation

This repository is now focused on one trainee path:

- Lab 3: secure Function App to Logic App calls with managed identity + Easy Auth.

Already have the Logic App and Function App? Start with [Portal-only setup for existing resources](docs/lab3-walkthrough.md#portal-only-setup-for-existing-resources). For a new environment, follow the same walkthrough through deployment. Run its final resource-group cleanup only after completing all validation paths.

Lab 1 and Lab 2 material is now background context only and is not required for completion of the active hands-on path.

## How To Use This Page

Do the steps in order. Do not skip ahead: steps 1 and 2 give you the vocabulary you need to
understand the deployment output and to diagnose 401 versus 403 responses later.

| Order | Stage | Do this |
| --- | --- | --- |
| 1 | Understand the goal | Read [README.md](README.md), including **Before you deploy** |
| 2 | Learn the concepts | Read [docs/lab3-managed-identity-bearer-token-flow.md](docs/lab3-managed-identity-bearer-token-flow.md) |
| 3 | Configure or deploy | Use [docs/lab3-walkthrough.md](docs/lab3-walkthrough.md) for portal setup on existing resources or Bicep deployment of a new environment |
| 4 | Inspect the Function implementation | Read the [managed-identity code flow](docs/lab3-passwordless-managed-identity-easy-auth.md#code-flow), [C# Function](solution/CallerFunctionApp/CallLogicApp.cs), and [minimal PowerShell example](scripts/call-logicapp-with-managed-identity.ps1) |
| 5 | Test Easy Auth from your PC | Use [docs/lab3-direct-pc-testing.md](docs/lab3-direct-pc-testing.md) to prove 401, 403, and 200, then restore the Function-only allow-list |
| 6 | Test the Function path | Follow [docs/lab3-testing-and-verification.md](docs/lab3-testing-and-verification.md) to invoke the keyed Function and prove its managed-identity call |
| 7 | Troubleshoot | Start with [Troubleshooting the identity flow](docs/lab3-managed-identity-bearer-token-flow.md#troubleshooting-the-identity-flow), then [docs/troubleshooting.md](docs/troubleshooting.md) |
| 8 | Clean up last | Run Step 17 in [docs/lab3-walkthrough.md](docs/lab3-walkthrough.md#step-17-clean-up-after-the-lab) only after every test is complete |

## Step 0 - If Using GitHub Codespaces

1. Open this repo in Codespaces.
2. Wait for devcontainer setup to finish.
3. Run `az login --use-device-code`.
4. Copy `.env.example` to `.env` and fill values.

## Step 1 - Understand the Goal

1. Read [README.md](README.md), especially the **Before you deploy** prerequisites and classroom networking choice.
2. Open [docs/README.md](docs/README.md) to see which canonical walkthrough owns each learner goal.

## Step 2 - Learn the Identity Concepts

Read [docs/lab3-managed-identity-bearer-token-flow.md](docs/lab3-managed-identity-bearer-token-flow.md).

After reading it you should be able to explain, in your own words:

- What Easy Auth is and where it runs.
- What Microsoft Entra ID, an app registration, and a managed identity are.
- What an access token, audience, resource, and scope are.
- The difference between authentication (401) and authorization (403).
- Why this lab uses an Entra access token instead of a SAS-signed callback URL.

## Step 3 - Configure or Deploy the Lab

Follow [docs/lab3-walkthrough.md](docs/lab3-walkthrough.md). Use its portal-only route when the resources already exist, or its numbered Bicep path for a new environment. Stop before Step 17 until the direct-PC and Function validation paths are complete.

## Step 4 - Inspect the Function Implementation

Review the [managed-identity code flow](docs/lab3-passwordless-managed-identity-easy-auth.md#code-flow), then inspect:

- [solution/CallerFunctionApp/CallLogicApp.cs](solution/CallerFunctionApp/CallLogicApp.cs) for the deployed .NET Function implementation.
- [scripts/call-logicapp-with-managed-identity.ps1](scripts/call-logicapp-with-managed-identity.ps1) for the two underlying managed-identity endpoint operations without framework abstractions.
- [scripts/demo-easyauth.ps1](scripts/demo-easyauth.ps1) for the repeatable end-to-end demonstration.

## Step 5 - Test Easy Auth from Your PC

1. Follow [docs/lab3-direct-pc-testing.md](docs/lab3-direct-pc-testing.md) with a delegated lab-user token.
2. Prove missing-token `401`, authenticated-but-not-allowed `403`, and temporarily allowed `200` behavior.
3. Complete Step 10 immediately after the direct test so the temporary lab-user Object ID is removed while the Function managed identity remains allowed.

## Step 6 - Validate the Function Managed-Identity Path

1. Follow [docs/lab3-testing-and-verification.md](docs/lab3-testing-and-verification.md) for the B1/B2/B3/B4 matrix and the optional B6 authorization-mutation exercise.
2. Validate outcomes in [docs/evidence/scenario-ids.md](docs/evidence/scenario-ids.md).
3. Compare the deployment with [the current validation and drift register](docs/evidence/current-validation-and-drift.md). B6 remains optional while runtime propagation is under follow-up.

## Step 7 - Troubleshoot If Needed

Start with [Troubleshooting the identity flow](docs/lab3-managed-identity-bearer-token-flow.md#troubleshooting-the-identity-flow) for 401, 403, invalid audience, and missing managed identity issues. Then use [docs/troubleshooting.md](docs/troubleshooting.md).

## Step 8 - Clean Up Last

After every validation path is complete, run [Step 17 in the self-guided walkthrough](docs/lab3-walkthrough.md#step-17-clean-up-after-the-lab). It removes the resource group and the two lab app registrations.

## Common Questions

| Question | Answer |
| --- | --- |
| How do I deploy quickly? | Complete steps 1-2, then run `scripts/deploy.ps1` in Step 4. |
| Where are expected scenarios? | [docs/evidence/scenario-ids.md](docs/evidence/scenario-ids.md) |
| How do I configure Easy Auth? | [docs/lab3-walkthrough.md](docs/lab3-walkthrough.md) for portal and Bicep paths |
| How can I test Easy Auth without Function code? | [docs/lab3-direct-pc-testing.md](docs/lab3-direct-pc-testing.md) |
| Where is the Function bearer-token code? | [C# Function](solution/CallerFunctionApp/CallLogicApp.cs), [code walkthrough](docs/lab3-passwordless-managed-identity-easy-auth.md#code-flow), and [PowerShell example](scripts/call-logicapp-with-managed-identity.ps1) |
| Where is troubleshooting? | [docs/troubleshooting.md](docs/troubleshooting.md) |
| Where are the identity concepts explained? | [docs/lab3-managed-identity-bearer-token-flow.md](docs/lab3-managed-identity-bearer-token-flow.md) |
| How do I clean up resources? | [Step 17 in the self-guided walkthrough](docs/lab3-walkthrough.md#step-17-clean-up-after-the-lab) |
| Is Codespaces supported? | Yes, via `.devcontainer/devcontainer.json`. |

## Recommended Reading Order

1. [README.md](README.md)
2. [docs/lab3-managed-identity-bearer-token-flow.md](docs/lab3-managed-identity-bearer-token-flow.md)
3. [docs/lab3-walkthrough.md](docs/lab3-walkthrough.md)
4. [docs/lab3-direct-pc-testing.md](docs/lab3-direct-pc-testing.md)
5. [docs/lab3-testing-and-verification.md](docs/lab3-testing-and-verification.md)
6. [docs/evidence/findings.md](docs/evidence/findings.md)

## Optional Background Reading

- [documentation/architecture/background-apim-alternative.html](documentation/architecture/background-apim-alternative.html)
- [documentation/architecture/background-waf-caf-alignment.html](documentation/architecture/background-waf-caf-alignment.html)

These are architecture best-practice pages and are not required for Lab 3 completion.
They provide context related to earlier lab patterns and enterprise design choices.
