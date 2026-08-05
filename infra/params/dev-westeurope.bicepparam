using '../main.bicep'

param environmentName = 'dev'
param location = 'westeurope'
param easyAuthMode = 'Return401'

// Replace these placeholders before deployment.
// Tenant ID: Microsoft Entra ID > Overview > Tenant ID.
// Logic App client ID: Microsoft Entra ID > App registrations > your Logic App
// API registration > Overview > Application (client) ID.
param entraAppClientId = 'REPLACE-WITH-LOGIC-APP-CLIENT-ID'
param entraAppTenantId = 'REPLACE-WITH-TENANT-ID'

param deployFunctionApp = false

// ── Lab 3: Function App caller → Logic App via private endpoint ──
// Caller client ID: Microsoft Entra ID > App registrations > your caller
// Function registration > Overview > Application (client) ID.
param deployFuncCallerDemo = true
param enablePrivateAppNetworking = false
param funcCallerEntraClientId = 'REPLACE-WITH-CALLER-APP-CLIENT-ID'
