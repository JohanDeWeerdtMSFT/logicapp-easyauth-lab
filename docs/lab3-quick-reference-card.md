# Lab 3: Testing Quick Reference

Use this reference card while testing and deploying Lab 3. Print it, bookmark it, or keep it open in a separate window.

---

## Pre-Test Checklist

Before you start testing, verify these infrastructure components are in place:

**Function App Configuration:**

- [ ] Plan: Standard (S1) or higher
- [ ] System-assigned managed identity: Enabled
- [ ] VNet integration: Enabled (routed through app integration subnet)
- [ ] HTTP trigger authorization level: Function
- [ ] Easy Auth enabled with AllowAnonymous mode behind the Function-key guard

**Logic App Configuration:**

- [ ] Public network access: Enabled for the classroom path
- [ ] Easy Auth enabled with Return401 mode
- [ ] Function App's managed identity principal ID in allowedPrincipals

**Network Configuration:**

- [ ] Virtual Network: 10.0.0.0/16 deployed
- [ ] Storage private DNS zones created for Blob, Queue, Table, and File
- [ ] Storage private endpoints approved
- [ ] Logic App private endpoint is optional

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
| --- | --- | --- |
| `LOGIC_APP_URL` | `https://<logic-app>.azurewebsites.net/api/httpTriggerWorkflow/triggers/When_a_HTTP_request_is_received/invoke?api-version=2022-05-01` | Deployment output |
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

FUNCTION_KEY=$(az functionapp keys list \
  --resource-group rg-la-easyauth-lab-dev \
  --name easyauth-func-<suffix> \
  --query functionKeys.default -o tsv)

# Call function
curl -X POST "$FUNC_URL" \
  -H "x-functions-key: $FUNCTION_KEY" \
  -H "Content-Type: application/json" \
  -d '{"scenario":"B1"}'

unset FUNCTION_KEY
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

```text
✅ Bearer token acquired successfully
✅ Calling Logic App at: https://easyauth-logic-xyz.azurewebsites.net/...
✅ Logic App response: 200 OK
✅ Logic App call succeeded
```

### Bearer Token (JWT)

Use the caller response `tokenClaims` object. Do not copy a bearer token into an online decoder.

```json
{
  "audience": "api://11111111-1111-1111-1111-111111111111",
  "iss": "https://login.microsoftonline.com/00922812-791e-41c8-a99e-45c3ed784cf5/v2.0",
  "objectId": "22222222-2222-2222-2222-222222222222",
  "expiresOn": "2026-08-04T18:00:00Z"
}
```

### Logic App Run History

- **Trigger:** When_a_HTTP_request_is_received ✅
- **Status:** Succeeded ✅
- **Authentication:** Principal ID matches the Function managed identity ✅

---

## 🚨 Common Errors & Quick Fixes

| Error | Cause | Fix |
| --- | --- | --- |
| **401 Unauthorized** | Wrong audience in token | Check `LOGIC_APP_AUDIENCE` matches Logic App client ID |
| **401 Unauthorized** | Token expired (shouldn't happen) | Re-issue token, check time sync |
| **403 Forbidden** | Principal not in allowedPrincipals | Get Function App MI principal ID, add to Bicep, redeploy |
| **AuthenticationFailedException** | MI not enabled | Portal → Function App → Identity → System-assigned (ON) |
| **Network Timeout** | Private DNS not resolving | Verify private DNS zone, CNAME records, PE IP |
| **Invalid URI** | LOGIC_APP_URL malformed | Regenerate callback URL from Logic App |

---

## 📈 Metrics to Capture

| Metric | Tool | Expected |
| --- | --- | --- |
| Token acquisition time | Application Insights | < 1 second |
| HTTP request roundtrip | Application Insights | < 2 seconds |
| Success rate | Application Insights | 100% |
| Token audience | Caller selected claims | Logic App Application ID URI |
| Token expiry | Caller selected claims | Future timestamp |
| Easy Auth validation | Logic App runs | Success with bearer token |

---

## 📸 Evidence to Capture

1. **Screenshot 1:** Function App logs showing "✅ Bearer token acquired"
2. **Screenshot 2:** Caller response with selected audience and object ID claims
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

```text
TEST DATE: ___________
TESTER: ___________
RESULT: ☐ PASS  ☐ FAIL

EVIDENCE CAPTURED:
☐ Function App logs
☐ Selected token claims (no bearer token)
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
