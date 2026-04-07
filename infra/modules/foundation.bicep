targetScope = 'resourceGroup'

// ──────────────────────────────────────────────
// Foundation module – storage, plan, monitoring
// ──────────────────────────────────────────────

@description('Environment name used in resource naming (e.g. dev, test, prod).')
param environmentName string

@description('Azure region for all resources.')
param location string

var baseName = 'la-easyauth-lab-${environmentName}'
var suffix = uniqueString(resourceGroup().id)

// ── Storage Account (required by Logic App Standard) ──
var storageRawName = replace('${baseName}${suffix}', '-', '')
#disable-next-line BCP334 // Name is always long enough given the baseName constant
var storageAccountName = toLower(take(storageRawName, 24))

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  #disable-next-line BCP334 // Name is always ≥3 chars given the baseName constant
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
  }
}

// ── App Service Plan (WorkflowStandard WS1) ──
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${baseName}-plan'
  location: location
  sku: {
    tier: 'WorkflowStandard'
    name: 'WS1'
  }
  kind: 'elastic'
  properties: {
    maximumElasticWorkerCount: 20
  }
}

// ── Log Analytics Workspace ──
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${baseName}-law'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// ── Application Insights ──
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${baseName}-ai'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

// ── Outputs ──
output storageAccountName string = storageAccount.name
output storageAccountId string = storageAccount.id
output appServicePlanId string = appServicePlan.id
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output logAnalyticsWorkspaceId string = logAnalytics.id
