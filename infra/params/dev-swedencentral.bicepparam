using '../main.bicep'

param environmentName = 'dev'
param location = 'swedencentral'
param easyAuthMode = 'Return401'

// TODO: Replace with actual Entra ID app registration values after running:
//   az ad app create --display-name "la-easyauth-lab-dev"
param entraAppClientId = '<ENTRA_APP_CLIENT_ID>'
param entraAppTenantId = '<ENTRA_TENANT_ID>'

param deployFunctionApp = false
