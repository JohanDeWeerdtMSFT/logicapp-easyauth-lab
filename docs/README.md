# Lab documentation

This directory is the single home for canonical learner documentation. Start with [START-HERE.md](../START-HERE.md) for the ordered path.

## Choose a walkthrough

| Learner goal | Start here | Supporting implementation |
| --- | --- | --- |
| Configure Easy Auth on an existing Logic App through Azure portal | [Portal-only setup for existing resources](lab3-walkthrough.md#portal-only-setup-for-existing-resources) | [Easy Auth Bicep module](../infra/modules/easyauth.bicep) |
| Deploy a new Logic App and Function App environment with Bicep | [Self-guided Lab 3 walkthrough](lab3-walkthrough.md#step-1-check-prerequisites) | [Main Bicep orchestration](../infra/main.bicep) and [deployment script](../scripts/deploy.ps1) |
| Test Logic App Easy Auth from your own PC | [Direct PC testing](lab3-direct-pc-testing.md) | Delegated `user_impersonation` scope, Azure CLI preauthorization, `401`/`403`/`200` validation, and authorization cleanup |
| Use a Function App to acquire a bearer token and call the Logic App | [Managed-identity implementation](lab3-passwordless-managed-identity-easy-auth.md#code-flow) | [C# Function](../solution/CallerFunctionApp/CallLogicApp.cs), [minimal PowerShell example](../scripts/call-logicapp-with-managed-identity.ps1), and [validation script](../scripts/demo-easyauth.ps1) |

## Canonical learner documents

| Document | Purpose |
| --- | --- |
| [Identity and Easy Auth concepts](lab3-managed-identity-bearer-token-flow.md) | Beginner-friendly explanation of Entra ID, managed identity, tokens, audience, scopes, authentication, and authorization |
| [Self-guided Lab 3 walkthrough](lab3-walkthrough.md) | Portal configuration for existing resources and complete Bicep deployment for a new environment |
| [Direct PC testing](lab3-direct-pc-testing.md) | Test Easy Auth independently of Function code and restore the production-style allow-list afterward |
| [Managed-identity implementation](lab3-passwordless-managed-identity-easy-auth.md) | Architecture, application settings, and C#/PowerShell bearer-token patterns |
| [Testing and verification](lab3-testing-and-verification.md) | Function-key invocation, managed-identity proof, token-claim assertions, run history, and negative tests |
| [Troubleshooting](troubleshooting.md) | Diagnose authentication, authorization, routing, deployment, storage, and networking failures |
| [Private networking and CI/CD](07-private-networking-and-cicd.md) | Optional advanced private-ingress design and deployment-executor requirements |

## Maintainer evidence

Files under [evidence/](evidence/) record the validated baseline, expected scenario IDs, and known drift. They support maintenance and review; they are not a substitute for the learner walkthroughs.

Sanitized screenshots used by the direct-PC walkthrough are stored under [images/](images/).
