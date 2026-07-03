using '../main.bicep'

param environmentName = 'dev'
param location = 'westeurope'
param easyAuthMode = 'AllowAnonymous'

// Lab 1 + Lab 3: Logic App Entra app registration
// az ad app create --display-name "la-easyauth-lab-dev"
param entraAppClientId = '786594a8-6b38-40cf-8c6b-d434b539dd46'
param entraAppTenantId = '00922812-791e-41c8-a99e-45c3ed784cf5'

param deployFunctionApp = false

// ── Lab 3: Function App caller → Logic App via private endpoint ──
// Function App caller Entra app registration for its own Easy Auth
// az ad app create --display-name "la-easyauth-lab-caller-dev"
param deployFuncCallerDemo = true
param funcCallerEntraClientId = 'a571dbde-47f4-4e3d-a1f8-1b012d065786'
