# Lab 3: Managed Identity Bearer Token Authentication Flow

**No SAS Tokens. No Connection Strings. Pure Identity-Based Authentication.**

---

## Overview

Lab 3 demonstrates how a **Function App can call a Logic App without using SAS tokens** by leveraging:
1. **Azure Managed Identity** — automatic credential management (no secrets to store/rotate)
2. **Bearer Tokens** — short-lived Entra ID access tokens used for request authentication
3. **Easy Auth** — built-in Azure App Service authentication middleware

This pattern is **production-ready** and aligns with Zero Trust security principles.

---

## Architecture Diagram

```mermaid
graph TD
    A["Function App<br/>(la-easyauth-lab-dev-caller)"] -->|1. Request Bearer Token<br/>Audience: Logic App Entra ID App| B["Azure Entra ID<br/>Security Token Service"]
    B -->|2. Return Access Token<br/>aud=Logic App Entra ID App| A
    A -->|3. HTTPS Request<br/>Authorization: Bearer &#60;token&#62;<br/>Host: la-easyauth-lab-dev-la.azurewebsites.net| C["Private DNS Zone<br/>(privatelink.azurewebsites.net)"]
    C -->|4. Resolve to<br/>Private Endpoint IP<br/>10.0.1.x| D["Private Endpoint<br/>for Logic App<br/>snet-privateendpoints"]
    D -->|5. Route to<br/>Logic App| E["Logic App Standard<br/>la-easyauth-lab-dev-la"]
    E -->|6. Easy Auth Middleware<br/>Validate Token Signature<br/>Check Audience<br/>Check allowedPrincipals| F["Token Validation<br/>✓ Signature valid<br/>✓ Aud matches<br/>✓ Principal in allowedPrincipals"]
    F -->|7. Request Forwarded to Workflow| E
    E -->|8. Workflow Executes<br/>Returns 200 OK| A
```

---

## Step-by-Step Flow Explanation

### Step 1: Function App Acquires Bearer Token

**What Happens:**
The Function App uses its **system-assigned managed identity** to request an access token from Azure Entra ID.

**Key Configuration (from Bicep):**
```bicep
// infra/modules/functionapp-caller.bicep
identity: {
  type: 'SystemAssigned'
}
```

The managed identity is automatically created by Azure and assigned a **principal ID** (object ID in Entra ID). This principal ID is later used by Easy Auth to restrict access.

**C# Code Example (in Function App):**
```csharp
using Azure.Identity;
using Azure.Core;

// Inside an Azure Function handler
public static async Task<IActionResult> Run(HttpRequest req, ILogger log)
{
    // The DefaultAzureCredential uses the system-assigned managed identity
    // when running in Azure App Service (no configuration needed).
    var credential = new DefaultAzureCredential();
    
    // Acquire token for Logic App
    // The "audience" (aud) claim in the token will be set to this scope
    var logicAppEntraClientId = Environment.GetEnvironmentVariable("LOGIC_APP_AUDIENCE");
    var tokenRequestContext = new TokenRequestContext(
        new[] { $"{logicAppEntraClientId}/.default" }
    );
    
    // Request the token from Entra ID STS
    // This call internally uses the managed identity credentials
    var tokenResponse = await credential.GetTokenAsync(tokenRequestContext);
    var accessToken = tokenResponse.Token;
    
    log.LogInformation($"Token acquired, expires: {tokenResponse.ExpiresOn}");
    
    // Use the token in the next step...
    return new OkResult();
}
```

**What Gets Requested:**
```
POST https://login.microsoftonline.com/{tenant-id}/oauth2/v2.0/token

Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials
&client_id={function-app-principal-id}
&client_secret={managed-identity-secret-from-azure-metadata-service}
&scope=api://{logic-app-entra-app-id}/.default
```

**Important:** The `client_secret` is never stored in code or configuration. Azure Entra ID provides it through the **Managed Identity Metadata Service** running on the compute host.

**Token Response:**
```json
{
  "access_token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsIng1dCI6IjEyMzQ1Njc4OTA....",
  "token_type": "Bearer",
  "expires_in": 3600,
  "ext_expires_in": 3600,
  "expires_on": 1719057654,
  "resource": "api://logic-app-entra-app-id",
  "scope": "api://logic-app-entra-app-id/.default"
}
```

