targetScope = 'resourceGroup'

// ══════════════════════════════════════════════════════════════
// APIM Lab – Logic App Standard without Easy Auth
// JWT validation done centrally at APIM instead of on the host
// ══════════════════════════════════════════════════════════════

@description('Environment name (e.g. dev, test, prod). Used in resource names.')
param environmentName string = 'dev'

@description('Primary Azure region.')
param location string = 'westeurope'

@description('Entra ID application (client) ID for JWT validation.')
param entraAppClientId string

@description('Entra ID tenant ID.')
param entraAppTenantId string

@description('APIM publisher email.')
param publisherEmail string = 'lab@contoso.com'

@description('APIM publisher name.')
param publisherName string = 'EasyAuth Lab'

// ── Naming ─────────────────────────────────────
var baseName = 'la-easyauth-lab-apim-${environmentName}'
var suffix = uniqueString(resourceGroup().id)
var storageRawName = replace('${baseName}${suffix}', '-', '')
var storageAccountName = toLower(take(storageRawName, 24))
var tags = {
  lab: 'apim'
  project: 'la-easyauth-lab'
}

// ══════════════════════════════════════════════════════════════
// 1. Storage Account
// ══════════════════════════════════════════════════════════════
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowSharedKeyAccess: false
  }
}

// ══════════════════════════════════════════════════════════════
// 2. App Service Plan (WorkflowStandard WS1)
// ══════════════════════════════════════════════════════════════
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${baseName}-plan'
  location: location
  tags: tags
  sku: {
    tier: 'WorkflowStandard'
    name: 'WS1'
  }
  kind: 'elastic'
  properties: {
    maximumElasticWorkerCount: 20
  }
}

// ══════════════════════════════════════════════════════════════
// 3. Log Analytics + Application Insights
// ══════════════════════════════════════════════════════════════
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${baseName}-law'
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${baseName}-ai'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

// ══════════════════════════════════════════════════════════════
// 4. Logic App Standard – NO Easy Auth
// ══════════════════════════════════════════════════════════════
var storageBlobUri = 'https://${storageAccountName}.blob.${environment().suffixes.storage}'
var storageQueueUri = 'https://${storageAccountName}.queue.${environment().suffixes.storage}'
var storageTableUri = 'https://${storageAccountName}.table.${environment().suffixes.storage}'
var logicAppName = '${baseName}-la-${suffix}'

resource logicApp 'Microsoft.Web/sites@2023-12-01' = {
  name: logicAppName
  location: location
  tags: tags
  kind: 'functionapp,workflowapp'
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      netFrameworkVersion: 'v6.0'
      appSettings: [
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
          value: appInsights.properties.ConnectionString
        }
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
    }
  }
}

// ══════════════════════════════════════════════════════════════
// 5. RBAC – Logic App MI → Storage
// ══════════════════════════════════════════════════════════════
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
    name: guid(storageAccount.id, logicApp.id, role.roleId)
    scope: storageAccount
    properties: {
      principalId: logicApp.identity.principalId
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', role.roleId)
      principalType: 'ServicePrincipal'
    }
  }
]

// ══════════════════════════════════════════════════════════════
// 6. API Management (Developer SKU)
// ══════════════════════════════════════════════════════════════
resource apim 'Microsoft.ApiManagement/service@2023-09-01-preview' = {
  name: '${baseName}-apim-${suffix}'
  location: location
  tags: tags
  sku: {
    name: 'Developer'
    capacity: 1
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
}

// ── Named Values ──
resource nvTenantId 'Microsoft.ApiManagement/service/namedValues@2023-09-01-preview' = {
  parent: apim
  name: 'tenant-id'
  properties: {
    displayName: 'tenant-id'
    value: entraAppTenantId
    secret: false
  }
}

resource nvClientId 'Microsoft.ApiManagement/service/namedValues@2023-09-01-preview' = {
  parent: apim
  name: 'client-id'
  properties: {
    displayName: 'client-id'
    value: entraAppClientId
    secret: false
  }
}

// ── Backend ──
resource apimBackend 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apim
  name: 'logic-app-backend'
  properties: {
    url: 'https://${logicApp.properties.defaultHostName}'
    protocol: 'http'
    description: 'Logic App Standard backend (no Easy Auth)'
  }
}

// ── API definition ──
var jwtPolicyXml = '''
<policies>
    <inbound>
        <base />
        <validate-jwt header-name="Authorization" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized. Valid Entra ID bearer token required." require-expiration-time="true" require-scheme="Bearer" require-signed-tokens="true">
            <openid-config url="https://login.microsoftonline.com/{{tenant-id}}/v2.0/.well-known/openid-configuration" />
            <audiences>
                <audience>{{client-id}}</audience>
            </audiences>
            <issuers>
                <issuer>https://login.microsoftonline.com/{{tenant-id}}/v2.0</issuer>
                <issuer>https://sts.windows.net/{{tenant-id}}/</issuer>
            </issuers>
        </validate-jwt>
        <set-header name="X-Authenticated-User" exists-action="override">
            <value>@(context.Request.Headers.GetValueOrDefault("Authorization","").AsJwt()?.Subject)</value>
        </set-header>
    </inbound>
    <backend>
        <base />
    </backend>
    <outbound>
        <base />
    </outbound>
    <on-error>
        <base />
    </on-error>
</policies>
'''

resource api 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' = {
  parent: apim
  name: 'logic-app-workflows'
  properties: {
    displayName: 'Logic App Workflows'
    path: 'workflows'
    protocols: [ 'https' ]
    serviceUrl: 'https://${logicApp.properties.defaultHostName}'
    subscriptionRequired: false
    apiType: 'http'
  }
  dependsOn: [ nvTenantId, nvClientId ]
}

resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-09-01-preview' = {
  parent: api
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: jwtPolicyXml
  }
}

// Catch-all operation so any path under /workflows/* is proxied
resource apiOperationGet 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: api
  name: 'get-all'
  properties: {
    displayName: 'GET all paths'
    method: 'GET'
    urlTemplate: '/*'
  }
}

resource apiOperationPost 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: api
  name: 'post-all'
  properties: {
    displayName: 'POST all paths'
    method: 'POST'
    urlTemplate: '/*'
  }
}

// ══════════════════════════════════════════════════════════════
// Outputs
// ══════════════════════════════════════════════════════════════
output logicAppName string = logicApp.name
output logicAppDefaultHostname string = logicApp.properties.defaultHostName
output logicAppResourceId string = logicApp.id
output logicAppPrincipalId string = logicApp.identity.principalId
output storageAccountName string = storageAccount.name
output appServicePlanId string = appServicePlan.id
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output apimName string = apim.name
output apimGatewayUrl string = apim.properties.gatewayUrl
