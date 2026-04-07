targetScope = 'resourceGroup'

// ──────────────────────────────────────────────
// Easy Auth (AuthSettingsV2) configuration module
// ──────────────────────────────────────────────

@description('Name of the Logic App to configure Easy Auth on.')
param logicAppName string

@description('Unauthenticated client action – the key toggle for this lab.')
@allowed([
  'Return401'
  'AllowAnonymous'
])
param easyAuthMode string

@description('Entra ID (AAD) application client ID.')
param entraAppClientId string

@description('Entra ID tenant ID.')
param entraAppTenantId string

@description('Allowed token audiences. Defaults to the client ID.')
param allowedAudiences array = [entraAppClientId]

@description('Allowed principal (object) IDs. When non-empty, restricts access to these identities.')
param allowedPrincipals array = []

var hasAllowedPrincipals = length(allowedPrincipals) > 0

resource authSettings 'Microsoft.Web/sites/config@2023-12-01' = {
  name: '${logicAppName}/authsettingsV2'
  properties: {
    platform: {
      enabled: true
    }
    globalValidation: {
      unauthenticatedClientAction: easyAuthMode
      redirectToProvider: 'azureActiveDirectory'
      // Exclude runtime management paths so portal + ARM proxy calls are not blocked
      excludedPaths: [
        '/runtime/webhooks/*'
        '/hostruntime/*'
      ]
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: {
          openIdIssuer: 'https://sts.windows.net/${entraAppTenantId}/v2.0'
          clientId: entraAppClientId
        }
        validation: {
          allowedAudiences: allowedAudiences
          defaultAuthorizationPolicy: {
            allowedPrincipals: hasAllowedPrincipals
              ? {
                  identities: allowedPrincipals
                }
              : {}
          }
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
output easyAuthMode string = easyAuthMode
