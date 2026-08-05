# Lab 3 Instructor Walkthrough: Easy Auth from Start to Finish

Use this page while presenting the environment to an attendee. Complete the steps in order. Each step includes what to do, what to show in the portal, and what to explain.

## What the attendee will learn

By the end of the walkthrough, the attendee should be able to explain this flow:

1. The Function App uses its system-assigned managed identity.
2. Microsoft Entra ID issues an access token for the Logic App API audience.
3. The Function sends the token in the `Authorization: Bearer` header.
4. Easy Auth validates the token and checks the caller against `allowedPrincipals`.
5. The Logic App workflow runs and appears in run history.

The Function-to-Logic-App call uses no client secret and no SAS-signed callback URL.

## Step 1: Check prerequisites

You need:

- Azure CLI, PowerShell 7, .NET 8, and Bicep.
- Permission to create Azure resources and role assignments: Owner, or Contributor plus User Access Administrator/RBAC Administrator.
- Permission to create Microsoft Entra app registrations. Application Developer is sufficient when tenant policy allows it.
- A subscription where the lab resources can be created.

Show the attendee that no application secret is required. The Function key protects only the public learner-to-Function test endpoint; managed identity protects the downstream Function-to-Logic-App call.

Official references:

- [Register an application in Microsoft Entra ID](https://learn.microsoft.com/entra/identity-platform/quickstart-register-app)
- [Managed identities for Azure resources](https://learn.microsoft.com/entra/identity/managed-identities-azure-resources/overview)
- [App Service authentication and authorization](https://learn.microsoft.com/azure/app-service/overview-authentication-authorization)

## Step 2: Clone the repository and sign in

```powershell
git clone https://github.com/JohanDeWeerdtMSFT/logicapp-easyauth-lab.git
Set-Location logicapp-easyauth-lab

az login --tenant '<tenant-id>'
az account set --subscription '<subscription-id>'
az account show --query '{subscription:name, subscriptionId:id, tenantId:tenantId}' --output table
```

Explain:

- The tenant contains the identity objects.
- The subscription contains the Azure resources.
- The tenant and subscription must match the environment being deployed.

## Step 3: Set the walkthrough variables

Use one PowerShell session for the rest of the walkthrough:

```powershell
$subscriptionId = '<subscription-id>'
$tenantId = '<tenant-id>'
$location = 'westeurope'
$environmentName = 'dev'
$resourceGroup = "rg-la-easyauth-lab-$environmentName"

$logicAppRegistrationName = "la-easyauth-lab-$environmentName-api"
$callerRegistrationName = "la-easyauth-lab-$environmentName-caller"
```

For the validated demo environment, the values are:

```powershell
$subscriptionId = '6851693c-0b74-4462-8da8-cd498b088827'
$tenantId = '00922812-791e-41c8-a99e-45c3ed784cf5'
$location = 'westeurope'
$environmentName = 'dev'
$resourceGroup = 'rg-la-easyauth-lab-dev'
$logicAppClientId = '786594a8-6b38-40cf-8c6b-d434b539dd46'
$callerClientId = 'a571dbde-47f4-4e3d-a1f8-1b012d065786'
```

## Step 4: Create the Logic App API app registration

This app registration represents the API being protected. Its Application ID URI becomes the token audience.

> **Using the existing validated environment?** Keep the `$logicAppClientId` value from Step 3, skip the creation commands, and continue with the portal checkpoint. Run the commands below only for a new lab environment.

```powershell
$logicAppClientId = az ad app create `
  --display-name $logicAppRegistrationName `
  --sign-in-audience AzureADMyOrg `
  --query appId `
  --output tsv

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($logicAppClientId)) {
  throw 'Could not create the Logic App API app registration.'
}

az ad app update `
  --id $logicAppClientId `
  --identifier-uris "api://$logicAppClientId"

az ad sp create --id $logicAppClientId --output none
```

Record the client ID:

```powershell
$logicAppClientId
```

Portal checkpoint:

1. Open **Microsoft Entra ID**.
2. Open **App registrations**.
3. Select the registration named `$logicAppRegistrationName`.
4. On **Overview**, show the **Application (client) ID**.
5. Open **Expose an API** and show `api://<client-id>` as the Application ID URI.

Explain:

- The client ID identifies the app registration.
- `api://<client-id>` identifies the protected API and appears in the token's `aud` claim.
- No delegated scope, app role, redirect URI, or client secret is required for this lab.

If the registration already exists, retrieve it instead of creating another:

```powershell
$logicAppClientId = az ad app list `
  --display-name $logicAppRegistrationName `
  --query '[0].appId' `
  --output tsv
```

## Step 5: Create the caller Function app registration

This second registration represents the Function App's own Easy Auth configuration. It is not the identity used for the downstream call. The downstream caller is the Function's system-assigned managed identity, which Azure creates during infrastructure deployment.

> **Using the existing validated environment?** Keep the `$callerClientId` value from Step 3, skip the creation commands, and continue with the portal checkpoint. Run the commands below only for a new lab environment.

```powershell
$callerClientId = az ad app create `
  --display-name $callerRegistrationName `
  --sign-in-audience AzureADMyOrg `
  --query appId `
  --output tsv

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($callerClientId)) {
  throw 'Could not create the caller Function app registration.'
}

az ad sp create --id $callerClientId --output none
```

Portal checkpoint:

1. Return to **Microsoft Entra ID** > **App registrations**.
2. Show both registrations.
3. Explain that neither registration contains a client secret.

If the registration already exists:

```powershell
$callerClientId = az ad app list `
  --display-name $callerRegistrationName `
  --query '[0].appId' `
  --output tsv
```

## Step 6: Save the local configuration

```powershell
Copy-Item .env.example .env
```

Set these values in `.env`:

```dotenv
AZURE_SUBSCRIPTION_ID=<subscription-id>
AZURE_TENANT_ID=<tenant-id>
ENTRA_APP_CLIENT_ID=<logic-app-client-id>
FUNC_CALLER_ENTRA_CLIENT_ID=<caller-client-id>
AZURE_REGION=westeurope
ENVIRONMENT_NAME=dev
```

Do not add secrets, storage keys, Function keys, or access tokens to `.env`.

## Step 7: Preview the infrastructure deployment

```powershell
./scripts/deploy.ps1 `
  -SubscriptionId $subscriptionId `
  -EnvironmentName $environmentName `
  -Location $location `
  -EntraAppClientId $logicAppClientId `
  -EntraAppTenantId $tenantId `
  -DeployFuncCallerDemo `
  -FuncCallerEntraClientId $callerClientId `
  -WhatIf
```

Explain what the deployment creates:

- Logic App Standard on a WS1 Workflow Service Plan.
- Caller Function App on an S1 App Service Plan.
- Function system-assigned managed identity.
- Easy Auth on the Logic App.
- VNet integration and private storage endpoints.
- Storage RBAC assignments for the hosting identities.
- Application Insights and Log Analytics.

Do not add `-EnablePrivateAppNetworking` for the classroom walkthrough. Private app ingress is an optional advanced exercise.

## Step 8: Deploy the infrastructure

Run the same command without `-WhatIf`:

```powershell
./scripts/deploy.ps1 `
  -SubscriptionId $subscriptionId `
  -EnvironmentName $environmentName `
  -Location $location `
  -EntraAppClientId $logicAppClientId `
  -EntraAppTenantId $tenantId `
  -DeployFuncCallerDemo `
  -FuncCallerEntraClientId $callerClientId
```

If Azure CLI reports `InteractionRequired` or `TokenCreatedWithOutdatedPolicies`, refresh the tenant sign-in and retry:

```powershell
az login --tenant $tenantId
az account set --subscription $subscriptionId
```

## Step 9: Discover and inspect the deployed resources

```powershell
$logicAppName = az resource list `
  --resource-group $resourceGroup `
  --resource-type Microsoft.Web/sites `
  --query "[?contains(kind, 'workflowapp')].name | [0]" `
  --output tsv

$functionAppName = az functionapp list `
  --resource-group $resourceGroup `
  --query "[?contains(name, '-caller-')].name | [0]" `
  --output tsv

$logicAppHost = az webapp show --resource-group $resourceGroup --name $logicAppName --query defaultHostName --output tsv
$functionAppHost = az functionapp show --resource-group $resourceGroup --name $functionAppName --query defaultHostName --output tsv
$functionPrincipalId = az functionapp identity show --resource-group $resourceGroup --name $functionAppName --query principalId --output tsv

[pscustomobject]@{
  LogicApp = $logicAppName
  LogicAppHost = $logicAppHost
  FunctionApp = $functionAppName
  FunctionAppHost = $functionAppHost
  FunctionManagedIdentityPrincipalId = $functionPrincipalId
} | Format-List
```

Portal checkpoint:

1. Open resource group `$resourceGroup`.
2. Show the Logic App, caller Function, plans, storage account, Application Insights, VNet, and private endpoints.
3. Open the Function App > **Identity** and show **System assigned: On** plus its object/principal ID.

Explain that the principal ID is the identity Easy Auth authorizes. It is different from both app-registration client IDs.

## Step 10: Inspect the deployed Easy Auth policy

```powershell
$authUri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Web/sites/$logicAppName/config/authsettingsv2?api-version=2023-12-01"

az rest --method get --uri $authUri `
  --query "properties.{enabled:platform.enabled,action:globalValidation.unauthenticatedClientAction,excludedPaths:globalValidation.excludedPaths,audiences:identityProviders.azureActiveDirectory.validation.allowedAudiences,principals:identityProviders.azureActiveDirectory.validation.defaultAuthorizationPolicy.allowedPrincipals.identities}" `
  --output json
```

Expected:

- `enabled`: `true`
- `action`: `Return401`
- `excludedPaths`: `/runtime/*`
- `audiences`: `api://<logic-app-client-id>`
- `principals`: the Function managed-identity principal ID

Portal checkpoint:

1. Open the Logic App > **Authentication**.
2. Show the Microsoft identity provider.
3. Explain that the portal does not display `excludedPaths`; Bicep configures `/runtime/*` so run history works.

## Step 11: Publish the workflow

```powershell
./scripts/deploy-workflow.ps1 `
  -SubscriptionId $subscriptionId `
  -ResourceGroupName $resourceGroup `
  -LogicAppName $logicAppName
```

Expected: `Workflow deployed successfully with HTTP POST.`

If App Service asks for a fresh token:

```powershell
az login --tenant $tenantId --scope https://appservice.azure.com/.default
```

Then rerun the workflow deployment.

Portal checkpoint:

1. Open the Logic App > **Workflows** > `httpTriggerWorkflow`.
2. Show the request trigger and response action.
3. Explain that the unsigned invoke URL contains no `sig` query parameter.

## Step 12: Publish the Function code

```powershell
$logicAppUrl = "https://$logicAppHost/api/httpTriggerWorkflow/triggers/When_a_HTTP_request_is_received/invoke?api-version=2022-05-01"

./solution/deploy.ps1 `
  -FunctionAppName $functionAppName `
  -ResourceGroupName $resourceGroup `
  -LogicAppUrl $logicAppUrl `
  -LogicAppAudience "api://$logicAppClientId" `
  -TenantId $tenantId
```

The script builds the .NET 8 isolated Function, ZIP-deploys it, and configures:

- `LOGIC_APP_URL`
- `LOGIC_APP_AUDIENCE=api://<logic-app-client-id>`
- `WEBSITE_AUTH_AAD_ALLOWED_TENANTS=<tenant-id>`

Portal checkpoint:

1. Open the Function App > **Environment variables**.
2. Show the setting names, but do not expose keys or tokens.
3. Open **Functions** and show `CallLogicApp`.

## Step 13: Run the presentation-ready Easy Auth demo

```powershell
./scripts/demo-easyauth.ps1 `
  -SubscriptionId $subscriptionId `
  -ResourceGroupName $resourceGroup `
  -LogicAppName $logicAppName `
  -FunctionAppName $functionAppName `
  -LogicAppClientId $logicAppClientId `
  -TenantId $tenantId
```

Expected:

- `passed`: `true`
- `unauthenticatedLogicAppStatus`: `401`
- `authenticatedFunctionStatus`: `200`
- Every assertion: `true`
- Workflow principal equals the Function managed-identity principal ID

Explain the two requests:

1. The script calls the unsigned Logic App URL without a bearer token. Easy Auth returns HTTP 401.
2. The script calls the Function with a Function key. The Function obtains a managed-identity token and calls the same Logic App URL. Easy Auth accepts it and the workflow returns HTTP 200.

The script never prints the Function key or bearer token.

## Step 14: Show the Logic App run history

1. Open the Logic App > **Workflows** > `httpTriggerWorkflow`.
2. Select **Run history**.
3. Refresh the pane.
4. Open the most recent `Succeeded` run.
5. Show the trigger inputs and response output.

If the portal reports HTTP 401, verify that `/runtime/*` is excluded:

```powershell
az rest --method get --uri $authUri `
  --query "properties.globalValidation.{action:unauthenticatedClientAction,excludedPaths:excludedPaths}" `
  --output json
```

Expected: `Return401` plus `/runtime/*`. The workflow trigger under `/api/*` remains protected.

## Step 15: Show the Function traces

Open Application Insights > **Logs** and run:

```kusto
traces
| where timestamp > ago(30m)
| where message has_any ("Bearer token acquired", "Token claims inspected locally", "Logic App response")
| project timestamp, message, severityLevel, operation_Id
| order by timestamp asc
```

Correlate the timestamp with the Logic App run shown in Step 14.

## Step 16: Summarize the security decisions

Ask the attendee to explain:

1. Why is the Logic App app registration needed? It defines the API identity and token audience.
2. Which identity actually calls the Logic App? The Function system-assigned managed identity.
3. What does Easy Auth authenticate? Token signature, issuer, audience, and lifetime.
4. What authorizes the caller? The Function identity in `allowedPrincipals`.
5. Why does the portal run history work? `/runtime/*` bypasses Easy Auth and uses Logic Apps runtime authorization; `/api/*` remains protected.
6. Why is there no SAS signature? The primary learner call proves access with an Entra workload identity and short-lived token.

## Step 17: Clean up after the lab

Delete the lab resource group when the attendee is finished:

```powershell
az group delete `
  --subscription $subscriptionId `
  --name $resourceGroup `
  --yes `
  --no-wait
```

Delete the two lab app registrations if they are not shared with another environment:

```powershell
az ad app delete --id $logicAppClientId
az ad app delete --id $callerClientId
```

## Quick troubleshooting

| Symptom | Meaning | First action |
| --- | --- | --- |
| Function endpoint returns 401 | Function key is missing or invalid | Use `scripts/demo-easyauth.ps1`, which obtains the key without printing it. |
| Logic App returns 401 | Bearer token is missing, invalid, expired, or for the wrong audience | Compare `LOGIC_APP_AUDIENCE` with Easy Auth `allowedAudiences`. |
| Logic App returns 403 | Token is valid but the caller is not allow-listed | Compare Function `principalId` with `allowedPrincipals`. |
| Portal run history returns 401 | `/runtime/*` is missing from Easy Auth `excludedPaths` | Redeploy the current Bicep or restore the runtime exclusion. |
| Managed-identity token request fails | Logic App registration lacks `api://<client-id>` or its service principal | Rerun the Entra preflight or repeat Step 4. |
| Workflow is missing or uses the wrong method | Workflow ZIP was not published | Repeat Step 11 and confirm HTTP POST. |
| Function ZIP deployment loses its SCM connection | App Service deployment token or SCM connection is stale | Refresh the App Service-scoped login and repeat Step 12. |

For deeper diagnosis, continue with [Lab 3 testing and verification](lab3-testing-and-verification.md) and [Troubleshooting](troubleshooting.md).
