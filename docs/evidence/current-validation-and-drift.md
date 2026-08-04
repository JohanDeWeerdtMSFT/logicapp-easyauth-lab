# Current validation and drift register

Last validated: 2026-08-04

This file records the current live classroom baseline. When older evidence or assessment text conflicts with this file, revalidate the live deployment and update both the implementation and canonical learner docs.

## Validated baseline

| Item | Validated value | Evidence |
| --- | --- | --- |
| Logic App state | Running, workflow Enabled and Healthy | Azure resource and workflow management queries |
| Logic App ingress | Public | `publicNetworkAccess: Enabled` |
| Function App ingress | Public with Easy Auth `AllowAnonymous` | Lab-only test harness; live `authsettingsV2` |
| Storage ingress | Private | `publicNetworkAccess: Disabled` |
| Workflow method | `POST` | ZIP publisher live verification |
| Workflow trigger | `When_a_HTTP_request_is_received` | Live workflow definition |
| Easy Auth mode | `Return401` | Live `authsettingsV2` |
| Allowed audience | `api://786594a8-6b38-40cf-8c6b-d434b539dd46` | Live `authsettingsV2` and B1 token claim |
| Allowed principal | `82fc3b4f-e83c-42b4-9981-b3fb92ed25e1` | Function managed identity and live `authsettingsV2` |
| Anonymous Logic App call | HTTP 401 | Direct unsigned `POST` without a bearer token |
| B1 managed-identity call | HTTP 200 and workflow `status: ok` | Assertion-rich validator at 2026-08-04T19:38:10Z |
| B2 invalid token | HTTP 401 | Direct request with an invalid expired token |
| B3 wrong audience | HTTP 401 | Direct request with an Azure Resource Manager token |
| B6 unauthorized principal | HTTP 403 | Explicit parameter-file override at 2026-08-04T19:29:51Z; exact original principals restored afterward |
| B1 after restoration | HTTP 200 and authenticated workflow response | Canonical validator at 2026-08-04T19:38:10Z |
| Public classroom resource cleanup | No Logic App private endpoint or App Service private DNS zone; four storage private endpoints retained | Azure inventory after cleanup |
| Deployment history cleanup | No failed deployment records remain | Azure deployment inventory |

The B1 response reported the expected audience, tenant issuer, Function managed-identity object ID, scenario `B1`, and an authenticated Logic App principal. No bearer token was stored as evidence.

## Drift resolved

| Drift | Resolution |
| --- | --- |
| Private Logic App ingress described as mandatory | Public app ingress is now the classroom default; private ingress is opt-in with `-EnablePrivateAppNetworking`. |
| `AllowAnonymous` described as the secured baseline | Classroom Logic App now uses `Return401`; `AllowAnonymous` is an advanced manageability option. |
| Workflow route used `/triggers/manual/` | All canonical code and docs use `/triggers/When_a_HTTP_request_is_received/`. |
| Workflow deployed through an unsupported child-resource PUT | Workflow content is ZIP-deployed as a Standard Logic Apps project. |
| Logic App Entra registration lacked API identity | Deployment verifies `api://<client-id>` and creates the tenant service principal when missing. |
| B1 scenario was not propagated | Caller reads `{"scenario":"B1"}` and adds `scenario=B1` to the Logic App request. |
| Function error bodies reset 401/403 to HTTP 200 | Error responses now use the isolated-worker `WriteAsJsonAsync` overload with an explicit status code. |
| Function-inbound `Return401` required unprovisioned delegated consent | Function Easy Auth uses `AllowAnonymous` as a lab-only harness; the Logic App remains the strict security boundary under test. |
| Incremental public-mode deployment retained an older Logic App private endpoint | `scripts/deploy.ps1` explicitly removes the retained endpoint when private app networking is disabled. |
| B6 validator was coupled to `dev-westeurope.bicepparam` | B6 now captures, mutates, restores, and compares the exact live `authsettingsV2` principal list. |
| B1 validator asserted only HTTP 200 | B1 now asserts scenario propagation, audience, managed-identity object ID, and authenticated workflow principal. |
| Public classroom deployment retained dual app ingress | The retained Logic App private endpoint and App Service private DNS zone were removed; storage private endpoints remain. |
| Tracked `infra/main.json` represented the old topology | Regenerated from the current Bicep source and verified to include `enablePrivateAppNetworking`. |

## Historical material

Files under `guides/` and older generated evidence can describe previous private-network or `AllowAnonymous` experiments. They are not the canonical deployment procedure. Duplicated Lab 3 guides under `labs/` now point to the canonical files. The active order is:

1. [README](../../README.md)
2. [START HERE](../../START-HERE.md)
3. [Lab 3 walkthrough](../lab3-passwordless-managed-identity-easy-auth.md)
4. [Deployment and validation](../lab3-testing-and-verification.md)
5. [Troubleshooting](../troubleshooting.md)
