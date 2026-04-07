targetScope = 'resourceGroup'

// ══════════════════════════════════════════════
// Lane A – Logic App Standard Easy Auth Lab
// Orchestrator
// ══════════════════════════════════════════════

@description('Environment name (e.g. dev, test, prod). Used in all resource names.')
param environmentName string

@description('Primary Azure region for deployment.')
param location string = 'westeurope'

@description('Easy Auth unauthenticated-client action – the key toggle for this lab.')
@allowed([
  'Return401'
  'AllowAnonymous'
])
param easyAuthMode string = 'Return401'

@description('Entra ID (AAD) application (client) ID for Easy Auth.')
param entraAppClientId string

@description('Entra ID tenant ID.')
param entraAppTenantId string

@description('Deploy an optional Function App for comparison testing.')
param deployFunctionApp bool = false

// ── 1. Foundation ──────────────────────────────
module foundation 'modules/foundation.bicep' = {
  name: 'foundation'
  params: {
    environmentName: environmentName
    location: location
  }
}

// ── 2. Logic App Standard ──────────────────────
module logicApp 'modules/logicapp.bicep' = {
  name: 'logicapp'
  params: {
    environmentName: environmentName
    location: location
    appServicePlanId: foundation.outputs.appServicePlanId
    storageAccountName: foundation.outputs.storageAccountName
    storageAccountId: foundation.outputs.storageAccountId
    appInsightsConnectionString: foundation.outputs.appInsightsConnectionString
  }
}

// ── 3. Easy Auth ───────────────────────────────
module easyAuth 'modules/easyauth.bicep' = {
  name: 'easyauth'
  params: {
    logicAppName: logicApp.outputs.logicAppName
    easyAuthMode: easyAuthMode
    entraAppClientId: entraAppClientId
    entraAppTenantId: entraAppTenantId
  }
}

// ── 4. Function App (optional) ─────────────────
module functionApp 'modules/functionapp.bicep' = if (deployFunctionApp) {
  name: 'functionapp'
  params: {
    environmentName: environmentName
    location: location
    appServicePlanId: foundation.outputs.appServicePlanId
    storageAccountName: foundation.outputs.storageAccountName
    storageAccountId: foundation.outputs.storageAccountId
    appInsightsConnectionString: foundation.outputs.appInsightsConnectionString
    enableEasyAuth: true
    entraAppClientId: entraAppClientId
    entraAppTenantId: entraAppTenantId
  }
}

// ── Outputs ────────────────────────────────────
output resourceGroupName string = resourceGroup().name
output logicAppName string = logicApp.outputs.logicAppName
output logicAppDefaultHostname string = logicApp.outputs.logicAppDefaultHostname
output logicAppResourceId string = logicApp.outputs.logicAppResourceId
output storageAccountName string = foundation.outputs.storageAccountName
