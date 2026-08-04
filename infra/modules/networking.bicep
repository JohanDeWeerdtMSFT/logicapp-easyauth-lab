targetScope = 'resourceGroup'

// ──────────────────────────────────────────────
// Networking module
// VNet, subnets, and private DNS zone for the
// Function App → Logic App private-endpoint demo
//
// Subnets:
//   snet-app-integration  (10.0.0.0/24) — VNet integration for Function App + Logic App (outbound)
//   snet-privateendpoints (10.0.1.0/24) — inbound private endpoints (no service delegation)
// ──────────────────────────────────────────────

@description('Environment name used in resource naming.')
param environmentName string

@description('Azure region for all network resources.')
param location string

@description('Name of the shared storage account that requires private connectivity.')
param storageAccountName string

var baseName = 'la-easyauth-lab-${environmentName}'
var vnetName = '${baseName}-vnet'
var storagePrivateLinkServices = [
  {
    groupId: 'blob'
    dnsZoneName: 'privatelink.blob.${environment().suffixes.storage}'
  }
  {
    groupId: 'queue'
    dnsZoneName: 'privatelink.queue.${environment().suffixes.storage}'
  }
  {
    groupId: 'table'
    dnsZoneName: 'privatelink.table.${environment().suffixes.storage}'
  }
  {
    groupId: 'file'
    dnsZoneName: 'privatelink.file.${environment().suffixes.storage}'
  }
]

resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: ['10.0.0.0/16']
    }
    subnets: [
      {
        name: 'snet-app-integration'
        properties: {
          addressPrefix: '10.0.0.0/24'
          // Required delegation for App Service / Logic App Standard VNet integration
          delegations: [
            {
              name: 'delegation-webfarms'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
      {
        name: 'snet-privateendpoints'
        properties: {
          addressPrefix: '10.0.1.0/24'
          // Must be Disabled to allow private endpoint NIC placement
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

// ── Private DNS zone — resolves *.azurewebsites.net to private IPs ──
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.azurewebsites.net'
  location: 'global'
}

// Link the DNS zone to the VNet so all VMs/apps in the VNet use private resolution
resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: '${baseName}-vnet-link'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

// Logic Apps Standard and Azure Functions hosts require Blob, Queue, Table, and File access.
resource storagePrivateDnsZones 'Microsoft.Network/privateDnsZones@2020-06-01' = [for service in storagePrivateLinkServices: {
  name: service.dnsZoneName
  location: 'global'
}]

resource storagePrivateDnsZoneLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (service, index) in storagePrivateLinkServices: {
  parent: storagePrivateDnsZones[index]
  name: '${baseName}-${service.groupId}-vnet-link'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}]

resource storagePrivateEndpoints 'Microsoft.Network/privateEndpoints@2024-01-01' = [for service in storagePrivateLinkServices: {
  name: 'pe-${storageAccountName}-${service.groupId}'
  location: location
  properties: {
    subnet: {
      id: vnet.properties.subnets[1].id
    }
    privateLinkServiceConnections: [
      {
        name: 'plsc-${storageAccountName}-${service.groupId}'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [service.groupId]
        }
      }
    ]
  }
}]

resource storagePrivateDnsZoneGroups 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-01-01' = [for (service, index) in storagePrivateLinkServices: {
  parent: storagePrivateEndpoints[index]
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-${service.groupId}'
        properties: {
          privateDnsZoneId: storagePrivateDnsZones[index].id
        }
      }
    ]
  }
}]

// ── Outputs ──
output vnetId string = vnet.id
// Subnet IDs — referenced by apps for VNet integration and private endpoint placement
output appIntegrationSubnetId string = vnet.properties.subnets[0].id
output privateEndpointSubnetId string = vnet.properties.subnets[1].id
output privateDnsZoneId string = privateDnsZone.id
output privateDnsZoneName string = privateDnsZone.name
