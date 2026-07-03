# Lab 1: Understanding Easy Auth (For Beginners)

## 🎯 What You'll Learn

In this lab, you'll understand:
- **What Easy Auth does** — Acts as a security checkpoint for your app
- **How it validates tokens** — Checks the signature and expiry
- **How it protects your workflow** — Only allows authenticated requests
- **How it fits in the bigger picture** — The first layer of defense

**Reading time:** 15-20 minutes

---

## The Problem: How Do We Prove Who We Are?

Imagine you're trying to use a cloud app. The app needs to know:
> "Are you really who you say you are?"

Without this, anyone could pretend to be you and call your Logic App!

**Easy Auth solves this** by validating your identity before your code even runs.

---

## Analogy: Easy Auth as a Nightclub Bouncer

```
You → Doorman (Easy Auth) → Inside the Club (Your App)
     ↓
     Checks your ID
     Makes sure you're on the list
     Makes sure your ID isn't fake
     ↓
     You're in!
```

**Easy Auth is the bouncer:**
- Stands at the door (in front of your app)
- Checks your credentials (Authorization header)
- Verifies the signature (is the ID real?)
- Checks the expiry (is your ID still valid?)
- Consults the whitelist (allowedPrincipals)

---

## What is Easy Auth, Actually?

Easy Auth is **authentication middleware** built into Azure App Services.

Middleware is just a fancy word for "something that intercepts requests":

```
HTTP Request arrives
    ↓
Easy Auth middleware intercepts it
    • Is there an Authorization header?
    • Is the token valid?
    • Is it signed by Entra ID?
    • Is it expired?
    • Is the caller in allowedPrincipals?
    ↓
If all checks pass:
    • Request goes to your app (with claims headers added)
If any check fails:
    • Request rejected with 401 or 403
    • Your code never sees it
```

**Key insight:** Easy Auth runs BEFORE your code, not in your code.

---

## Configuration: AllowAnonymous + Bearer Token Validation

There are two confusing settings in Easy Auth:

### Setting 1: `unauthenticatedClientAction`

```
unauthenticatedClientAction = "Return401"
    • If no auth header → reject
    • But breaks Azure Portal (can't view run history)
    • ❌ NOT what we use

unauthenticatedClientAction = "AllowAnonymous"
    • If no auth header → let it through
    • Easy Auth still validates if header IS present
    • ✅ This is what we use (and it works!)
```

**Why AllowAnonymous?**
- Portal needs to access your app without a token
- But Easy Auth still validates bearer tokens when present
- So security is actually enforced!

### Setting 2: `allowedPrincipals`

```json
{
  "allowedPrincipals": [
    "function-app-principal-id-here",
    "another-app-principal-id-here"
  ]
}
```

**This is a whitelist** of which identities are allowed to call your app.

If a token comes in with a different principal ID → 403 Forbidden.

---

## Token Validation Process (Step by Step)

### Step 1: Request arrives with Authorization header

```
POST /api/workflows/httpTriggerWorkflow/triggers/manual/invoke
Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
```

### Step 2: Easy Auth extracts the token

Easy Auth looks for: `Authorization: Bearer <token-here>`

If not found → next request (no token validation)

### Step 3: Easy Auth validates the signature

Easy Auth knows Entra ID's public key. It uses this to verify:
> "Is this token really signed by Entra ID?"

If not signed by Entra ID → 401 Unauthorized (reject)

### Step 4: Easy Auth checks expiry

Tokens are only valid for 1 hour from creation.

If token is more than 1 hour old → 401 Unauthorized (reject)

### Step 5: Easy Auth checks allowedPrincipals

The token includes a `sub` (subject) claim — the principal ID of who the token was issued for.

Easy Auth checks: "Is this principal ID in our allowedPrincipals list?"

If not in list → 403 Forbidden (reject)

### Step 6: Request allowed through

If all checks pass → Easy Auth allows the request to reach your app.

Your app receives the request with extra headers added by Easy Auth:
```
X-MS-CLIENT-PRINCIPAL-ID: 123e4567-e89b-12d3-a456-426614174000
X-MS-CLIENT-PRINCIPAL-NAME: function-app@tenant.onmicrosoft.com
X-MS-CLIENT-PRINCIPAL: <base64-encoded-claims>
```

---

## The Token Structure (JWT)

Bearer tokens are **JSON Web Tokens (JWT)**. They have 3 parts:

```
eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c
```

Breaking it down:

```
Part 1 (Header): eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9
    ↓ (Base64 decode)
    {
      "alg": "RS256",        ← Signing algorithm
      "typ": "JWT"
    }

Part 2 (Payload): eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ
    ↓ (Base64 decode)
    {
      "sub": "1234567890",   ← Subject (principal ID)
      "name": "John Doe",
      "iat": 1516239022,     ← Issued at (unix timestamp)
      "exp": 1516242622,     ← Expires (unix timestamp)
      "aud": "api://app-id"  ← Audience (intended for this app)
    }

Part 3 (Signature): SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c
    ↓ (Cryptographic signature)
    HMAC-SHA256(
      base64url(header) + "." +
      base64url(payload),
      secret_key
    )
```

