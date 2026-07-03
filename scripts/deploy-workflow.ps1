# Deploy the workflow definition to the Logic App
$resourceGroup = "rg-la-easyauth-lab-dev"
$logicAppName = "la-easyauth-lab-dev-la-daaq6t5xzrpaw"
$workflowName = "httpTriggerWorkflow"
$subscriptionId = "6851693c-0b74-4462-8da8-cd498b088827"

$workflowJsonPath = "c:\Code\CSU\Ores\EasyAuth\src\httpTriggerWorkflow\workflow.json"

Write-Host "Deploying workflow: $workflowName to Logic App: $logicAppName"

# Read the workflow definition
$workflowDef = Get-Content $workflowJsonPath -Raw

# Deploy via REST API
$uri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Web/sites/$logicAppName/workflows/$workflowName" + "?api-version=2022-09-01"

Write-Host "URI: $uri"
Write-Host ""
Write-Host "Deployment in progress..."

$response = az rest --method put --uri "$uri" --body "$workflowDef" 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Workflow deployed successfully" -ForegroundColor Green
    Write-Host ""
    Write-Host "Callback URL:"
    az rest --method post `
      --uri "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Web/sites/$logicAppName/workflows/$workflowName/triggers/When_a_HTTP_request_is_received/listCallbackUrl?api-version=2022-09-01" `
      --query value -o tsv
} else {
    Write-Host "❌ Deployment failed" -ForegroundColor Red
    Write-Host $response
}
