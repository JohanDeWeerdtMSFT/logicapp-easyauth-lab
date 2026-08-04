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
- A machine that can reach the deployment endpoints. The Logic App is private when `-DeployFuncCallerDemo` is enabled, so direct tests of the Logic App require VNet routing and private DNS. The caller Function App performs the normal end-to-end test from inside the VNet.

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

## 3. Deploy the workflow

Deploy [the workflow definition](../src/httpTriggerWorkflow/workflow.json) through the Azure Resource Manager API:

```powershell
./scripts/deploy-workflow.ps1 `
  -LogicAppName $logicAppName `
  -ResourceGroupName $resourceGroup
```

The script prints this unsigned invoke URL:

```text
https://<logic-app-host>/api/workflows/httpTriggerWorkflow/triggers/manual/invoke?api-version=2022-05-01
```

## 4. Deploy the caller Function code

The infrastructure already configures the same unsigned URL and audience. Deploy the code and verify the settings:

```powershell
$logicAppUrl = "https://$logicAppHost/api/workflows/httpTriggerWorkflow/triggers/manual/invoke?api-version=2022-05-01"

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
| `LOGIC_APP_URL` | Unsigned `/api/workflows/httpTriggerWorkflow/...` URL |
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

## 6. Run the successful managed-identity test

```powershell
$response = Invoke-RestMethod `
  -Method Post `
  -Uri "https://$functionAppHost/api/CallLogicApp" `
  -ContentType 'application/json' `
  -Body '{"scenario":"B1"}'

$response | ConvertTo-Json -Depth 10
```

Expected: HTTP 200 with `status` equal to `success` and a `tokenClaims` object.

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

Application Insights query:

```kusto
traces
| where timestamp > ago(30m)
| where message has_any ("Bearer token acquired", "Token claims inspected locally", "Logic App response")
| project timestamp, message, severityLevel, operation_Id
| order by timestamp asc
```

Directly calling the unsigned private Logic App endpoint without a bearer token should not create an authorized run. From a machine with private endpoint reachability:

```powershell
try {
  Invoke-WebRequest -Method Post -Uri $logicAppUrl -ContentType 'application/json' -Body '{}'
} catch {
  [int]$_.Exception.Response.StatusCode
}
```

Expected in strict `Return401` mode: `401`. In the optional `AllowAnonymous` manageability mode, use the scenario matrix and workflow evidence to distinguish platform behavior; do not interpret network timeouts as authentication results.

## 9. Diagnose HTTP 401

HTTP 401 means authentication failed before the workflow accepted the request. Common causes are a missing token, wrong audience, wrong issuer, invalid signature, or expired token.

### Reproduce wrong audience safely

Temporarily set the caller to request a token for Azure Resource Manager:

```powershell
az functionapp config appsettings set `
  --name $functionAppName `
  --resource-group $resourceGroup `
  --settings LOGIC_APP_AUDIENCE='https://management.azure.com'

az functionapp restart --name $functionAppName --resource-group $resourceGroup
```

Invoke the caller again. Expected: the caller reports downstream HTTP 401 and no successful workflow run appears.

Restore immediately:

```powershell
az functionapp config appsettings set `
  --name $functionAppName `
  --resource-group $resourceGroup `
  --settings LOGIC_APP_AUDIENCE="api://$logicAppClientId"

az functionapp restart --name $functionAppName --resource-group $resourceGroup
```

Confirm the next invocation returns HTTP 200.

## 10. Diagnose HTTP 403

HTTP 403 means Easy Auth accepted the token as authenticated but the caller failed the authorization policy. In this lab, compare the token `oid` and Function principal ID with `allowedPrincipals`.

### Reproduce unauthorized principal safely

Save the current auth configuration before changing it:

```powershell
$authBackup = az rest --method get --uri $authUri | ConvertFrom-Json
$authBackup | ConvertTo-Json -Depth 100 | Set-Content "$env:TEMP\logicapp-authsettingsv2-backup.json"
```

The preferred lab exercise is to redeploy with an intentionally different caller principal in an isolated test environment. If you temporarily remove the current caller from `allowedPrincipals`, expect the valid managed-identity token to receive HTTP 403. Restore the Bicep-defined configuration immediately by rerunning `scripts/deploy.ps1` with the original parameters.

After restoration, verify:

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
| 403 | Authorization | Token `oid` versus `allowedPrincipals` | Redeploy the original Bicep parameters so the caller principal is allow-listed. |
| 404 or 405 | Route/method | Unsigned URL and `POST` method | Use `/api/workflows/httpTriggerWorkflow/triggers/manual/invoke?api-version=2022-05-01`. |
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