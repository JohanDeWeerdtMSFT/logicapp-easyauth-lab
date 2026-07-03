targetScope = 'resourceGroup'

// ──────────────────────────────────────────────
// Logic App Standard module
// Uses managed-identity storage (no shared keys)
// ──────────────────────────────────────────────

@description('Environment name used in resource naming.')
param environmentName string

@description('Azure region for the Logic App.')
param location string

@description('Resource ID of the App Service Plan.')
param appServicePlanId string

@description('Name of the storage account used by the Logic App.')
param storageAccountName string

@description('Resource ID of the storage account.')
param storageAccountId string

@description('Application Insights connection string.')
param appInsightsConnectionString string

@description('Entra ID tenant ID — used for WEBSITE_AUTH_AAD_ALLOWED_TENANTS.')
param entraAppTenantId string = ''

@description('Subnet resource ID for outbound VNet integration. Leave empty to skip VNet integration.')
param vnetIntegrationSubnetId string = ''

@description('Subnet resource ID for the inbound private endpoint. Leave empty to skip (public access remains enabled).')
param privateEndpointSubnetId string = ''

@description('Resource ID of the privatelink.azurewebsites.net private DNS zone. Required when privateEndpointSubnetId is set.')
param privateDnsZoneId string = ''

var baseName = 'la-easyauth-lab-${environmentName}'
var suffix = uniqueString(resourceGroup().id)
var logicAppName = '${baseName}-la-${suffix}'
var storageBlobUri = 'https://${storageAccountName}.blob.${environment().suffixes.storage}'
var storageQueueUri = 'https://${storageAccountName}.queue.${environment().suffixes.storage}'
var storageTableUri = 'https://${storageAccountName}.table.${environment().suffixes.storage}'

var baseAppSettings = [
  // Identity-based storage (no shared keys required)
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
    value: 'node'
  }
  {
    name: 'WEBSITE_NODE_DEFAULT_VERSION'
    value: '~18'
  }
  // Monitoring
  {
    name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
    value: appInsightsConnectionString
  }
  // Logic App Standard
  {
    name: 'APP_KIND'
    value: 'workflowApp'
  }
  {
    name: 'AzureFunctionsJobHost__extensionBundle__id'
    value: 'Microsoft.Azure.Functions.ExtensionBundle.Workflows'
  }
  {
    name: 'AzureFunctionsJobHost__extensionBundle__version'
    value: '[1.*, 2.0.0)'
  }
]

// Tenant restriction for Easy Auth (required for proper tenant validation)
var tenantAppSetting = empty(entraAppTenantId) ? [] : [
  {
    name: 'WEBSITE_AUTH_AAD_ALLOWED_TENANTS'
    value: entraAppTenantId
  }
]

var allAppSettings = concat(baseAppSettings, tenantAppSetting)

var hasVnetIntegration = !empty(vnetIntegrationSubnetId)
var hasPrivateEndpoint = !empty(privateEndpointSubnetId)

resource logicApp 'Microsoft.Web/sites@2023-12-01' = {
  name: logicAppName
  location: location
  kind: 'functionapp,workflowapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlanId
    httpsOnly: true
    // Disable public inbound access when a private endpoint is configured
    publicNetworkAccess: hasPrivateEndpoint ? 'Disabled' : 'Enabled'
    // Outbound VNet integration — routes egress through the VNet
    virtualNetworkSubnetId: hasVnetIntegration ? vnetIntegrationSubnetId : null
    vnetRouteAllEnabled: hasVnetIntegration
    siteConfig: {
      netFrameworkVersion: 'v6.0'
      appSettings: allAppSettings
    }
  }
}

// ── Private Endpoint (inbound) ──
// Exposes the Logic App on the VNet so only callers within the VNet
// (or via private peering) can reach the HTTP trigger endpoint.
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-01-01' = if (hasPrivateEndpoint) {
  name: 'pe-${logicAppName}'
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'plsc-${logicAppName}'
        properties: {
          privateLinkServiceId: logicApp.id
          groupIds: ['sites']
        }
      }
    ]
  }
}

// ── Private DNS Zone Group ──
// Automatically registers the private endpoint NIC IP as an A record
// in the privatelink.azurewebsites.net zone so DNS resolves to the private IP.
resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-01-01' = if (hasPrivateEndpoint && !empty(privateDnsZoneId)) {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-azurewebsites-net'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

// ── RBAC: Logic App managed identity → Storage ──
// Required roles for identity-based AzureWebJobsStorage
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

resource roleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for role in storageRoles: {
    name: guid(storageAccountId, logicApp.id, role.roleId)
    scope: storageAccount
    properties: {
      principalId: logicApp.identity.principalId
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', role.roleId)
      principalType: 'ServicePrincipal'
    }
  }
]

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

// ── Outputs ──
output logicAppName string = logicApp.name
output logicAppDefaultHostname string = logicApp.properties.defaultHostName
output logicAppResourceId string = logicApp.id
output logicAppPrincipalId string = logicApp.identity.principalId
output privateEndpointId string = hasPrivateEndpoint ? privateEndpoint.id : ''