**The signature proves:**
- Token hasn't been tampered with
- It was really issued by Entra ID

---

## Key Claims Explained

### `sub` (Subject) — WHO made the token

```
"sub": "12345678-90ab-cdef-1234-567890abcdef"
```

This is the **principal ID** of the identity that got the token.

Easy Auth checks this against `allowedPrincipals`.

### `aud` (Audience) — WHO the token is FOR

```
"aud": "api://786594a8-6b38-40cf-8c6b-d434b539dd46"
```

This identifies which app the token is intended for.

The Function App specifies this when requesting the token:
```csharp
var tokenContext = new TokenRequestContext(
    scopes: new[] { "api://786594a8-6b38-40cf-8c6b-d434b539dd46/.default" }
);
```

**Token with wrong audience = rejected!**

### `iat` (Issued At) & `exp` (Expires) — WHEN the token is valid

```
"iat": 1234567890,  ← Created at this unix timestamp
"exp": 1234571490   ← Expires at this unix timestamp (1 hour later)
```

Easy Auth checks: `current_time > exp` → expired, reject!

---

## What Happens When Easy Auth Rejects a Request?

### 401 Unauthorized

```
Reason 1: No Authorization header
    • Client didn't send a token
    • But Easy Auth is configured to check for one

Reason 2: Invalid token
    • Token is malformed (not JWT format)
    • Signature doesn't match (tampered with)
    • Issued by wrong authority (not Entra ID)
    • Expired (past expiry time)

Response to client:
    HTTP/1.1 401 Unauthorized
    WWW-Authenticate: Bearer realm="https://login.microsoftonline.com/..."
    
    (empty body)
```

### 403 Forbidden

```
Reason 1: Token is valid, but caller not in allowedPrincipals
    • Token signature is good
    • Token is not expired
    • But principal ID is not in whitelist

Response to client:
    HTTP/1.1 403 Forbidden
    
    (empty body)
```

---

## Debugging Easy Auth Problems

### Problem 1: "401 Unauthorized"

**Check:**
1. Is Authorization header being sent?
   ```bash
   curl -i -H "Authorization: Bearer YOUR_TOKEN" https://your-app.azurewebsites.net/api/...
   ```

2. Is the token valid?
   - Decode the token at https://jwt.ms
   - Check expiry time (is it in the past?)
   - Check audience (does it match your app?)

3. Is token from correct issuer?
   - Token should be signed by: `https://login.microsoftonline.com/{tenant-id}/v2.0`
   - Check the `iss` claim in the token

### Problem 2: "403 Forbidden"

**Check:**
1. Get the principal ID from the token:
   ```bash
   # Decode token, look for "sub" claim
   ```

2. Check Logic App's allowedPrincipals:
   ```bash
   az resource show --resource-group ... \
     --resource-type "Microsoft.Web/sites/config" \
     --name .../authsettingsv2 \
     --query "properties.identityProviders.azureActiveDirectory.allowedPrincipals"
   ```

3. If principal ID is missing, add it via Bicep or Portal

---

## The Big Picture: Where Does Easy Auth Fit?

```
Your Application Architecture
├── Layer 1: Network (VNet, Private Endpoints, Firewalls)
├── Layer 2: Easy Auth (Request comes in, validate token)
├── Layer 3: Your Code (Sees only validated requests)
└── Layer 4: Business Logic (Do useful work)

Easy Auth is Layer 2:
  ✅ Happens before your code runs
  ✅ Rejects bad requests automatically
  ✅ Adds identity information to request headers
  ✅ Logs authentication events
  ❌ Doesn't handle business logic
  ❌ Doesn't validate request content
  ❌ Doesn't check permissions (that's your code's job)
```

---

## Key Takeaways

✅ Easy Auth is middleware that runs before your code  
✅ Validates bearer tokens using Entra ID public key  
✅ Checks token signature, expiry, and audience  
✅ Uses allowedPrincipals whitelist  
✅ Returns 401 for invalid tokens, 403 for unauthorized  
✅ Adds identity headers to validated requests  
✅ AllowAnonymous + bearer validation is the right config  
✅ Easy Auth is just one layer (network + Easy Auth + your code)  

---

## Next Steps

1. **Continue to Lab 2** to learn about Managed Identity
2. **Then move to Lab 3** to see how it all comes together
3. **Look at actual code** in `solution/CallerFunctionApp/CallLogicApp.cs`

---

## Review Questions

Think about these before moving to Lab 2:

1. What is Easy Auth checking when it validates a token?
2. Why do we use AllowAnonymous instead of Return401?
3. What does allowedPrincipals do?
4. What's the difference between 401 and 403?
5. How long is a bearer token valid for?
6. What information does Easy Auth add to request headers?

---

**Ready to continue?** Move on to [Lab 2: Understanding Managed Identity](lab2-managed-identity-basics.md)
