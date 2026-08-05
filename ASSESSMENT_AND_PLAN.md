# Assessment and improvement plan

Last updated: 2026-08-05

## 1. Executive summary

The active Lab 3 presentation path is implemented and live-validated. It teaches a Function App calling a Logic App Standard workflow with a Microsoft Entra access token acquired through the Function's system-assigned managed identity. `scripts/demo-easyauth.ps1` provides a repeatable proof that the uncredentialed Logic App call is rejected and the managed-identity call is accepted.

Current classroom baseline:

- Function App endpoint: public, with a Function-key-protected HTTP trigger and Easy Auth `AllowAnonymous` behind that lab guard.
- Logic App endpoint: public, with Easy Auth `Return401`, audience validation, and `allowedPrincipals`.
- Shared storage: private, with Blob, Queue, Table, and File private endpoints and managed-identity RBAC.
- Optional private Logic App ingress: enabled only with `-EnablePrivateAppNetworking`.
- Workflow content: deployed as a Standard Logic Apps ZIP project.

The earlier private-first assessment is superseded by this baseline. Private ingress remains an advanced extension documented in [Private networking and CI/CD](docs/07-private-networking-and-cicd.md).

## 2. Current lab flow

1. Read [README.md](README.md) and [START-HERE.md](START-HERE.md).
2. Learn the identity flow in [docs/lab3-managed-identity-bearer-token-flow.md](docs/lab3-managed-identity-bearer-token-flow.md).
3. Review the walkthrough in [docs/lab3-passwordless-managed-identity-easy-auth.md](docs/lab3-passwordless-managed-identity-easy-auth.md).
4. Preview and deploy infrastructure with `scripts/deploy.ps1`.
5. Publish workflow content with `scripts/deploy-workflow.ps1`.
6. Publish the caller Function with `solution/deploy.ps1`.
7. Run the manual and automated checks in [docs/lab3-testing-and-verification.md](docs/lab3-testing-and-verification.md).
8. Use [docs/troubleshooting.md](docs/troubleshooting.md) for 401, 403, routing, and storage failures.

## 3. Target learning journey

The implemented learning journey is:

1. Understand Easy Auth, managed identity, access tokens, audience, scope, authentication, and authorization.
2. Configure two Entra app registrations and the Logic App Application ID URI.
3. Deploy public classroom app endpoints and private runtime storage.
4. Publish a `POST` workflow through the supported ZIP deployment path.
5. Invoke the Function test harness and observe its managed-identity call to the protected Logic App.
6. Validate selected token claims without exposing the token.
7. Reproduce B2/B3/B4 authentication failures and B6 authorization failure.
8. Correlate Function traces with Logic App run history.
9. Treat private app ingress and private CI/CD executors as an optional advanced exercise.

## 4. Findings

| Priority | Original finding | Current resolution | Evidence |
| --- | --- | --- | --- |
| Critical | Workflow child-resource PUT did not publish Standard workflow content | ZIP project deployment implemented | `scripts/deploy-workflow.ps1`; live `POST` verification |
| Critical | Subscription and caller-demo inputs were not reproducible | Explicit parameters and `.env` fallback implemented | `scripts/deploy.ps1` |
| High | Scenario body did not correlate with the workflow run | Caller propagates `scenario` in the query string | `CallLogicApp.cs`; B1 assertions |
| High | Audience documentation did not match Easy Auth | `api://<logic-app-client-id>` aligned across Entra, caller, and Easy Auth | B1 token claim and live `authsettingsV2` |
| High | B6 could not safely mutate and restore authorization | Restoration is safe, but runtime propagation remains open because the 2026-08-05 mutation returned HTTP 200 after ARM reported the temporary principal | Follow-up issue; original principal restoration confirmed |
| High | Public Function harness could proxy anonymous internet calls | HTTP trigger now requires a Function key; teardown and production-hardening warnings added | `CallLogicApp.cs`; canonical learner docs |
| High | WS1 storage account disabled required key access | Bicep requests Shared Key capability, but inherited `StorageAccount_DisableLocalAuth_Modify` policy keeps the effective value disabled | Follow-up issue; live policy and storage state inspected |
| High | Private ingress blocked normal workstation publishing | Public app ingress is the classroom default | `enablePrivateAppNetworking=false` |
| Medium | Private networking and CI/CD caveats were fragmented | Dedicated guide added | `docs/07-private-networking-and-cicd.md` |
| Medium | Duplicate Lab 3 procedures drifted | Duplicate files now point to canonical guides | `labs/lab3-bearer-token/docs/` |

