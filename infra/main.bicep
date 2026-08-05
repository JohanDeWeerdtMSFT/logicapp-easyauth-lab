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

@description('Deploy the Function App caller demo (Lab 3). Requires a separate Entra app registration for the Function App.')
param deployFuncCallerDemo bool = false

@description('Enable private inbound access for the Logic App. The public classroom path leaves this disabled while retaining VNet integration and private storage.')
param enablePrivateAppNetworking bool = false

@description('Entra ID application client ID for the caller Function App Easy Auth registration. Required when deployFuncCallerDemo = true.')
param funcCallerEntraClientId string = ''

@description('Optional object ID used instead of the caller managed identity in Logic App Easy Auth allowedPrincipals. Intended only for isolated authorization tests such as B6.')
param easyAuthAllowedPrincipalOverride string = ''

// ── 1. Foundation ──────────────────────────────
module foundation 'modules/foundation.bicep' = {
  name: 'foundation'
  params: {
    environmentName: environmentName
    location: location
    disableStoragePublicAccess: deployFuncCallerDemo
  }
}

// ── 1b. Networking (optional — required for func-caller demo) ──
module networking 'modules/networking.bicep' = if (deployFuncCallerDemo) {
  name: 'networking'
  params: {
    environmentName: environmentName
    location: location
    storageAccountName: foundation.outputs.storageAccountName
    enableAppPrivateIngress: enablePrivateAppNetworking
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
    entraAppTenantId: entraAppTenantId
    // VNet integration supports private storage; Logic App private ingress is optional.
    vnetIntegrationSubnetId: deployFuncCallerDemo ? networking!.outputs.appIntegrationSubnetId : ''
    privateEndpointSubnetId: deployFuncCallerDemo && enablePrivateAppNetworking ? networking!.outputs.privateEndpointSubnetId : ''
    privateDnsZoneId: deployFuncCallerDemo && enablePrivateAppNetworking ? networking!.outputs.privateDnsZoneId : ''
  }
}

// ── 3. Function App (optional, comparison baseline) ─────────────
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

// ── 5. Function App Caller + Easy Auth ──
// Deploys a dedicated Function App with:
//   - Outbound VNet integration → routes HTTP calls through the VNet
//   - System-assigned managed identity → used to acquire Entra tokens for the Logic App
//   - Function-key-protected test harness with Easy Auth AllowAnonymous behind the key guard
// The Logic App Easy Auth is updated (module easyauth above) to only allow this
// Function App’s managed identity principal ID.
module funcCallerApp 'modules/functionapp-caller.bicep' = if (deployFuncCallerDemo) {
  name: 'functionapp-caller'
  params: {
    environmentName: environmentName
    location: location
    appInsightsConnectionString: foundation.outputs.appInsightsConnectionString
    storageAccountName: foundation.outputs.storageAccountName
    storageAccountId: foundation.outputs.storageAccountId
    vnetIntegrationSubnetId: networking!.outputs.appIntegrationSubnetId
    entraAppClientId: funcCallerEntraClientId
    entraAppTenantId: entraAppTenantId
    logicAppHostname: logicApp.outputs.logicAppDefaultHostname
    logicAppEntraClientId: entraAppClientId
  }
}

// ── 4. Easy Auth on Logic App ────────────────────────
// Default to the deployed caller identity. An explicit override supports isolated 403 tests.
var defaultEasyAuthAllowedPrincipals = deployFuncCallerDemo ? [ funcCallerApp!.outputs.functionAppPrincipalId ] : []
var easyAuthAllowedPrincipals = !empty(easyAuthAllowedPrincipalOverride)
  ? [ easyAuthAllowedPrincipalOverride ]
  : defaultEasyAuthAllowedPrincipals

module easyAuth 'modules/easyauth.bicep' = {
  name: 'easyauth'
  params: {
    logicAppName: logicApp.outputs.logicAppName
    easyAuthMode: easyAuthMode
    entraAppClientId: entraAppClientId
    entraAppTenantId: entraAppTenantId
    allowedPrincipals: easyAuthAllowedPrincipals
  }
}

// ── Outputs ────────────────────────────────────
output resourceGroupName string = resourceGroup().name
output logicAppName string = logicApp.outputs.logicAppName
output logicAppDefaultHostname string = logicApp.outputs.logicAppDefaultHostname
output logicAppResourceId string = logicApp.outputs.logicAppResourceId
output storageAccountName string = foundation.outputs.storageAccountName
output functionAppCallerName string = deployFuncCallerDemo ? funcCallerApp!.outputs.functionAppName : ''
output functionAppCallerHostname string = deployFuncCallerDemo ? funcCallerApp!.outputs.functionAppDefaultHostname : ''
output functionAppCallerPrincipalId string = deployFuncCallerDemo ? funcCallerApp!.outputs.functionAppPrincipalId : ''

