# Deployment & Testing Quick Reference

## Environment Values (TEMPLATE - Replace with your values)

```
Subscription ID:                {subscriptionId}
Tenant ID:                      {tenantId}
Region:                         {region}
Resource Group:                 {resourceGroupName}

Logic App Name:                 {logicAppName}
Logic App Client ID:            {logicAppClientId}

Function App Name:              {functionAppName}
Function App Location:          https://{functionAppName}.azurewebsites.net

Workflow:                       httpTriggerWorkflow
Invoke URL (NO SIG!):           https://{logicAppName}.azurewebsites.net/api/httpTriggerWorkflow/triggers/When_a_HTTP_request_is_received/invoke?api-version=2022-05-01

Audience (for bearer token):    {logicAppClientId}

User-assigned MI:               {managedIdentityName}
User-assigned MI Client ID:     {managedIdentityClientId}
```

> **Note:** This is a template. Replace all `{placeholders}` with your actual values before using in scripts.

## Deploy Function App Code

```powershell
cd c:\Code\CSU\Ores\EasyAuth\solution

.\deploy.ps1 `
  -FunctionAppName "{functionAppName}" `
  -ResourceGroupName "{resourceGroupName}" `
  -LogicAppUrl "https://{logicAppName}.azurewebsites.net/api/httpTriggerWorkflow/triggers/When_a_HTTP_request_is_received/invoke?api-version=2022-05-01" `
  -LogicAppAudience "{logicAppClientId}" `
  -TenantId "{tenantId}"
```

✅ **Note**: No SAS signature required!

## Verify Deployment

```powershell
# Check app settings (should show NO secrets)
az functionapp config appsettings list `
  --name "{functionAppName}" `
  --resource-group "{resourceGroupName}" `
  --query "[?name=='LOGIC_APP_URL' || name=='LOGIC_APP_AUDIENCE' || name=='WEBSITE_AUTH_AAD_ALLOWED_TENANTS'].{name:name, value:value}" `
  -o table

# Check Function App managed identity
az functionapp identity show `
  --name "la-easyauth-lab-dev-caller-daaq6t5xzrpaw" `
  --resource-group "rg-la-easyauth-lab-dev"

# Check function deployment
az functionapp deployment slot list `
  --name "la-easyauth-lab-dev-caller-daaq6t5xzrpaw" `
  --resource-group "rg-la-easyauth-lab-dev" `
  --query "[].name"
```

## Deploy Workflow to Logic App

```powershell
./scripts/deploy-workflow.ps1 `
  -SubscriptionId "{subscriptionId}" `
  -ResourceGroupName "{resourceGroupName}" `
  -LogicAppName "{logicAppName}"
```

This ZIP deployment publishes `src/host.json` and the workflow directory separately from the Bicep infrastructure deployment. For a private Logic App, run it from a machine with network and DNS access to the SCM endpoint.

## Verify Workflow Deployment

```powershell
# List workflows
az rest --method get `
  --uri "https://management.azure.com/subscriptions/6851693c-0b74-4462-8da8-cd498b088827/resourceGroups/rg-la-easyauth-lab-dev/providers/Microsoft.Web/sites/la-easyauth-lab-dev-la-daaq6t5xzrpaw/workflows?api-version=2023-12-01" `
  --query "value[].name"

# Get workflow status
az rest --method get `
  --uri "https://management.azure.com/subscriptions/6851693c-0b74-4462-8da8-cd498b088827/resourceGroups/rg-la-easyauth-lab-dev/providers/Microsoft.Web/sites/la-easyauth-lab-dev-la-daaq6t5xzrpaw/workflows/httpTriggerWorkflow?api-version=2023-12-01" `
  --query "properties.state"
```

## Add Function App to Logic App allowedPrincipals

```powershell
# Get Function App's managed identity Object ID
$funcAppObjectId = az functionapp identity show `
  --name "la-easyauth-lab-dev-caller-daaq6t5xzrpaw" `
  --resource-group "rg-la-easyauth-lab-dev" `
  --query principalId -o tsv

Write-Host "Function App Object ID: $funcAppObjectId"

# Add to Logic App's Easy Auth allowedPrincipals
az rest --method patch `
  --uri "https://management.azure.com/subscriptions/6851693c-0b74-4462-8da8-cd498b088827/resourceGroups/rg-la-easyauth-lab-dev/providers/Microsoft.Web/sites/la-easyauth-lab-dev-la-daaq6t5xzrpaw/config/authsettingsv2?api-version=2023-12-01" `
  --body @-<<EOF
{
  "properties": {
    "identityProviders": {
      "azureActiveDirectory": {
        "validation": {
          "allowedPrincipals": {
            "identities": [
              "$funcAppObjectId"
            ]
          }
        }
      }
    }
  }
}
EOF

Write-Host "Function App added to Logic App allowedPrincipals"
```

## Test Bearer Token Flow

