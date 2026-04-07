targetScope = 'resourceGroup'

// ──────────────────────────────────────────────
// Optional Function App – comparison baseline
// ──────────────────────────────────────────────

@description('Environment name used in resource naming.')
param environmentName string

@description('Azure region for the Function App.')
param location string

@description('Resource ID of the App Service Plan.')
param appServicePlanId string

@description('Name of the storage account used by the Function App.')
param storageAccountName string

@description('Resource ID of the storage account (kept for interface consistency).')
#disable-next-line no-unused-params
param storageAccountId string

@description('Application Insights connection string.')
param appInsightsConnectionString string

@description('Whether to enable Easy Auth on the Function App.')
param enableEasyAuth bool = false

@description('Entra ID application client ID (required when enableEasyAuth is true).')
param entraAppClientId string = ''

@description('Entra ID tenant ID (required when enableEasyAuth is true).')
param entraAppTenantId string = ''

var baseName = 'la-easyauth-lab-${environmentName}'
var suffix = uniqueString(resourceGroup().id)
var functionAppName = '${baseName}-func-${suffix}'

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlanId
    httpsOnly: true
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'node'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~18'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
      ]
    }
  }
}

resource functionAuthSettings 'Microsoft.Web/sites/config@2023-12-01' = if (enableEasyAuth) {
  name: 'authsettingsV2'
  parent: functionApp
  properties: {
    platform: {
      enabled: true
    }
    globalValidation: {
      unauthenticatedClientAction: 'Return401'
      redirectToProvider: 'azureActiveDirectory'
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: {
          openIdIssuer: 'https://sts.windows.net/${entraAppTenantId}/v2.0'
          clientId: entraAppClientId
        }
        validation: {
          allowedAudiences: [entraAppClientId]
        }
      }
    }
    login: {
      tokenStore: {
        enabled: true
      }
    }
  }
}

// ── Outputs ──
output functionAppName string = functionApp.name
output functionAppDefaultHostname string = functionApp.properties.defaultHostName
