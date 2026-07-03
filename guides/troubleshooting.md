# Troubleshooting Guide for Azure Easy Auth Lab

This guide helps you diagnose and fix common issues in the Easy Auth lab.

---

## Common Issues and Solutions

### Setup & Installation Issues

#### ❌ "setup.ps1: command not found" or "cannot be loaded"

**Cause:** PowerShell execution policy is too restrictive

**Fix:**
```powershell
# Allow scripts for current user
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

# Or run script with bypass (one-time)
powershell -ExecutionPolicy Bypass -File ./setup.ps1
```

---

#### ❌ ".env file not found"

**Cause:** You haven't created .env file

**Fix:**
```bash
# Copy the template
cp .env.example .env

# Edit it with your values
notepad .env           # Windows
nano .env              # Mac/Linux
```

**What to set:**
- `AZURE_SUBSCRIPTION_ID` — Your Azure subscription ID
- `AZURE_TENANT_ID` — Your Entra ID tenant ID
- `AZURE_REGION` — Azure region (e.g., westeurope)
- `ENVIRONMENT_NAME` — Name (dev, test, prod)
- `YOUR_EMAIL` — Your email for tagging

---

#### ❌ "ERROR: Not logged in to Azure"

**Cause:** Not authenticated with Azure

**Fix:**
```bash
# Sign in interactively
az login --tenant <your-tenant-id>

# Verify you're signed in
az account show

# Select your subscription
az account set --subscription <subscription-id>
```

---

#### ❌ "Subscription ...not found or you don't have access"

**Cause:** You don't have access to the subscription or ID is wrong

**Fix:**
```bash
# List your accessible subscriptions
az account list --query "[].{name:name, subscriptionId:id}" -o table

# Copy the correct subscription ID to .env
```

---

### Deployment Issues

#### ❌ "Deployment failed" / "Error validating template"

**Cause:** Bicep template has syntax errors

**Fix:**
```bash
# Validate template
az bicep build --file infra/main.bicep --output-format json

# Check for detailed error messages (usually at the end)
```

---

#### ❌ Deployment times out (takes more than 30 minutes)

**Cause:** Large resource creation or network issues

**Fix:**
```bash
# Check deployment status
az deployment group list --resource-group rg-easyauth-lab-dev \
  --query "[].{name:name, state:properties.provisioningState}" -o table

# If stuck, cancel it:
az deployment operation cancel --resource-group rg-easyauth-lab-dev \
  --name <deployment-name>

# Then try again
./setup.ps1
```

---

#### ❌ Quota exceeded error

**Cause:** Your subscription doesn't have enough quota for resources

**Fix:**
1. Check available quotas:
   ```bash
   az vm list-usage --location westeurope \
     --query "[?contains(name.value, 'Total')]" -o table
   ```