### Test 1: Call Function App (Simple)
```bash
# Get Function App URL
FUNC_URL=$(az functionapp show \
  --name "la-easyauth-lab-dev-caller-daaq6t5xzrpaw" \
  --resource-group "rg-la-easyauth-lab-dev" \
  --query defaultHostName -o tsv)

# Call the function
curl -X POST "https://$FUNC_URL/api/CallLogicApp" \
  -H "Content-Type: application/json"
```

### Test 2: Check Logs
```kusto
# In Application Insights
traces
| where message contains "CallLogicApp"
| project timestamp, message, severityLevel
| order by timestamp desc
```

### Test 3: Full Token Flow
```powershell
# Get bearer token using your own identity (for testing)
$token = $(az account get-access-token `
  --resource "api://786594a8-6b38-40cf-8c6b-d434b539dd46" `
  --query accessToken -o tsv)

# Call Logic App directly with bearer token
$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type" = "application/json"
}

$response = Invoke-WebRequest `
  -Uri "https://la-easyauth-lab-dev-la-daaq6t5xzrpaw.azurewebsites.net/api/httpTriggerWorkflow/triggers/When_a_HTTP_request_is_received/invoke?api-version=2022-05-01" `
  -Method Post `
  -Headers $headers `
  -Body '{"test":"message"}'

Write-Host $response.Content
```

## Troubleshooting

### 401 Unauthorized
```
Cause: Bearer token invalid or audience mismatch
Fix:   Verify LOGIC_APP_AUDIENCE = api://786594a8-6b38-40cf-8c6b-d434b539dd46
```

### 403 Forbidden
```
Cause: Function App not in Logic App's allowedPrincipals
Fix:   Run "Add Function App to Logic App allowedPrincipals" section above
```

### Function App deployment fails
```
Cause: Solution build error
Fix:   cd solution && dotnet build --configuration Release
```

### Workflow not found (404)
```
Cause: httpTriggerWorkflow not deployed
Fix:   Deploy workflow via Portal or VS Code extension
```

### Can't acquire token
```
Cause: System-assigned managed identity not enabled
Fix:   Portal → Function App → Identity → System assigned → On
```

## Application Insights Queries

```kusto
# All CallLogicApp invocations
traces
| where message contains "CallLogicApp"
| project timestamp, message, severityLevel

# Bearer token events
traces
| where message contains "Bearer token"
| project timestamp, message

# Logic App responses
traces
| where message contains "Logic App response"
| project timestamp, message

# Easy Auth validation results
traces
| where message contains "Easy Auth"
| project timestamp, message

# Errors and failures
traces
| where severityLevel >= 2
| project timestamp, message, severityLevel
```

## One-Liner: Full Deployment

```powershell
# Deploy infrastructure (if needed)
# az deployment group create --resource-group rg-la-easyauth-lab-dev --template-file infra/main.json

# Deploy Function App code
cd solution; .\deploy.ps1 `
  -FunctionAppName "la-easyauth-lab-dev-caller-daaq6t5xzrpaw" `
  -ResourceGroupName "rg-la-easyauth-lab-dev" `
  -LogicAppUrl "https://la-easyauth-lab-dev-la-daaq6t5xzrpaw.azurewebsites.net/api/httpTriggerWorkflow/triggers/When_a_HTTP_request_is_received/invoke?api-version=2022-05-01" `
  -LogicAppAudience "api://786594a8-6b38-40cf-8c6b-d434b539dd46" `
  -TenantId "00922812-791e-41c8-a99e-45c3ed784cf5"; `

# Add Function App to allowedPrincipals
$funcAppObjectId = az functionapp identity show --name "la-easyauth-lab-dev-caller-daaq6t5xzrpaw" --resource-group "rg-la-easyauth-lab-dev" --query principalId -o tsv; `

az rest --method patch --uri "https://management.azure.com/subscriptions/6851693c-0b74-4462-8da8-cd498b088827/resourceGroups/rg-la-easyauth-lab-dev/providers/Microsoft.Web/sites/la-easyauth-lab-dev-la-daaq6t5xzrpaw/config/authsettingsv2?api-version=2023-12-01" `
  --body "{\"properties\": {\"identityProviders\": {\"azureActiveDirectory\": {\"validation\": {\"allowedPrincipals\": {\"identities\": [\"$funcAppObjectId\"]}}}}}}"; `

# Test
$FUNC_URL = az functionapp show --name "la-easyauth-lab-dev-caller-daaq6t5xzrpaw" --resource-group "rg-la-easyauth-lab-dev" --query defaultHostName -o tsv; `
curl -X POST "https://$FUNC_URL/api/CallLogicApp"
```

## Key Files

| File | Purpose |
|------|---------|
| `solution/CallerFunctionApp/CallLogicApp.cs` | Bearer token flow implementation |
| `solution/deploy.ps1` | Deployment automation |
| `solution/CallerFunctionApp/local.settings.json` | Local development config |
| `src/httpTriggerWorkflow/workflow.json` | Logic App workflow definition |
| `infra/modules/functionapp-caller.bicep` | Function App infrastructure |
| `docs/lab3-passwordless-managed-identity-easy-auth.md` | Full documentation |
| `docs/REFACTORING-NOTES.md` | Change summary |
