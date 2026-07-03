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

var baseName = 'la-easyauth-lab-${environmentName}'
var vnetName = '${baseName}-vnet'

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

// ── Outputs ──
output vnetId string = vnet.id
// Subnet IDs — referenced by apps for VNet integration and private endpoint placement
output appIntegrationSubnetId string = vnet.properties.subnets[0].id
output privateEndpointSubnetId string = vnet.properties.subnets[1].id
output privateDnsZoneId string = privateDnsZone.id
output privateDnsZoneName string = privateDnsZone.name
