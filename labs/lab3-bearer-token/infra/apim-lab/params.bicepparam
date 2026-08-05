using 'main.bicep'

param environmentName = 'dev'
param location = 'westeurope'
// Replace before deployment. Find both values under Microsoft Entra ID:
// App registrations > Logic App API registration > Application (client) ID,
// and Overview > Tenant ID.
param entraAppClientId = 'REPLACE-WITH-LOGIC-APP-CLIENT-ID'
param entraAppTenantId = 'REPLACE-WITH-TENANT-ID'
param publisherEmail = 'lab@contoso.com'
param publisherName = 'EasyAuth Lab'
