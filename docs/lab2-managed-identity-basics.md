# Lab 2: Understanding Managed Identity (For Beginners)

## 🎯 What You'll Learn

In this lab, you'll understand:
- **What Managed Identity is** — Passwordless credentials for Azure services
- **Why it's better than connection strings** — No secrets to leak
- **How DefaultAzureCredential works** — Automatic credential discovery
- **System-assigned vs User-assigned** — When to use which
- **How it acquires bearer tokens** — The step-by-step process

**Reading time:** 20-25 minutes

---

## The Problem: How Do Services Get Credentials?

Normally, if Service A needs to call Service B, it needs credentials:

```
Service A:
  username: "caller@example.com"
  password: "P@ssw0rdSecretKey123"
  
Service B:
  checks: "Is this the right username and password?"
```

**But this is risky:**
- ❌ Credentials must be stored somewhere (code, config file, Key Vault)
- ❌ Credentials must be rotated regularly
- ❌ If credentials leak, attacker can access Service B
- ❌ Managing multiple services = managing multiple credentials

**Example of what could go wrong:**
```
1. Dev stores password in local.settings.json
2. Dev commits to GitHub (accidentally)
3. Attacker finds password on GitHub
4. Attacker calls Service B as Service A
5. Disaster!
```

**Managed Identity solves all of this!**

---

## What is Managed Identity?

Managed Identity is **automatic, Azure-managed credentials for Azure services**.

Think of it like an employee badge:
- When you join a company, you get a badge automatically
- The company manages the badge (issues it, maintains it, expires it)
- You don't have to think about the badge
- The building's security system recognizes the badge

**Managed Identity works the same way:**
- When you create an Azure service (Function App, Logic App, etc.), it gets a managed identity automatically
- Azure manages it (creates it, rotates it, stores it securely)
- Your code doesn't see the credentials
- Azure's security system recognizes it

---

## System-Assigned vs User-Assigned

There are two types of managed identity:

### System-Assigned (What We Use)

```
Azure creates an identity specifically for ONE service
    │
    ├─ Tied to the service's lifecycle
    ├─ If you delete the service, the identity is deleted
    ├─ Each service has its own identity
    └─ Simple, for most cases
    
Example:
  Function App "caller" → System-assigned identity (unique to that app)
  Logic App "receiver" → System-assigned identity (unique to that app)
```

### User-Assigned (Advanced)

```
You create an identity that can be used by MULTIPLE services
    │
    ├─ Shared across services
    ├─ Survives service deletion
    ├─ One identity can run multiple apps
    └─ Complex, for advanced scenarios (not this lab)
    
Example (not us):
  Shared identity "worker" → used by Function App A and Function App B
```

**For this lab:** We use System-Assigned (one per service, simple).

---

## How Managed Identity Works (Big Picture)

```
Step 1: Service is created
  Azure creates a system-assigned managed identity
  Identity is stored securely in Azure
  Service can access its own identity

Step 2: Service code asks "Who am I?"
  Code: new DefaultAzureCredential()
  Azure responds: "You are application X, principal ID Y"

Step 3: Service code asks for token
  Code: credential.GetTokenAsync(...)
  Azure responds: "Here's a bearer token, valid for 1 hour"

Step 4: Service code uses token to call another service
  Code: POST https://other-service.com with Authorization: Bearer <token>
  Other service validates token via Easy Auth
  Other service recognizes the caller's principal ID
  Other service allows the request
```

---

## The DefaultAzureCredential Magic

`DefaultAzureCredential` is a .NET class that automatically discovers credentials:

```csharp
var credential = new DefaultAzureCredential();
```

When you run this:

### On Your Local Machine
```
DefaultAzureCredential tries:
  1. Environment variables (AZURE_CLIENT_ID, AZURE_CLIENT_SECRET)
  2. Shared credentials from az login
  3. Azure CLI (az account show)
  4. Visual Studio sign-in
  5. VS Code sign-in
  6. Fails if none found
```

### On Azure App Service (Function App, Logic App)
```
DefaultAzureCredential tries:
  1. Environment variables (AZURE_CLIENT_ID, AZURE_CLIENT_SECRET)
  2. Managed identity (if enabled)
  3. Fails if neither found
```

**When running in Azure:**
- Managed identity is automatically available
- `DefaultAzureCredential` finds it without any code changes
- You never see the credentials (Azure handles them)

---

## Bearer Token Acquisition Flow

When your code calls `GetTokenAsync()`:

```
Step 1: DefaultAzureCredential checks if it's running in Azure
  Environment check:
    • Is IDENTITY_ENDPOINT set? (Azure's managed identity endpoint)
    • Is IDENTITY_HEADER set? (Secret header for Azure authentication)
  
  Result: If both are set → Managed identity mode

Step 2: Call Azure's managed identity endpoint
  Request:
    GET http://169.254.169.254/metadata/identity/oauth2/token?
      api-version=2017-09-01&
      resource=https://management.azure.com&
      ...
  
  Header:
    X-IDENTITY-HEADER: <secret-header-value>

Step 3: Azure's managed identity service responds
  Response:
    {
      "access_token": "eyJ0eXAiOiJKV1QiLCJhbGc...",
      "expires_on": "1234567890",
      "token_type": "Bearer"
    }

Step 4: Your code gets the token
  You can now use this token in requests
```

