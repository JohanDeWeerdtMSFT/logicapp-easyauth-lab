targetScope = 'resourceGroup'

// ──────────────────────────────────────────────
// Function App (caller) module
//
// Represents the "caller" side of the demo:
//   [Function App] -> [Logic App Standard]
//
// Security posture:
// - Inbound:  The HTTP trigger requires a Function key. Easy Auth remains in
//             AllowAnonymous mode behind that lab guard.
// - Outbound: Uses system-assigned managed identity to acquire an Entra
//             bearer token for the Logic App audience before calling it
// - Network:  VNet integration for private storage. Logic App ingress can be
//             public for the classroom path or private for advanced exercises.
// - Storage:  AzureWebJobsStorage uses managed identity, not a connection string.
// ──────────────────────────────────────────────

@description('Environment name used in resource naming.')
param environmentName string

@description('Azure region for the Function App.')
param location string

@description('Application Insights connection string.')
param appInsightsConnectionString string

@description('Name of the shared storage account.')
param storageAccountName string

@description('Resource ID of the shared storage account (used for RBAC).')
param storageAccountId string

@description('Subnet resource ID for outbound VNet integration.')
param vnetIntegrationSubnetId string

@description('Entra ID (AAD) application client ID for the Function App\'s own Easy Auth registration.')
param entraAppClientId string

@description('Entra ID tenant ID.')
param entraAppTenantId string

@description('Object IDs of principals allowed to call this Function App via Easy Auth.')
param allowedPrincipals array = []

@description('Default hostname of the Logic App being called. Used to build LOGIC_APP_URL app setting.')
param logicAppHostname string

@description('Entra app client ID of the Logic App — used as the token audience when calling it via managed identity.')
param logicAppEntraClientId string

var baseName = 'la-easyauth-lab-${environmentName}'
var suffix = uniqueString(resourceGroup().id)
var functionAppName = '${baseName}-caller-${suffix}'
var storageBlobUri = 'https://${storageAccountName}.blob.${environment().suffixes.storage}'
var storageQueueUri = 'https://${storageAccountName}.queue.${environment().suffixes.storage}'
var storageTableUri = 'https://${storageAccountName}.table.${environment().suffixes.storage}'

// ── Dedicated App Service Plan for the Function App ──
// Standard S1 is the minimum tier that supports VNet integration.
// Cannot reuse the WS1 WorkflowStandard plan (Logic App–only SKU).
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${baseName}-caller-plan'
  location: location
  sku: {
    tier: 'Standard'
    name: 'S1'
  }
  kind: 'app'
}

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    // Outbound VNet integration provides access to private storage endpoints.
    virtualNetworkSubnetId: vnetIntegrationSubnetId
    vnetRouteAllEnabled: true
    siteConfig: {
      appSettings: [
        // Identity-based AzureWebJobsStorage application settings
        {
          name: 'AzureWebJobsStorage__accountName'
          value: storageAccountName
        }
        {
          name: 'AzureWebJobsStorage__credential'
          value: 'managedidentity'
        }
        {
          name: 'AzureWebJobsStorage__blobServiceUri'
          value: storageBlobUri
        }
        {
          name: 'AzureWebJobsStorage__queueServiceUri'
          value: storageQueueUri
        }
        {
          name: 'AzureWebJobsStorage__tableServiceUri'
          value: storageTableUri
        }
        // Runtime
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet-isolated'
        }
        // Monitoring
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
        // ── Logic App call configuration ──
        // The function acquires a managed-identity token with this audience,
        // then sends it as Authorization: Bearer <token> to the Logic App.
        {
          name: 'LOGIC_APP_URL'
          value: 'https://${logicAppHostname}/api/httpTriggerWorkflow/triggers/When_a_HTTP_request_is_received/invoke?api-version=2022-05-01'
        }
        {
          name: 'LOGIC_APP_AUDIENCE'
          value: 'api://${logicAppEntraClientId}'
        }
        {
          name: 'WEBSITE_AUTH_AAD_ALLOWED_TENANTS'
          value: entraAppTenantId
        }
      ]
    }
  }
}

// ── Easy Auth on Function App ──
// The Function-level key protects the public trigger. AllowAnonymous avoids a
// separate delegated-user auth exercise before the managed-identity lesson.
resource functionAppAuthSettings 'Microsoft.Web/sites/config@2023-12-01' = {
  name: 'authsettingsV2'
  parent: functionApp
  properties: {
    platform: {
      enabled: true
      runtimeVersion: '~1'
    }
    globalValidation: {
      requireAuthentication: true
      unauthenticatedClientAction: 'AllowAnonymous'
    }
    httpSettings: {
      requireHttps: true
      routes: {
        apiPrefix: '/.auth'
      }
      forwardProxy: {
        convention: 'NoProxy'
      }
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: {
          openIdIssuer: uri('https://sts.windows.net/', entraAppTenantId)
          clientId: entraAppClientId
        }
        validation: {
          allowedAudiences: [
            entraAppClientId
            'api://${entraAppClientId}'
          ]
          defaultAuthorizationPolicy: {
            allowedPrincipals: length(allowedPrincipals) > 0
              ? { identities: allowedPrincipals }
              : {}
          }
        }
      }
    }
    login: {
      tokenStore: {
        enabled: false
      }
    }
  }
}

// ── RBAC: Function App managed identity → shared storage ──
// Required for identity-based AzureWebJobsStorage (no connection string).
var storageRoles = [
  {
    name: 'blob-owner'
    roleId: 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b' // Storage Blob Data Owner
  }
  {
    name: 'queue-contrib'
    roleId: '974c5e8b-45b9-4653-ba55-5f855dd0fb88' // Storage Queue Data Contributor
  }
  {
    name: 'table-contrib'
    roleId: '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3' // Storage Table Data Contributor
  }
  {
    name: 'account-contrib'
    roleId: '17d1049b-9a84-46fb-8f53-869881c3d3ab' // Storage Account Contributor
  }
  {
    name: 'fileshare-contrib'
    roleId: '0c867c2a-1d8c-454a-a3db-ab2ea1bdc8bb' // Storage File Data SMB Share Contributor
  }
]

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource storageRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for role in storageRoles: {
    name: guid(storageAccountId, functionApp.id, role.roleId)
    scope: storageAccount
    properties: {
      principalId: functionApp.identity.principalId
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', role.roleId)
      principalType: 'ServicePrincipal'
    }
  }
]

// ── Outputs ──
output functionAppName string = functionApp.name
output functionAppDefaultHostname string = functionApp.properties.defaultHostName
output functionAppResourceId string = functionApp.id
// Used by main.bicep to wire into the Logic App Easy Auth allowedPrincipals
output functionAppPrincipalId string = functionApp.identity.principalId
