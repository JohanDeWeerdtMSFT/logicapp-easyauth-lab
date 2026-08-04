targetScope = 'resourceGroup'

// ──────────────────────────────────────────────
// Easy Auth (AuthSettingsV2) configuration module
// ──────────────────────────────────────────────
//
// References:
// - https://learn.microsoft.com/en-us/community/content/secure-integration-workflows-azure-logic-apps-api-management#method-2-security-using-easy-auth
// - https://azcloudsecurity.io/posts/logic-app-standard-easy-auth/
// - https://learn.microsoft.com/en-us/azure/app-service/overview-authentication-authorization#considerations-for-using-built-in-authentication
//
// Key design decisions:
// - Uses AllowAnonymous (NOT Return401) — Microsoft explicitly warns that Return401
//   breaks the portal experience because requests never reach the Logic Apps runtime.
// - Requests WITH an Authorization header are still validated by Easy Auth.
// - platform.enabled + runtimeVersion ~1 are required for Easy Auth to function.
// - MICROSOFT_PROVIDER_AUTHENTICATION_SECRET must be set as an app setting (Key Vault ref).
// - allowedPrincipals restricts access to specific identities (e.g., APIM managed identity).

@description('Name of the Logic App to configure Easy Auth on.')
param logicAppName string

@description('Unauthenticated client action – AllowAnonymous is required for Logic Apps Standard portal manageability.')
@allowed([
  'AllowAnonymous'
  'Return401'
])
param easyAuthMode string = 'AllowAnonymous'

@description('Entra ID (AAD) application client ID (the App Registration representing the Logic App).')
param entraAppClientId string

@description('Entra ID tenant ID.')
param entraAppTenantId string

@description('Allowed token audiences. Defaults to the Application ID URI (api://<client-id>) of the Logic App app registration, which is the audience requested by the caller Function App.')
param allowedAudiences array = [
  'api://${entraAppClientId}'
]

@description('Allowed principal (object) IDs. Restricts access to these identities (e.g., APIM system-assigned managed identity principal ID).')
param allowedPrincipals array = []

@description('Name of the app setting that holds the client secret (typically a Key Vault reference). Leave empty to skip.')
#disable-next-line secure-secrets-in-params
param clientSecretSettingName string = 'MICROSOFT_PROVIDER_AUTHENTICATION_SECRET'

var hasAllowedPrincipals = length(allowedPrincipals) > 0

resource logicApp 'Microsoft.Web/sites@2023-12-01' existing = {
  name: logicAppName
}

resource authSettings 'Microsoft.Web/sites/config@2023-12-01' = {
  parent: logicApp
  name: 'authsettingsV2'
  properties: {
    platform: {
      enabled: true
      runtimeVersion: '~1'
    }
    globalValidation: {
      requireAuthentication: true
      unauthenticatedClientAction: easyAuthMode
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
          clientSecretSettingName: empty(clientSecretSettingName) ? null : clientSecretSettingName
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
