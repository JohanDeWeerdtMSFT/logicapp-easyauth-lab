# Lab 3: Testing Quick Reference

Use this reference card while testing and deploying Lab 3. Print it, bookmark it, or keep it open in a separate window.

---

## Pre-Test Checklist

Before you start testing, verify these infrastructure components are in place:

**Function App Configuration:**
- [ ] Plan: Standard (S1) or higher
- [ ] System-assigned managed identity: Enabled
- [ ] VNet integration: Enabled (routed through app integration subnet)
- [ ] Easy Auth configured

**Logic App Configuration:**
- [ ] Public network access: Disabled
- [ ] Easy Auth enabled with AllowAnonymous mode
- [ ] Function App's managed identity principal ID in allowedPrincipals

**Network Configuration:**
- [ ] Virtual Network: 10.0.0.0/16 deployed
- [ ] Private DNS Zone: privatelink.azurewebsites.net created
- [ ] Private Endpoint: Created and linked to Logic App

**Monitoring:**
- [ ] Application Insights: Connected to Function App

---

## Function App Implementation

### Required NuGet Packages

Install these packages in your Function App project:

```bash
dotnet add package Azure.Identity          # For DefaultAzureCredential
dotnet add package Azure.Core              # For TokenRequestContext
dotnet add package Newtonsoft.Json         # For JSON serialization
```

### Application Settings (Required)

| Setting | Example Value | Source |
|---------|---------------|--------|
| `LOGIC_APP_URL` | `https://easyauth-logic-xyz.azurewebsites.net/api/workflows/workflow1/triggers/manual/invoke?...` | Logic App > Settings > Callback URL |
| `LOGIC_APP_AUDIENCE` | `api://11111111-1111-1111-1111-111111111111` | Logic App > Entra ID > Client ID |
| `WEBSITE_AUTH_AAD_ALLOWED_TENANTS` | `{tenantId}` | Tenant ID |

### Key Code Patterns

```csharp
// Token Acquisition
var credential = new DefaultAzureCredential(
    new DefaultAzureCredentialOptions 
    { 
        TenantId = Environment.GetEnvironmentVariable("WEBSITE_AUTH_AAD_ALLOWED_TENANTS") 
    }
);

var tokenResponse = await credential.GetTokenAsync(
    new TokenRequestContext(new[] { $"{audience}/.default" })
);

var token = tokenResponse.Token;

// HTTP Request
httpClient.DefaultRequestHeaders.Authorization = 
    new AuthenticationHeaderValue("Bearer", token);

var response = await httpClient.PostAsync(logicAppUrl, content);
```

---

## ✅ Test Execution Steps

### 1. Deploy Function

```bash
# Build and publish
func azure functionapp publish easyauth-func-<suffix> --build remote
```

### 2. Test HTTP Trigger

```bash
# Get URL
FUNC_URL=$(az functionapp function show \
  --resource-group rg-la-easyauth-lab-dev \
  --name easyauth-func-<suffix> \
  --function-name CallLogicApp \
  --query invokeUrlTemplate -o tsv)

# Call function
curl -X POST "$FUNC_URL" \
  -H "Content-Type: application/json" \
  -d '{}'
```

### 3. Monitor Logs

```bash
# Tail logs in real-time
func azure functionapp logstream easyauth-func-<suffix>

# Or query Application Insights
az monitor app-insights query \
  --apps <app-insights-name> \
  --analytics-query 'traces | where message startswith "✅" | limit 10'
```

---

## 📊 Expected Success Indicators

### Function App Logs (Application Insights)

```
✅ Bearer token acquired successfully
✅ Calling Logic App at: https://easyauth-logic-xyz.azurewebsites.net/...
✅ Logic App response: 200 OK
✅ Logic App call succeeded
```

### Bearer Token (JWT)

Decode at https://jwt.io:

```json
{
  "aud": "api://11111111-1111-1111-1111-111111111111",  ← Logic App client ID
  "iss": "https://login.microsoftonline.com/00922812-791e-41c8-a99e-45c3ed784cf5/v2.0",
  "appid": "22222222-2222-2222-2222-222222222222",       ← Function App MI principal ID
  "oid": "22222222-2222-2222-2222-222222222222",
  "exp": 1720000000,
  "iat": 1719996400
}
```

### Logic App Run History

- **Trigger:** manual/invoke ✅
- **Status:** Succeeded ✅
- **Input Headers:** Authorization: Bearer eyJ... ✅

---

## 🚨 Common Errors & Quick Fixes

| Error | Cause | Fix |
|-------|-------|-----|
| **401 Unauthorized** | Wrong audience in token | Check `LOGIC_APP_AUDIENCE` matches Logic App client ID |
| **401 Unauthorized** | Token expired (shouldn't happen) | Re-issue token, check time sync |
| **403 Forbidden** | Principal not in allowedPrincipals | Get Function App MI principal ID, add to Bicep, redeploy |
| **AuthenticationFailedException** | MI not enabled | Portal → Function App → Identity → System-assigned (ON) |
| **Network Timeout** | Private DNS not resolving | Verify private DNS zone, CNAME records, PE IP |
| **Invalid URI** | LOGIC_APP_URL malformed | Regenerate callback URL from Logic App |

---

## 📈 Metrics to Capture

| Metric | Tool | Expected |
|--------|------|----------|
| Token acquisition time | Application Insights | < 1 second |
| HTTP request roundtrip | Application Insights | < 2 seconds |
| Success rate | Application Insights | 100% |
| JWT signature validity | jwt.io | RS256 verified ✅ |
| Token expiry | jwt.io | 3600 seconds (1 hour) |
| Easy Auth validation | Logic App runs | Success with bearer token |

---

## 📸 Evidence to Capture

1. **Screenshot 1:** Function App logs showing "✅ Bearer token acquired"
2. **Screenshot 2:** JWT decoded at jwt.io with aud and appid
3. **Screenshot 3:** Logic App run history showing Succeeded status
4. **Screenshot 4:** Application Insights KQL query results
5. **Document:** Timestamps matching Function App log → Logic App run

---

## 🔗 Quick Links

- **Testing Guide:** [docs/lab3-testing-and-verification.md](lab3-testing-and-verification.md)
- **Architecture Docs:** [documentation/architecture/lab3-bearer-token-flow.html](../documentation/architecture/lab3-bearer-token-flow.html)
- **Markdown Reference:** [docs/lab3-managed-identity-bearer-token-flow.md](lab3-managed-identity-bearer-token-flow.md)
- **Bicep Modules:** [infra/modules/](../infra/modules/)

---

## 🎯 Test Result Template

```
TEST DATE: ___________
TESTER: ___________
RESULT: ☐ PASS  ☐ FAIL

EVIDENCE CAPTURED:
☐ Function App logs
☐ JWT token (decoded)
☐ Logic App run
☐ AppInsights query
☐ End-to-end latency

NOTES:
_________________________________________________________________
_________________________________________________________________

TIMESTAMP OF SUCCESSFUL FLOW: ___________
```

---

**Need Help?** See [docs/lab3-testing-and-verification.md](lab3-testing-and-verification.md) troubleshooting section.