**Token Content (JWT Claims):**
```json
{
  "aud": "api://logic-app-entra-app-id",      // ← Audience (Logic App)
  "iss": "https://sts.windows.net/tenant-id/",
  "iat": 1719054054,
  "nbf": 1719054054,
  "exp": 1719057654,                           // ← Expires in 1 hour
  "aio": "...",
  "appid": "function-app-principal-id",       // ← Function App's principal
  "appidacr": "2",
  "oid": "function-app-principal-id",
  "sub": "function-app-principal-id",
  "tid": "tenant-id",
  "uti": "...",
  "ver": "1.0"
}
```

### Step 2: Function App Sends HTTP Request with Bearer Token

**What Happens:**
The Function App makes an HTTPS request to the Logic App endpoint, including the bearer token in the `Authorization` header.

**C# Code Example:**
```csharp
using System.Net.Http;

// Continue from previous token acquisition...
var accessToken = tokenResponse.Token;
var logicAppUrl = Environment.GetEnvironmentVariable("LOGIC_APP_URL");

// Create HTTP client
using var httpClient = new HttpClient();

// Add Authorization header with bearer token
httpClient.DefaultRequestHeaders.Authorization = 
    new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", accessToken);

try
{
    // Make request to Logic App
    var response = await httpClient.PostAsync(
        logicAppUrl,
        new StringContent(
            JsonConvert.SerializeObject(new { message = "Hello from Function App" }),
            System.Text.Encoding.UTF8,
            "application/json"
        )
    );
    
    if (response.IsSuccessStatusCode)
    {
        log.LogInformation($"Logic App returned: {response.StatusCode}");
        return new OkResult();
    }
    else
    {
        log.LogError($"Logic App returned error: {response.StatusCode}");
        return new BadRequestResult();
    }
}
catch (HttpRequestException ex)
{
    log.LogError($"Network error calling Logic App: {ex.Message}");
    return new BadRequestResult();
}
```

**HTTP Request on the Wire:**
```
POST https://la-easyauth-lab-dev-la-daaq6t5xzrpaw.azurewebsites.net/api/httpTriggerWorkflow/triggers/manual/invoke?api-version=2022-05-01 HTTP/1.1
Host: la-easyauth-lab-dev-la-daaq6t5xzrpaw.azurewebsites.net
Authorization: Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsIng1dCI6IjEyMzQ1Njc4OTA....
Content-Type: application/json
Content-Length: 42
X-Forwarded-Proto: https

{"message":"Hello from Function App"}
```

**Network Routing:**
1. Function App queries private DNS zone: `la-easyauth-lab-dev-la-daaq6t5xzrpaw.azurewebsites.net`
2. Private DNS zone returns private endpoint IP: `10.0.1.5` (example)
3. Request is routed through VNet to private endpoint
4. Private endpoint routes to Logic App (bypassing public internet)

### Step 3: Private DNS Resolution

**What Happens:**
The DNS query for the Logic App hostname is intercepted by the private DNS zone and resolved to the **private endpoint IP** instead of the public IP.

**Bicep Configuration:**
```bicep
// infra/modules/logicapp.bicep
// Private DNS zone for *.azurewebsites.net
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.azurewebsites.net'
  location: 'global'
}

// Link private DNS zone to Function App's VNet
resource dnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: '${environmentName}-vnet-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

// A record pointing Logic App name to private endpoint IP
resource privateDnsARecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  parent: privateDnsZone
  name: logicAppName
  properties: {
    ttl: 3600
    aRecords: [
      {
        ipv4Address: privateEndpointNicIpAddress
      }
    ]
  }
}
```

**DNS Resolution Process:**
```
Function App: nslookup la-easyauth-lab-dev-la-daaq6t5xzrpaw.azurewebsites.net
           ↓
Private DNS Zone (privatelink.azurewebsites.net)
           ↓
Return: 10.0.1.5 (private endpoint IP)
           ↓
(NOT: 52.166.234.100, the public IP that external callers would get)
```

### Step 4: Private Endpoint Routes Request to Logic App

**What Happens:**
The request arrives at the private endpoint network interface, which routes it to the Logic App backend.

**Bicep Configuration:**
```bicep
// infra/modules/logicapp.bicep
// Private Endpoint for Logic App
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-04-01' = {
  name: 'pe-${logicAppName}'
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'connection-${logicAppName}'
        properties: {
          privateLinkServiceId: logicApp.id
          groupIds: ['sites']
        }
      }
    ]
  }
}

// Logic App is configured to BLOCK public access
resource logicAppNetworkSettings 'Microsoft.Web/sites@2023-12-01' = {
  name: logicAppName
  properties: {
    publicNetworkAccess: 'Disabled'  // ← Only private endpoint allowed
    virtualNetworkSubnetId: vnetIntegrationSubnetId
    vnetRouteAllEnabled: true
  }
}
```

