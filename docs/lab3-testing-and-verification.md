# Lab 3 deployment, testing, and verification

Use this guide to deploy the active Lab 3 assets and prove that the caller Function App reaches the Logic App Standard workflow by using its system-assigned managed identity and a Microsoft Entra access token.

The required learner path does not use a Logic Apps SAS callback URL. The invoke URL must not contain `sp`, `sv`, or `sig` query parameters.

## What you will prove

By the end of this guide, you will have evidence that:

1. The Function App has a system-assigned managed identity.
2. The Function App requests a token for `api://<logic-app-client-id>/.default`.
3. The token audience, issuer, object ID, caller app claim, and expiry have the expected values.
4. Easy Auth accepts the valid token and creates a Logic App run.
5. Easy Auth rejects a token with the wrong audience with HTTP 401.
6. Easy Auth rejects an authenticated but unauthorized principal with HTTP 403.

Microsoft references:

- [App Service authentication and authorization](https://learn.microsoft.com/azure/app-service/overview-authentication-authorization)
- [Microsoft identity platform access-token claims](https://learn.microsoft.com/entra/identity-platform/access-token-claims-reference)
- [Managed identities for Azure resources](https://learn.microsoft.com/entra/identity/managed-identities-azure-resources/overview)
- [Secure access and data in Azure Logic Apps](https://learn.microsoft.com/azure/logic-apps/logic-apps-securing-a-logic-app)

## Prerequisites

- Azure CLI, PowerShell 7, .NET 8 SDK, and Azure Functions Core Tools 4.
- An Azure subscription where you can create resources and assign Azure RBAC roles (for example, Owner, or Contributor plus User Access Administrator/RBAC Administrator).
- Permission to create or use two Microsoft Entra app registrations:
  - Logic App API registration: used as the token audience.
  - Caller Function App registration: used by Easy Auth on the caller endpoint.
- A machine that can reach the public App Service deployment endpoints. The classroom path keeps both app endpoints public and protects the Logic App with Easy Auth `Return401`.

The private Lab 3 deployment creates private endpoints and VNet-linked DNS zones for the shared storage account's Blob, Queue, Table, and File services. These endpoints are required for both hosts to start when storage public network access is disabled. See [Deploy Standard logic apps with private storage](https://learn.microsoft.com/azure/logic-apps/deploy-single-tenant-logic-apps-private-storage-account).

The deployment script verifies that the Logic App registration has its default Application ID URI and tenant service principal. Those values are required before managed identity can request `api://<logic-app-client-id>/.default`. The caller registration configures Easy Auth on the lab test harness.

> [!IMPORTANT]
> Do not log, paste, upload, or take screenshots of a complete bearer token. A bearer token is a credential. The sample caller decodes its token payload locally and reports only selected non-secret claims. Reading claims does not validate the token signature; Easy Auth performs signature, issuer, audience, lifetime, and policy enforcement.

## 1. Configure deployment values

Copy the environment template and set the subscription ID:

```powershell
Copy-Item .env.example .env
```

At minimum, replace `AZURE_SUBSCRIPTION_ID` in `.env`. Keep these values available for the commands below:

```powershell
$logicAppClientId = '<logic-app-app-registration-client-id>'
$callerClientId = '<caller-function-app-registration-client-id>'
$tenantId = '<tenant-id>'
$resourceGroup = 'rg-la-easyauth-lab-dev'
```

The deployment script resolves the subscription in this order:

1. `-SubscriptionId`
2. Process environment variable `AZURE_SUBSCRIPTION_ID`
3. `AZURE_SUBSCRIPTION_ID` in the repository `.env` file

## 2. Preview and deploy infrastructure

Sign in and preview the Bicep deployment:

```powershell
az login --tenant $tenantId

./scripts/deploy.ps1 `
  -EntraAppClientId $logicAppClientId `
  -EntraAppTenantId $tenantId `
  -DeployFuncCallerDemo `
  -FuncCallerEntraClientId $callerClientId `
  -WhatIf
```

Review the changes, then deploy without `-WhatIf`:

```powershell
./scripts/deploy.ps1 `
  -EntraAppClientId $logicAppClientId `
  -EntraAppTenantId $tenantId `
  -DeployFuncCallerDemo `
  -FuncCallerEntraClientId $callerClientId
```

Record these outputs:

- Logic App name and hostname
- Caller Function App name and hostname
- Caller principal ID

Set them for later commands:

```powershell
$logicAppName = '<logic-app-name-from-output>'
$logicAppHost = '<logic-app-hostname-from-output>'
$functionAppName = '<caller-function-app-name-from-output>'
$functionAppHost = '<caller-function-app-hostname-from-output>'
$functionPrincipalId = '<caller-principal-id-from-output>'
```

## 3. Deploy and verify the workflow artifact

Bicep provisions the Logic App infrastructure but does not publish Standard Logic App workflow content. Publish [the workflow project](../src) as a ZIP artifact from a machine that can resolve and reach the Logic App SCM endpoint:

```powershell
./scripts/deploy-workflow.ps1 `
  -SubscriptionId $subscriptionId `
  -ResourceGroupName $resourceGroup `
  -LogicAppName $logicAppName
```

The ZIP contains `host.json` and the `httpTriggerWorkflow` directory at its root. If Azure CLI reports an unusable App Service account, refresh the deployment token and rerun the command:

```powershell
az login --tenant $tenantId --scope https://appservice.azure.com/.default
```

For the optional private-ingress mode, run the publisher from a VNet-connected developer machine or self-hosted agent with private DNS for both the app and SCM hostnames. Do not enable public storage to deploy workflow content.

The publisher verifies that the deployed HTTP trigger uses the source method. You can also verify that the workflow is enabled and healthy through the management API:

```powershell
$subscriptionId = az account show --query id --output tsv
$workflowUri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Web/sites/$logicAppName/workflows/httpTriggerWorkflow?api-version=2023-12-01"

az rest --method get --uri $workflowUri `
  --query "properties.{state:flowState,health:health.state}" `
  --output json
```

Expected: `state` is `Enabled`, `health` is `Healthy`, and the publisher reports trigger method `POST`. The unsigned invoke URL is:

```text
https://<logic-app-host>/api/httpTriggerWorkflow/triggers/When_a_HTTP_request_is_received/invoke?api-version=2022-05-01
```

## 4. Deploy the caller Function code

The infrastructure already configures the same unsigned URL and audience. Deploy the code and verify the settings:

```powershell
$logicAppUrl = "https://$logicAppHost/api/httpTriggerWorkflow/triggers/When_a_HTTP_request_is_received/invoke?api-version=2022-05-01"

./solution/deploy.ps1 `
  -FunctionAppName $functionAppName `
  -ResourceGroupName $resourceGroup `
  -LogicAppUrl $logicAppUrl `
  -LogicAppAudience "api://$logicAppClientId" `
  -TenantId $tenantId
```

> [!NOTE]
> ZIP deployment needs network access to the target Function App deployment endpoint. If you later make that app private, run this step from a developer machine or self-hosted agent with the required route and DNS resolution.

## 5. Verify configuration before calling

### Managed identity

```powershell
$actualPrincipalId = az functionapp identity show `
  --name $functionAppName `
  --resource-group $resourceGroup `
  --query principalId `
  --output tsv

$actualPrincipalId
```

Expected: a GUID equal to `$functionPrincipalId`.

### Caller application settings

```powershell
az functionapp config appsettings list `
  --name $functionAppName `
  --resource-group $resourceGroup `
  --query "[?name=='LOGIC_APP_URL' || name=='LOGIC_APP_AUDIENCE' || name=='WEBSITE_AUTH_AAD_ALLOWED_TENANTS'].{name:name,value:value}" `
  --output table
```

Expected:

| Setting | Expected value |
| --- | --- |
| `LOGIC_APP_URL` | Unsigned `/api/httpTriggerWorkflow/...` URL |
| `LOGIC_APP_AUDIENCE` | `api://<logic-app-client-id>` |
| `WEBSITE_AUTH_AAD_ALLOWED_TENANTS` | Lab tenant ID |

### Logic App Easy Auth policy

```powershell
$subscriptionId = az account show --query id --output tsv
$authUri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Web/sites/$logicAppName/config/authsettingsv2?api-version=2023-12-01"

az rest --method get --uri $authUri `
  --query "properties.{enabled:platform.enabled,action:globalValidation.unauthenticatedClientAction,audiences:identityProviders.azureActiveDirectory.validation.allowedAudiences,principals:identityProviders.azureActiveDirectory.validation.defaultAuthorizationPolicy.allowedPrincipals.identities}" `
  --output json
```

Expected:

- `enabled` is `true`.
- `audiences` contains `api://<logic-app-client-id>`.
- `principals` contains `$functionPrincipalId`.

### Storage private connectivity

```powershell
az network private-endpoint list `
  --resource-group $resourceGroup `
  --query "[?contains(name, 'pe-laeasyauthlab')].{name:name,group:privateLinkServiceConnections[0].groupIds[0],state:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status}" `
  --output table

az network private-dns zone list `
  --resource-group $resourceGroup `
  --query "[?contains(name, 'privatelink')].name" `
  --output table
```

Expected: approved storage private endpoints and linked private DNS zones for `blob`, `queue`, `table`, and `file`. The Logic App `sites` private endpoint is optional and is not required for the classroom path. Do not proceed while either host reports `Unable to access AzureWebJobsStorage`.

## 6. Run the successful managed-identity test

For a presentation-ready proof, run the demo script. It first proves that the Logic App rejects a request without a bearer token, then invokes the Function and validates the managed-identity token claims and authenticated workflow principal:

```powershell
./scripts/demo-easyauth.ps1 `
  -SubscriptionId $subscriptionId `
  -ResourceGroupName $resourceGroup `
  -LogicAppName $logicAppName `
  -FunctionAppName $functionAppName `
  -LogicAppClientId $logicAppClientId `
  -TenantId $tenantId
```

Expected: `passed` is `true`, `unauthenticatedLogicAppStatus` is `401`, `authenticatedFunctionStatus` is `200`, and every assertion is `true`. The script never prints the Function key or bearer token.

To perform the same successful call manually:

```powershell
$functionKey = az functionapp keys list `
  --resource-group $resourceGroup `
  --name $functionAppName `
  --query functionKeys.default `
  --output tsv

$response = Invoke-RestMethod `
  -Method Post `
  -Uri "https://$functionAppHost/api/CallLogicApp" `
  -Headers @{ 'x-functions-key' = $functionKey } `
  -ContentType 'application/json' `
  -Body '{"scenario":"B1"}'

$response | ConvertTo-Json -Depth 10
Remove-Variable functionKey
```

Expected: HTTP 200 with `status` equal to `success` and a `tokenClaims` object. The Function key limits access to the public lab harness; the protected downstream assertion is its managed-identity call to the strict Logic App. Keep the key in memory and never include it in evidence.

## 7. Validate the access-token claims

Compare the returned claim metadata with the deployment values:

| Claim | Expected value | Why it matters |
| --- | --- | --- |
| `audience` | `api://<logic-app-client-id>` | Proves the token was minted for the receiving API, not another Azure resource. |
| `issuer` | Your tenant's Entra issuer | Proves which tenant issued the token. |
| `objectId` | Function App managed identity principal ID | Identifies the calling service principal. |
| `callerAppId` | Managed-identity client identifier from the issued token | Identifies the client represented in `azp` or `appid`, depending on token version. |
| `expiresOn` | A future timestamp | Confirms the token was current when acquired. |

Run these comparisons:

```powershell
$response.tokenClaims.audience -eq "api://$logicAppClientId"
$response.tokenClaims.objectId -eq $functionPrincipalId
[DateTimeOffset]$response.tokenClaims.expiresOn -gt [DateTimeOffset]::UtcNow
```

Expected: all three expressions return `True`.

This inspects the claims students need to understand without exposing the bearer token. The successful request through Easy Auth is the evidence that the platform accepted the token's signature, issuer, audience, lifetime, and authorized principal.

## 8. Validate that Easy Auth is working

Use all four signals, not only the caller's HTTP status:

1. The caller returns HTTP 200.
2. The response reports the expected token audience and object ID.
3. A new `httpTriggerWorkflow` run appears at the same time in Logic App run history.
4. Application Insights contains the caller messages `Bearer token acquired`, `Token claims inspected locally`, and `Logic App response: HTTP 200`.

The deployed Easy Auth policy keeps `Return401` for trigger paths and excludes only `/runtime/*`, which allows the portal run-history blade to use the Logic Apps runtime authorization. If the blade reports HTTP 401, verify:

```powershell
az rest --method get --uri $authUri `
  --query "properties.globalValidation.{action:unauthenticatedClientAction,excludedPaths:excludedPaths}" `
  --output json
```

Expected: `action` is `Return401` and `excludedPaths` contains `/runtime/*`.

Application Insights query:

```kusto
traces
| where timestamp > ago(30m)
| where message has_any ("Bearer token acquired", "Token claims inspected locally", "Logic App response")
| project timestamp, message, severityLevel, operation_Id
| order by timestamp asc
```

Directly calling the unsigned public Logic App endpoint without a bearer token should not create an authorized run:

```powershell
try {
  Invoke-WebRequest -Method Post -Uri $logicAppUrl -ContentType 'application/json' -Body '{}'
} catch {
  [int]$_.Exception.Response.StatusCode
}
```

Expected in the classroom `Return401` mode: `401`. `AllowAnonymous` is an optional portal-manageability investigation and is not the secured learner baseline.

## 9. Diagnose HTTP 401

HTTP 401 means authentication failed before the workflow accepted the request. Common causes are a missing token, wrong audience, wrong issuer, invalid signature, or expired token.

### Reproduce wrong audience safely

Acquire an Azure Resource Manager token locally and send it directly to the Logic App. Keep the token in memory and record only the HTTP status:

```powershell
$wrongAudienceToken = az account get-access-token `
  --resource 'https://management.azure.com/' `
  --query accessToken `
  --output tsv

try {
  $result = Invoke-WebRequest `
    -Method Post `
    -Uri "$logicAppUrl&scenario=B3" `
    -Headers @{ Authorization = "Bearer $wrongAudienceToken" } `
    -ContentType 'application/json' `
    -Body '{"scenario":"B3"}' `
    -SkipHttpErrorCheck

  [int]$result.StatusCode
}
finally {
  Remove-Variable wrongAudienceToken -ErrorAction SilentlyContinue
}
```

Expected: `401` and no successful workflow run for scenario B3. Do not print or save `$wrongAudienceToken`. This direct procedure avoids managed-identity token caching in the running Function process.

## 10. Diagnose HTTP 403

HTTP 403 means Easy Auth accepted the token as authenticated but the caller failed the authorization policy. In this lab, compare the token `oid` and Function principal ID with `allowedPrincipals`.

### Reproduce unauthorized principal safely

Run this exercise only in an isolated lab resource group. The canonical validator gets the Logic App's own managed identity object ID, captures the complete live `authsettingsV2` policy, changes only `allowedPrincipals`, verifies HTTP 403, and restores the captured policy in a `finally` block:

```powershell
./scripts/validate.ps1 `
  -SubscriptionId $subscriptionId `
  -ResourceGroupName $resourceGroup `
  -LogicAppName $logicAppName `
  -FunctionAppName $functionAppName `
  -LogicAppClientId $logicAppClientId `
  -TenantId $tenantId `
  -RunAuthorizationMutation
```

Expected: B6 returns HTTP 403 because the managed-identity token is valid but its `oid` is not the temporary allow-listed object ID.

Easy Auth runtime enforcement lags behind the ARM resource. The validator therefore waits for the *observed* HTTP 403, not only for ARM to return the temporary principal. If bounded retries are not enough, it restarts the Logic App once and continues retrying. It then restores the captured policy in a `finally` block, waits for ARM to return the original principal list, and proves restoration with a `B6-restored` request that must return HTTP 200 with the original Function managed identity principal. You can independently confirm the restored value:

```powershell
az rest --method get --uri $authUri `
  --query "properties.identityProviders.azureActiveDirectory.validation.defaultAuthorizationPolicy.allowedPrincipals.identities" `
  --output json
```

Expected: the Function App principal ID is present and the next caller invocation returns HTTP 200.

## 11. Failure triage

| Symptom | Layer | First check | Typical fix |
| --- | --- | --- | --- |
| 401 | Authentication | `aud`, issuer/tenant, expiry, and bearer header | Restore `LOGIC_APP_AUDIENCE`, tenant ID, and Easy Auth allowed audiences. |
| 403 | Authorization | Token `oid` versus `allowedPrincipals` | Restore the captured Easy Auth policy or redeploy the original Bicep parameters. |
| 404 or 405 | Route/method | Workflow and trigger names plus `POST` method | Use `/api/httpTriggerWorkflow/triggers/When_a_HTTP_request_is_received/invoke?api-version=2022-05-01`. |
| Timeout or DNS error | Network | Resolve the Logic App hostname from the caller's reachable network | Check VNet integration, private endpoint, private DNS link, and route controls. |
| Credential unavailable | Caller identity | Function App system-assigned identity | Enable or redeploy the managed identity. |
| 200 but no run | Workflow/runtime | Workflow name, deployment, and run history time | Redeploy the workflow and correlate timestamps in Application Insights. |

Continue with [the detailed troubleshooting guide](troubleshooting.md) when the first check does not isolate the cause.

## 12. Evidence checklist

Capture values, not secrets:

- [ ] Infrastructure deployment output showing Logic App name, caller name, hostname, and principal ID.
- [ ] Easy Auth query showing enabled platform, allowed audiences, and allowed principal.
- [ ] Successful caller response with selected `tokenClaims`; redact other identifiers if required by your organization.
- [ ] Three `True` claim comparisons.
- [ ] Application Insights trace correlation for token acquisition and HTTP 200.
- [ ] Logic App run-history entry with matching timestamp.
- [ ] 401 wrong-audience result and successful restoration.
- [ ] 403 unauthorized-principal result in an isolated environment and successful restoration.

Never include a complete access token, SAS signature, client secret, storage key, or connection string in evidence.

## 13. Run the automated scenario matrix

After the manual learning steps, run the canonical validator. It retrieves the Function key through the Azure management plane and keeps it in memory. B6 captures the live Easy Auth policy, changes only the captured `allowedPrincipals` value, restores the complete captured policy, and compares the restored principal list with the original.

```powershell
./scripts/validate.ps1 `
  -SubscriptionId $subscriptionId `
  -ResourceGroupName $resourceGroup `
  -LogicAppName $logicAppName `
  -FunctionAppName $functionAppName `
  -LogicAppClientId $logicAppClientId `
  -TenantId $tenantId `
  -RunAuthorizationMutation
```

Expected: B1 returns `200`, B2/B3/B4 return `401`, B6 returns `403`, and `B6-restored` returns `200`. The command exits nonzero if any expected status or assertion fails.

### Storage: private network access and Shared Key authorization are separate controls

The shared storage account uses two independent settings:

- `publicNetworkAccess: Disabled` keeps storage ingress private. The deployment asserts this value for the caller-demo classroom path.
- `allowSharedKeyAccess: true` keeps Shared Key authorization available, which Logic App Standard on a Workflow Service Plan (WS1) still requires. This is not the same as how the application authenticates: `AzureWebJobsStorage` remains identity-based.

`scripts/deploy.ps1` reads the *effective* storage account settings after deployment. If an inherited Azure Policy `Modify` assignment has rewritten `allowSharedKeyAccess` to `false`, the deployment fails with actionable guidance instead of reporting success. See [Troubleshooting](troubleshooting.md) and Microsoft Learn: [Set up managed identity access to your storage account](https://learn.microsoft.com/azure/logic-apps/create-single-tenant-workflows-azure-portal#set-up-managed-identity-access-to-your-storage-account).

### Run the focused helper tests

```powershell
Invoke-Pester ./labs/lab3-bearer-token/tests
```
