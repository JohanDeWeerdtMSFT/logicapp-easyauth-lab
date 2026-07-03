using '../main.bicep'

param environmentName = 'dev'
param location = 'westeurope'
param easyAuthMode = 'Return401'

// TODO: Replace with actual Entra ID app registration values after running:
//   az ad app create --display-name "la-easyauth-lab-dev"
param entraAppClientId = '<ENTRA_APP_CLIENT_ID>'
param entraAppTenantId = '<ENTRA_TENANT_ID>'

param deployFunctionApp = false

// ── Lab 3: Function App caller → Logic App via private endpoint ──
// Set deployFuncCallerDemo = true and supply a second Entra app registration
// for the Function App's own Easy Auth. Run:
//   az ad app create --display-name "la-easyauth-lab-caller-dev"
param deployFuncCallerDemo = false
param funcCallerEntraClientId = '<FUNC_CALLER_ENTRA_APP_CLIENT_ID>'