**Key Point:** When `publicNetworkAccess: Disabled`, the Logic App:
- ✅ **Accepts** requests from private endpoint
- ❌ **Rejects** requests from public internet (e.g., `curl https://logic-app.azurewebsites.net`)

### Step 5: Easy Auth Middleware Validates Bearer Token

**What Happens:**
Before the request reaches the Logic App workflow, the **Easy Auth middleware** intercepts it and validates the bearer token.

**Easy Auth Configuration (Bicep):**
```bicep
// infra/modules/easyauth.bicep
resource easyAuthSettings 'Microsoft.Web/sites/config@2023-12-01' = {
  name: 'authsettingsV2'
  parent: logicApp
  properties: {
    platform: {
      enabled: true
      runtimeVersion: '~2'
    }
    globalValidation: {
      requireAuthentication: true
      unauthenticatedClientAction: 'AllowAnonymous'  // ← Allows portal access
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: {
          clientId: entraAppClientId
          openIdIssuer: uri('https://sts.windows.net/', entraAppTenantId)
        }
        validation: {
          allowedAudiences: [
            entraAppClientId
            'api://${entraAppClientId}'
          ]
          // ← CRITICAL: Restrict to specific principals (Function App's MI)
          defaultAuthorizationPolicy: {
            allowedPrincipals: {
              identities: [
                functionAppPrincipalId  // Function App's system-assigned MI
              ]
            }
          }
        }
      }
    }
  }
}
```

**Validation Steps (in order):**

1. **Parse Bearer Token**
   ```
   Authorization Header: "Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsIng1dCI6IjEyMzQ1Njc4OTA...."
   ↓
   Extract token: "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsIng1dCI6IjEyMzQ1Njc4OTA...."
   ```

2. **Verify Token Signature**
   ```
   - Download Entra ID public key from: https://sts.windows.net/{tenant-id}/discovery/v2.0/keys
   - Verify JWT signature using RS256 algorithm
   - If invalid: Return 401 Unauthorized
   ```

3. **Check Token Claims**
   ```json
   {
     "aud": "api://logic-app-entra-app-id",   // ← Must match configured audience
     "iss": "https://sts.windows.net/tenant-id/",  // ← Must match tenant
     "exp": 1719057654,                       // ← Must be in the future
     "appid": "function-app-principal-id",    // ← Must be in allowedPrincipals
   }
   ```

4. **Check allowedPrincipals Filter**
   ```
   Extract "appid" or "oid" claim from token: "function-app-principal-id"
   ↓
   Check if in allowedPrincipals list: [function-app-principal-id]
   ↓
   If match: ✅ Allow request to proceed
   If no match: ❌ Return 403 Forbidden
   ```

**Easy Auth Decision Tree:**
```mermaid
graph TD
    A["Request arrives with<br/>Authorization: Bearer token"] --> B["Parse JWT"]
    B --> C["Verify Signature"]
    C -->|Invalid| D["❌ Return 401<br/>Unauthorized"]
    C -->|Valid| E["Check Audience Claim"]
    E -->|Doesn't match| D
    E -->|Matches| F["Check Token Expiry"]
    F -->|Expired| D
    F -->|Valid| G["Extract Principal<br/>appid/oid claim"]
    G --> H["Check allowedPrincipals"]
    H -->|Not in list| I["❌ Return 403<br/>Forbidden"]
    H -->|In list| J["✅ Allow request<br/>Forward to workflow"]
    J --> K["Workflow Executes"]
    K --> L["Return 200 OK"]
```

### Step 6: Request Reaches Workflow

**What Happens:**
Once Easy Auth validates the token and confirms the principal is in the allowedPrincipals list, the HTTP trigger fires and the workflow executes.

**Logic App HTTP Trigger (from deployment):**
```json
{
  "type": "Request",
  "kind": "Http",
  "inputs": {
    "schema": {
      "type": "object",
      "properties": {
        "message": {
          "type": "string"
        }
      }
    }
  },
  "runAfter": {}
}
```