2. Request quota increase in [Azure Portal](https://portal.azure.com):
   - Home → Subscriptions → [Your subscription] → Usage + quotas
   - Find the resource type
   - Click "Request quota increase"
   - Submit request

3. Wait for approval (usually 1-2 hours)

---

### Authentication Issues

#### ❌ Function App returns "401 Unauthorized"

**Cause:** Bearer token is invalid or missing

**Diagnosis:**
```bash
# Check if Function App Easy Auth is enabled
az resource show --resource-group rg-easyauth-lab-dev \
  --resource-type "Microsoft.Web/sites/config" \
  --name la-easyauth-lab-dev-caller-xxx/authsettingsv2 \
  --query "properties.{httpSettings:httpSettings, login:login, identityProviders:identityProviders}"
```

**Fix:**

1. **Verify token acquisition code:**
   ```csharp
   // Should look like this:
   var credential = new DefaultAzureCredential();
   var tokenContext = new TokenRequestContext(
     scopes: new[] { $"{audience}/.default" }
   );
   var token = await credential.GetTokenAsync(tokenContext, cancellationToken);
   ```

2. **Check token expiry:**
   ```bash
   # Log in to Function App and check token lifetime
   # Token should be valid for 1 hour from acquisition
   ```

3. **Verify Authorization header format:**
   ```
   ✅ Correct:  Authorization: Bearer eyJhbGc...
   ❌ Wrong:    Authorization: eyJhbGc...
   ❌ Wrong:    Bearer eyJhbGc...  (no Authorization header name)
   ```

---

#### ❌ Function App returns "403 Forbidden"

**Cause:** Token is valid but caller is not in allowedPrincipals

**Fix:**

1. **Get Function App's principal ID:**
   ```bash
   az resource show --resource-group rg-easyauth-lab-dev \
     --resource-type "Microsoft.Web/sites" \
     --name la-easyauth-lab-dev-caller-xxx \
     --query "identity.principalId"
   ```

2. **Check Logic App's allowedPrincipals:**
   ```bash
   az resource show --resource-group rg-easyauth-lab-dev \
     --resource-type "Microsoft.Web/sites/config" \
     --name la-easyauth-lab-dev-la-xxx/authsettingsv2 \
     --query "properties.identityProviders.azureActiveDirectory.allowedPrincipals"
   ```

3. **If Function App principal is missing, add it:**
   ```bash
   # Get the principal IDs
   FUNC_APP_PRINCIPAL=$(az resource show --resource-group rg-easyauth-lab-dev \
     --resource-type "Microsoft.Web/sites" \
     --name la-easyauth-lab-dev-caller-xxx \
     --query "identity.principalId" -o tsv)
   
   LOGICAPP_PRINCIPAL=$(az resource show --resource-group rg-easyauth-lab-dev \
     --resource-type "Microsoft.Web/sites" \
     --name la-easyauth-lab-dev-la-xxx \
     --query "identity.principalId" -o tsv)
   
   # Re-run setup to fix configuration
   ./setup.ps1
   ```

---

#### ❌ "AADSTS50058: Silent sign-in request failed"

**Cause:** No interactive authentication session available

**Fix:**
```bash
# Sign out and sign in again
az logout
az login --tenant <your-tenant-id>
```

---

### Network Issues

#### ❌ "Connection refused" or "Connection timeout"

**Cause:** Network connectivity issue or firewall blocking

**Fix:**

1. **If using private endpoints:**
   ```bash
   # Verify private endpoint is accessible
   az network private-endpoint show --resource-group rg-easyauth-lab-dev \
     --name la-easyauth-lab-dev-la-pe \
     --query "{status:provisioningState, ipConfig:customDnsConfigs}"
   ```

2. **If using public endpoints:**
   ```bash
   # Test connectivity
   curl -v https://la-easyauth-lab-dev-la-xxx.azurewebsites.net/health
   ```

3. **Check firewall rules:**
   - If behind corporate firewall, may need to whitelist Azure domains
   - Contact your network team

---

#### ❌ "Failed to resolve private DNS name"

**Cause:** Private DNS zone not linked to VNet

**Fix:**
```bash
# Verify private DNS zone exists and is linked
az network private-dns zone list --resource-group rg-easyauth-lab-dev

# Check DNS record
az network private-dns record-set a list \
  --resource-group rg-easyauth-lab-dev \
  --zone-name privatelink.azurewebsites.net
```

---

### Application Issues

#### ❌ Application Insights shows no data

**Cause:** Instrumentation may not be connected

**Fix:**

1. **Check if AppInsights is enabled:**
   ```bash
   az resource show --resource-group rg-easyauth-lab-dev \
     --resource-type "Microsoft.Insights/components" \
     --name la-easyauth-lab-dev-ai \
     --query "properties.InstrumentationKey"
   ```

2. **Verify Function App has APPINSIGHTS_INSTRUMENTATION_KEY:**
   ```bash
   az functionapp config appsettings list \
     --resource-group rg-easyauth-lab-dev \
     --name la-easyauth-lab-dev-caller-xxx \
     --query "[?name=='APPINSIGHTS_INSTRUMENTATION_KEY']"
   ```

3. **If missing, redeploy:**
   ```bash
   ./setup.ps1
   ```

---

#### ❌ Logic App workflow shows "Skipped" status

**Cause:** Workflow didn't receive a valid request

**Fix:**

1. **Check Easy Auth settings:**
   ```bash
   az resource show --resource-group rg-easyauth-lab-dev \
     --resource-type "Microsoft.Web/sites/config" \
     --name la-easyauth-lab-dev-la-xxx/authsettingsv2 \
     --query "properties.{platformEnabled:platformSettings.enabled, unauthenticatedClientAction:platform.unauthenticatedClientAction}"
   ```

2. **Verify HTTP trigger is set to AllowAnonymous:**
   - Should be: `unauthenticatedClientAction = "AllowAnonymous"`
   - Easy Auth validates the token, not the trigger

3. **Check workflow input:**
   - Open Logic App in Portal → Designer
   - Look at trigger configuration
   - Should NOT require authentication

---

### Getting Help

#### Still stuck?

1. **Collect diagnostic information:**
   ```bash
   # Create a diagnostic bundle
   az group show --name rg-easyauth-lab-dev > diagnostic-rg.json
   az resource list --resource-group rg-easyauth-lab-dev > diagnostic-resources.json
   az functionapp config appsettings list --resource-group rg-easyauth-lab-dev \
     --name la-easyauth-lab-dev-caller-xxx > diagnostic-func-settings.json
   ```

2. **Check Application Insights logs:**
   - Open [Azure Portal](https://portal.azure.com)
   - Go to your Application Insights resource
   - Click "Logs" (KQL queries)
   - Run this query:
     ```kusto
     traces
     | where timestamp > ago(1h)
     | order by timestamp desc
     | limit 50
     ```

3. **Check Easy Auth logs:**
   - Function App → Monitoring → Log stream
   - Look for authentication errors

4. **File a GitHub issue:**
   - Include diagnostic information above
   - Include error messages (exact text)
   - Include your OS and tool versions

---

## Quick Reference Table

| Problem | Likely Cause | Command to Check |
|---------|--------------|------------------|
| Setup fails | Not signed in | `az account show` |
| 401 Unauthorized | Token not in header | Check function app logs |
| 403 Forbidden | Not in allowedPrincipals | Check Easy Auth config |
| Connection timeout | Private DNS not working | `nslookup <logicapp>.azurewebsites.net` |
| No App Insights data | Not configured | `az functionapp config appsettings list ...` |
| Resource quota exceeded | Too many resources | `az vm list-usage ...` |
| .env file not found | Not created yet | `cp .env.example .env` |

---

## Performance Tips

### Slow token acquisition?

Token caching can help:
```csharp
// Bad: Creates new credential each time
var credential = new DefaultAzureCredential();

// Better: Reuse credential (implemented in our code)
private static readonly DefaultAzureCredential _credential = 
    new DefaultAzureCredential();
```

### Slow Function App deployment?

Publish in Release mode:
```bash
dotnet publish --configuration Release
```

### Slow Logic App execution?

Check if workflow has unnecessary steps:
- Open Logic App Designer
- Remove test/debug steps
- Simplify conditions

---

## When All Else Fails

1. **Delete everything and start over:**
   ```bash
   az group delete --name rg-easyauth-lab-dev --yes
   ./setup.ps1
   ```

2. **Check Azure status page:**
   - https://status.azure.com/
   - Are there any outages in your region?

3. **Contact Azure support:**
   - Azure Portal → Help + support → New support request
   - Describe the issue
   - Include diagnostic information

---

## Prevention Tips

✅ **Always use `.env` file** — Don't hardcode values  
✅ **Keep scripts versioned** — Use git to track changes  
✅ **Test in dev first** — Before production  
✅ **Monitor with AppInsights** — Catch issues early  
✅ **Use managed identities** — Not connection strings  
✅ **Document custom changes** — Help future you  

---

## Related Documentation

- [Azure Easy Auth & Authorization](https://learn.microsoft.com/en-us/azure/app-service/overview-authentication-authorization)
- [Managed Identity Troubleshooting](https://learn.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/troubleshoot)
- [Azure Function App Diagnostics](https://learn.microsoft.com/en-us/azure/azure-functions/functions-diagnostics)
- [Application Insights Troubleshooting](https://learn.microsoft.com/en-us/azure/azure-monitor/app/troubleshoot-availability)

---

**Still have questions?** Check the main lab guide: [docs/lab3-passwordless-managed-identity-easy-auth.md](lab3-passwordless-managed-identity-easy-auth.md)