PR 6 is complete and the presentation demo is not blocked. Two high-priority operational findings remain for a dedicated follow-up issue and Copilot PR.

## 5. Missing explanations for beginners

The active documentation now explains:

- Easy Auth and App Service authentication.
- Microsoft Entra app registrations and service principals.
- Function system-assigned managed identity.
- Access-token audience, resource, and `/.default` scope.
- Authentication (`401`) versus authorization (`403`).
- `allowedPrincipals` and why the Function object ID is used.
- Why the learner flow uses an unsigned endpoint plus Entra bearer token instead of a SAS-signed callback URL.
- Why private storage and public app ingress are separate network decisions.

Canonical concept source: [docs/lab3-managed-identity-bearer-token-flow.md](docs/lab3-managed-identity-bearer-token-flow.md).

## 6. Private networking and CI/CD caveats

The classroom path keeps app ingress public and storage private. This allows workstation, GitHub-hosted, and Microsoft-hosted Azure DevOps publishing while retaining identity enforcement on the Logic App.

Private Logic App ingress is opt-in. It requires:

- Route and DNS access to both the app and SCM hostnames.
- `privatelink.azurewebsites.net` records for the app and `.scm` host.
- A VNet-connected developer machine or self-hosted agent for ZIP deployment and direct validation.

Public-mode deployment removes a retained Logic App private endpoint and App Service private DNS zone because incremental ARM deployment does not delete omitted resources.

Authoritative details and executor matrix: [docs/07-private-networking-and-cicd.md](docs/07-private-networking-and-cicd.md).

## 7. Proposed repository changes

All PR 6 implementation changes are complete:

| File or area | Status | Result |
| --- | --- | --- |
| `README.md`, `START-HERE.md` | Done | Linear beginner-first path |
| `scripts/deploy.ps1` | Done | Reproducible public/private mode, Entra preflight, safe What-If, cleanup |
| `scripts/deploy-workflow.ps1` | Done | Supported ZIP publisher and live method check |
| `scripts/validate.ps1` | Done | B1 assertions and B2/B3/B4/B6 matrix with restoration |
| `infra/main.bicep`, `infra/main.json` | Done | Synchronized source and tracked deployment artifact |
| `docs/lab3-testing-and-verification.md` | Done | Canonical SAS-free validation procedure |
| `docs/07-private-networking-and-cicd.md` | Done | Private-ingress and CI/CD extension |
| Duplicate Lab 3 docs | Done | Canonical pointers replace duplicate procedures |

## 8. Copilot implementation plan

| Phase | Name | Status | Evidence |
| --- | --- | --- | --- |
| 1 | Documentation structure | Done | README and START-HERE |
| 2 | Identity and Easy Auth explanation | Done | Concept and walkthrough guides |
| 3 | Deployment guidance | Done | Infrastructure, workflow, and Function deployment scripts |
| 4 | Validation and troubleshooting | Done | Automated scenario matrix and canonical guide |
| 5 | Private networking and CI/CD caveats | Done | Dedicated networking guide |
| 6 | Final review | Done | Builds, diagnostics, live scenarios, and drift checks |

## 9. Acceptance criteria for the improved lab

- [x] A beginner can understand the scenario before deploying.
- [x] Prerequisites include resource creation, role-assignment permission, tenant ID, and both client IDs.
- [x] Easy Auth and Entra concepts are explained before implementation.
- [x] The Function-to-Logic-App token flow is documented.
- [x] The mandatory learner path uses no SAS signature.
- [x] Workflow content deploys through a supported Standard Logic Apps ZIP package.
- [x] B1 asserts scenario, audience, issuer, managed-identity object ID, and authenticated workflow principal.
- [x] B2/B3/B4 return `401` and B6 returns `403`.
- [x] B6 restores the captured live Easy Auth policy and compares the original principal list.
- [x] Public classroom and optional private-ingress modes are distinct.
- [x] Storage remains private in the classroom path.
- [x] Canonical documentation is lint-clean and duplicate procedures are removed.

## 10. Open questions

No open question blocks the Easy Auth presentation demo.

Required follow-up work:

- Make deployment detect and explain the inherited storage-policy conflict with WS1 hosting requirements.
- Make B6 validate Easy Auth runtime enforcement and prove restoration with a successful B1 request.

Future work outside PR 6:

- Optional APIM production-extension lab.
- Optional strict Function-inbound authentication exercise with delegated consent or app roles.
- Automated CI workflow for Bicep, PowerShell, .NET, Markdown, and scenario validation.