**Workflow receives:**
```json
{
  "message": "Hello from Function App",
  "headers": {
    "Authorization": "Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsIng1dCI6IjEyMzQ1Njc4OTA....",
    "Host": "la-easyauth-lab-dev-la-daaq6t5xzrpaw.azurewebsites.net",
    "X-Forwarded-Proto": "https"
  },
  "principalId": "function-app-principal-id"  // ← Injected by Easy Auth
}
```

---

## Comparison: SAS Token vs. Bearer Token

| Aspect | SAS Token (❌ Avoided) | Bearer Token (✅ Used in Lab 3) |
|--------|------------------|---------------------|
| **Storage** | Must be stored in app settings / Key Vault | Acquired on-demand from Entra ID |
| **Rotation** | Manual (set new secret, rotate app settings) | Automatic (1-hour expiry, renewed on each request) |
| **Scope** | Typically broad (all operations on resource) | Scoped to specific Entra app audience |
| **Credential Type** | Symmetric key (both parties know the secret) | Asymmetric (public key signature validation) |
| **Auditability** | Limited (logs show "SAS key" was used) | Rich (logs show principal ID, tenant, timestamp) |
| **Integration** | Custom HTTP client code required | Built-in to Easy Auth middleware |
| **Scalability** | OK for small solutions | Better for large deployments (identity-based) |
| **Security** | Moderate (risk if secret is compromised) | Strong (no long-lived secrets in code) |

---

## Application Settings Required

**Function App Configuration** (infra/modules/functionapp-caller.bicep):
```bicep
{
  name: 'LOGIC_APP_URL'
  value: 'https://${logicAppHostname}/api/httpTriggerWorkflow/triggers/manual/invoke?api-version=2022-05-01'
}
{
  name: 'LOGIC_APP_AUDIENCE'
  value: 'api://${logicAppEntraClientId}'
}
{
  name: 'WEBSITE_AUTH_AAD_ALLOWED_TENANTS'
  value: entraAppTenantId
}
```