**The key insight:** Azure's managed identity endpoint is secure because:
- Only runs inside Azure's datacenter
- Endpoint address is internal (169.254.169.254)
- Requires secret header (can't access from internet)
- Azure verifies the request is from your service

---

## Code Example: Token Acquisition

### Step 1: Create DefaultAzureCredential

```csharp
using Azure.Identity;

// Create once, reuse many times
private static readonly DefaultAzureCredential _credential = 
    new DefaultAzureCredential(new DefaultAzureCredentialOptions 
    {
        TenantId = "your-tenant-id"  // Optional, Entra ID tenant
    });
```

**Why reuse?** Token acquisition is expensive (network call to Azure). Cache the credential object.

### Step 2: Request a token

```csharp
public async Task<string> GetAccessTokenAsync(string audience, CancellationToken cancellationToken = default)
{
    // Tell Azure: "I need a token for this audience"
    var tokenContext = new TokenRequestContext(
        scopes: new[] { $"{audience}/.default" }  
        // e.g., "api://786594a8-6b38-40cf-8c6b-d434b539dd46/.default"
    );
    
    // Request the token from managed identity
    var token = await _credential.GetTokenAsync(tokenContext, cancellationToken);
    
    // token.Token is a string: "eyJ0eXAi..."
    // token.ExpiresOn tells you when it expires
    return token.Token;
}
```

### Step 3: Use token in request

```csharp
using (var request = new HttpRequestMessage(HttpMethod.Post, logicAppUrl))
{
    // Add the token to Authorization header
    request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
    
    // Add other headers
    request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
    
    // Send request
    using (var response = await _httpClient.SendAsync(request))
    {
        if (!response.IsSuccessStatusCode)
        {
            throw new HttpRequestException($"Logic App returned {response.StatusCode}");
        }
    }
}
```

---

## The `audience` Parameter

When requesting a token, you specify the `audience`:

```csharp
var tokenContext = new TokenRequestContext(
    scopes: new[] { "api://786594a8-6b38-40cf-8c6b-d434b539dd46/.default" }
);
```

**What does this mean?**

```
"api://786594a8-6b38-40cf-8c6b-d434b539dd46/.default"
 └──────────┬──────────────────────────────────────────┘
            │
            Audience: The Logic App's Entra ID app ID
            
            This tells Entra ID:
            "I want a token for this specific app"
            
            The token will have:
            "aud": "api://786594a8-6b38-40cf-8c6b-d434b539dd46"
```

**Why does the audience matter?**

Easy Auth validates:
```csharp
if (token.aud != expectedAudience)
{
    return 403 Forbidden;  // Token is for wrong app!
}
```

So if you get a token for the wrong audience, Easy Auth rejects it.

---

## Token Expiry and Caching

### Token Lifetime

```
Token acquired at: 2024-01-15 10:00:00 UTC
Token expires at:  2024-01-15 11:00:00 UTC
Token valid for:   1 hour
```

### Token Caching

```csharp
// Bad: Always request new token
for (int i = 0; i < 100; i++)
{
    var token = await _credential.GetTokenAsync(tokenContext, ct);
    // Network call 100 times! Slow!
}

// Better: Cache the token until expiry
private string _cachedToken;
private DateTimeOffset _tokenExpiry;

public async Task<string> GetCachedTokenAsync()
{
    if (_cachedToken != null && DateTimeOffset.UtcNow < _tokenExpiry)
    {
        return _cachedToken;  // Use cached token
    }
    
    var result = await _credential.GetTokenAsync(tokenContext, ct);
    _cachedToken = result.Token;
    _tokenExpiry = result.ExpiresOn;
    return _cachedToken;
}
```

**In this lab's code:**
- We request a fresh token each time (fine for demo)
- Production code should cache (reduce Azure calls)

---

## Permissions: Giving Managed Identity Access

Managed identity needs permissions to access other resources.

### Example: Function App needs to read from storage

```
Function App (has system-assigned MI)
    ├─ Needs: Read access to storage account
    └─ Grant: RBAC role "Storage Blob Data Reader"
    
How:
  az role assignment create \
    --assignee-object-id <function-app-principal-id> \
    --role "Storage Blob Data Reader" \
    --scope /subscriptions/.../storageAccounts/...
```

### In this lab: Function App needs to call Logic App

```
Function App (has system-assigned MI)
    ├─ Needs: Call Logic App (bearer token validation)
    └─ Grant: Add to Logic App's allowedPrincipals list
    
How:
  Logic App → Authentication → Easy Auth settings
  Add Function App's principal ID to allowedPrincipals
```

---

## Local Development with Managed Identity

### Problem: Managed identity only works in Azure

When you debug locally:
```
new DefaultAzureCredential()
    ├─ Checks: Am I in Azure?
    ├─ Result: No, I'm on a local machine
    └─ Tries: az login credentials instead
    
So locally, it uses: az account show
```

### Solution: Use Service Principal locally

```bash
# 1. Create a service principal
az ad sp create-for-rbac --name "LocalDevSP"

# 2. Get the output (credentials)
# Output:
#   appId: 12345678-...
#   password: ABC123...
#   tenant: 98765432-...

# 3. Set environment variables
export AZURE_CLIENT_ID=12345678-...
export AZURE_CLIENT_SECRET=ABC123...
export AZURE_TENANT_ID=98765432-...

# 4. Run your code
dotnet run

# DefaultAzureCredential will find these env vars and use them
```

**Important:** 
- Never commit service principal credentials to git
- Use `.env` file with `.gitignore`
- Use Key Vault in production

---

## Debugging Managed Identity Issues

### Problem 1: "Credential unavailable"

```
new DefaultAzureCredential() throws:
  CredentialUnavailableException: 
    "Credential unavailable"
```

**Cause:** DefaultAzureCredential can't find credentials

**Fix:**
1. On Azure: Ensure managed identity is enabled
   ```bash
   az resource show --resource-type "Microsoft.Web/sites" \
     --name "your-app" \
     --query "identity"
   ```

2. Locally: Ensure you're signed in
   ```bash
   az login
   az account show
   ```

### Problem 2: "Token request failed (403)"

```
GetTokenAsync() throws:
  Azure.Identity.AuthenticationFailedException: 
    "Service returned an error: 403"
```

**Cause:** Managed identity doesn't have permission for this operation

**Fix:**
1. Get the principal ID:
   ```bash
   az resource show --resource-type "Microsoft.Web/sites" \
     --name "your-app" \
     --query "identity.principalId"
   ```

2. Grant RBAC role:
   ```bash
   az role assignment create \
     --assignee-object-id "<principal-id>" \
     --role "Contributor"  # Or more specific role
     --scope "/subscriptions/..."
   ```

### Problem 3: "Wrong audience error"

```
Logic App returns 403:
  POST /api/workflows/... returned 403 Forbidden
```

**Cause:** Token audience doesn't match Logic App ID

**Fix:**
1. Check the token audience:
   ```bash
   # Decode your token at https://jwt.ms
   # Look for "aud" claim
   ```

2. Check Logic App's Entra app ID:
   ```bash
   az resource show --resource-group "..." \
     --resource-type "Microsoft.Web/sites" \
     --name "your-logicapp" \
     --query "identity.principalId"
   ```

3. Ensure they match when requesting token:
   ```csharp
   var tokenContext = new TokenRequestContext(
       scopes: new[] { "api://LOGIC_APP_ENTRA_CLIENT_ID/.default" }
   );
   ```

---

## The Big Picture

```
Managed Identity Architecture
│
├─ Azure Layer (Secure, Managed by Microsoft)
│  ├─ Manages credentials (generates, stores, rotates)
│  ├─ Provides token endpoint (169.254.169.254)
│  └─ Never exposes credentials to your code
│
├─ Your Service Layer
│  ├─ Uses DefaultAzureCredential
│  ├─ Gets tokens automatically
│  └─ Presents tokens to other services
│
└─ Other Services (receivers)
   ├─ Easy Auth validates tokens
   ├─ Checks principal ID against whitelist
   └─ Allows or rejects requests
```

**The key benefit:** Your code never handles credentials directly!

---

## Key Takeaways

✅ Managed Identity = automatic, Azure-managed credentials  
✅ System-assigned is tied to one service  
✅ User-assigned can be shared by multiple services  
✅ DefaultAzureCredential finds credentials automatically  
✅ In Azure, it uses managed identity  
✅ Locally, it uses az login or env vars  
✅ Tokens are valid for 1 hour  
✅ Always specify the correct audience when requesting tokens  
✅ RBAC roles grant managed identity permissions  
✅ Easy Auth validates tokens via principal ID whitelist  

---

## Next Steps

1. **You now understand Easy Auth** (Lab 1)
2. **You now understand Managed Identity** (Lab 2)
3. **Next: Move to Lab 3** to see how they work together

---

## Review Questions

Before moving to Lab 3, think about:

1. What is the difference between a password and a bearer token?
2. Why is managed identity better than storing credentials in config files?
3. How does DefaultAzureCredential know which credentials to use?
4. Why do we specify an audience when requesting a token?
5. What is the `allowedPrincipals` list for?
6. How long is a bearer token valid?
7. What information is in the token (JWT claims)?

---

**Ready to put it all together?** Move on to [Lab 3: Passwordless Authentication with Managed Identity + Easy Auth](lab3-passwordless-managed-identity-easy-auth.md)