**What They Do:**
- `LOGIC_APP_URL` — The endpoint to call (includes private endpoint DNS name)
- `LOGIC_APP_AUDIENCE` — The audience claim expected in the bearer token (matches Logic App's Entra app ID)
- `WEBSITE_AUTH_AAD_ALLOWED_TENANTS` — Restricts token validation to the correct tenant

---

## Error Scenarios & Troubleshooting

### Scenario 1: Invalid Token Signature

**Error:**
```
HTTP/1.1 401 Unauthorized
www-authenticate: Bearer realm="https://login.microsoftonline.com/{tenant}/oauth2/authorize", error="invalid_token", error_description="The access token is not valid"
```

**Causes:**
- Token was issued by a different tenant
- Entra ID public key validation failed
- Token was tampered with

**Fix:**
- Verify `entraAppTenantId` is correct in app settings
- Check that Entra app registrations are in the same tenant

### Scenario 2: Audience Mismatch

**Error:**
```
HTTP/1.1 401 Unauthorized
error=invalid_aud
```

**Cause:**
- Token was issued for a different audience than the Logic App expects

**Example:**
```
Token aud claim: "api://function-app-entra-id"  ❌ Wrong
Expected aud:   "api://logic-app-entra-id"      ✅ Correct
```

**Fix:**
- Verify `LOGIC_APP_AUDIENCE` environment variable matches the Logic App's Entra app ID
- Ensure token request uses the correct scope: `api://{logic-app-entra-id}/.default`

### Scenario 3: Principal Not in allowedPrincipals

**Error:**
```
HTTP/1.1 403 Forbidden
www-authenticate: Bearer realm="https://login.microsoftonline.com/{tenant}/oauth2/authorize", error="insufficient_claims"
```

**Cause:**
- Token is valid but the principal (Function App) is not in the allowedPrincipals list

**Fix:**
- Redeploy with the Function App's principal ID included in allowedPrincipals
- Or: Set allowedPrincipals to empty array to disable the filter (less secure)

### Scenario 4: Token Expired

**Error:**
```
HTTP/1.1 401 Unauthorized
error=token_expired
```

**Cause:**
- Bearer token is older than 1 hour

**Note:** The Function App code should handle this automatically by requesting a new token if the current one is expired.

### Scenario 5: Private Endpoint DNS Not Resolving

**Error:**
```
System.Net.Http.HttpRequestException: "Unable to resolve the remote name"
```

**Cause:**
- Private DNS zone is not linked to the Function App's VNet
- DNS zone A records are not configured
- Private endpoint network interface IP is incorrect

**Fix:**
- Verify private DNS zone is linked to VNet: `az network private-dns link vnet list --zone-name privatelink.azurewebsites.net`
- Check private endpoint NIC IP: `az network nic list --resource-group rg-la-easyauth-lab-dev`
- Verify A record in private DNS zone: `az network private-dns record-set a list --zone-name privatelink.azurewebsites.net`

---

## Microsoft Learn Documentation References

### Core Concepts

1. **Azure Managed Identities**
   - What are managed identities? https://learn.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/overview
   - How to use managed identities in Azure Functions: https://learn.microsoft.com/en-us/azure/azure-functions/functions-identity

2. **Bearer Token Authentication**
   - OAuth 2.0 Bearer Token Usage (RFC 6750): https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-oauth2/draft-ietf-oauth-v2-bearer
   - How to get an access token: https://learn.microsoft.com/en-us/azure/active-directory/develop/access-tokens
   - Azure.Identity DefaultAzureCredential: https://learn.microsoft.com/en-us/dotnet/api/azure.identity.defaultazurecredential

3. **Easy Auth**
   - App Service authentication and authorization: https://learn.microsoft.com/en-us/azure/app-service/overview-authentication-authorization
   - Easy Auth with Azure Active Directory: https://learn.microsoft.com/en-us/azure/app-service/configure-authentication-provider-aad

4. **Private Endpoints & DNS**
   - Azure Private Endpoints: https://learn.microsoft.com/en-us/azure/private-link/private-endpoints-overview
   - Private DNS zones: https://learn.microsoft.com/en-us/azure/dns/private-dns-overview
   - Azure App Service with private endpoints: https://learn.microsoft.com/en-us/azure/app-service/networking/private-endpoint

5. **VNet Integration**
   - App Service VNet integration: https://learn.microsoft.com/en-us/azure/app-service/web-sites-integrate-with-vnet
   - Egress with VNet integration: https://learn.microsoft.com/en-us/azure/app-service/configure-vnet-integration-routing

### Code Examples & Samples

6. **Azure SDK Token Acquisition**
   - Azure.Identity library: https://learn.microsoft.com/en-us/dotnet/api/overview/azure/identity-readme
   - Azure SDK for .NET: https://learn.microsoft.com/en-us/dotnet/azure/sdk/

7. **Logic App HTTP Triggers**
   - Call Logic Apps from Azure Functions: https://learn.microsoft.com/en-us/azure/logic-apps/logic-apps-http-endpoint
   - Logic App HTTP connector: https://learn.microsoft.com/en-us/connectors/connector-reference/connector-reference-logicapps-connectors#http

### Security Best Practices

8. **Zero Trust**
   - Azure Security Baseline: https://learn.microsoft.com/en-us/security/benchmark/azure/
   - Zero Trust architecture for app access: https://learn.microsoft.com/en-us/security/zero-trust/

9. **Service-to-Service Authentication**
   - How to authenticate service-to-service calls with managed identity: https://learn.microsoft.com/en-us/azure/app-service/scenario-secure-app-authentication-app-service

---

## Key Takeaways

✅ **No SAS Tokens Required**
- Function App acquires bearer tokens on-demand using its managed identity
- Tokens are short-lived (1 hour) and automatically refreshed

✅ **Network Isolation**
- Private endpoint ensures Logic App is not accessible from the public internet
- Private DNS ensures Function App resolves to the private IP, not public

✅ **Principal-Based Access Control**
- Easy Auth validates token signature and checks if the principal is in `allowedPrincipals`
- Only the Function App's managed identity can call the Logic App

✅ **Audit Trail**
- Every token acquisition and request is logged to Application Insights
- Azure AD sign-in logs track token requests
- Rich debugging information available in Log Analytics

✅ **Production Ready**
- Aligns with Microsoft Cloud Security Benchmark (MCSB)
- Implements Zero Trust principles
- Scalable to multiple callers (add more principals to `allowedPrincipals`)

---

## Related Documentation

- [Lab 1: Easy Auth Only](../docs/decision-guidance.md#lab-1-easy-auth-only)
- [Lab 2: APIM Gateway](../docs/decision-guidance.md#lab-2-apim-gateway)
- [Deployment Guide](../README.md#lab-3--function-app-caller-with-easy-auth-managed-identity-pattern)
