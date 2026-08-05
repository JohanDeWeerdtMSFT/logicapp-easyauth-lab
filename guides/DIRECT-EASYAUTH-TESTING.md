# Test Logic App Easy Auth Directly from a Lab PC

Use this guide to test a Logic App Standard Easy Auth configuration from a lab user's Windows PC **without deploying Function App caller code first**.

The test uses the signed-in lab user's Microsoft Entra token. It validates the same issuer, audience, and principal controls as a workload token, but it does not prove managed-identity token acquisition. Use the Function App flow later for the final service-to-service demonstration.

## What the tests prove

| Test | Expected status | Meaning |
| --- | ---: | --- |
| No bearer token | `401` | Easy Auth requires authentication. |
| Valid user token, user not allow-listed | `403` | Authentication passed; authorization rejected the user. |
| Valid user token, user temporarily allow-listed | `200` | Issuer, audience, and principal validation succeeded. |

## Step 1: Collect your values from Azure portal

Create a temporary text file or PowerShell session with these placeholders. Do not commit the actual values.

| Variable | Where to find it in Azure portal |
| --- | --- |
| `{tenant-id}` | **Microsoft Entra ID** > **Overview** > **Tenant ID** |
| `{subscription-id}` | **Subscriptions** > your subscription > **Subscription ID** |
| `{logic-app-client-id}` | **Microsoft Entra ID** > **App registrations** > the registration used by Logic App Authentication > **Overview** > **Application (client) ID** |
| `{logic-app-name}` | Logic App Standard > **Overview** > resource name |
| `{logic-app-default-domain}` | Logic App Standard > **Overview** > **Default domain** |
| `{lab-user-object-id}` | **Microsoft Entra ID** > **Users** > the lab user > **Object ID** |
| `{function-managed-identity-object-id}` | Function App > **Settings** > **Identity** > **System assigned** > **Object (principal) ID** |

Confirm the Logic App API registration has this Application ID URI:

```text
api://{logic-app-client-id}
```

Find it under **Microsoft Entra ID** > **App registrations** > your Logic App API registration > **Expose an API** > **Application ID URI**.

Official references:

- [Register an application in Microsoft Entra ID](https://learn.microsoft.com/entra/identity-platform/quickstart-register-app)
- [Expose scopes and understand the Application ID URI](https://learn.microsoft.com/entra/identity-platform/scenario-protected-web-api-expose-scopes)
- [App Service authentication and authorization](https://learn.microsoft.com/azure/app-service/overview-authentication-authorization)
- [Configure Microsoft Entra authentication for App Service](https://learn.microsoft.com/azure/app-service/configure-authentication-provider-aad)
- [Access tokens in the Microsoft identity platform](https://learn.microsoft.com/entra/identity-platform/access-tokens)

## Step 2: Set local PowerShell variables

Replace every `{placeholder}` with the value collected in Step 1:

```powershell
$tenantId = '{tenant-id}'
$subscriptionId = '{subscription-id}'
$logicAppClientId = '{logic-app-client-id}'
$logicAppDefaultDomain = '{logic-app-default-domain}'
$labUserObjectId = '{lab-user-object-id}'

$audience = "api://$logicAppClientId"
$logicAppUrl = "https://$logicAppDefaultDomain/api/httpTriggerWorkflow/triggers/When_a_HTTP_request_is_received/invoke?api-version=2022-05-01"
```

The Logic App URL must be the **unsigned** endpoint. It must not contain `sig=`, `sp=`, or `sv=` query parameters.

## Step 3: Sign in as the lab user

```powershell
az login --tenant $tenantId
az account set --subscription $subscriptionId

az account show `
  --query '{signedInAs:user.name, tenantId:tenantId, subscriptionId:id}' `
  --output table
```

Verify that the displayed account is the attendee whose Object ID you recorded.

## Step 4: Prove that a missing token returns 401

```powershell
$noTokenResponse = Invoke-WebRequest `
  -Method Post `
  -Uri "$logicAppUrl&scenario=NO-TOKEN" `
  -ContentType 'application/json' `
  -Body '{"message":"No bearer token"}' `
  -SkipHttpErrorCheck

[int]$noTokenResponse.StatusCode
```

Expected: `401`.

## Step 5: Fetch a user bearer token

```powershell
$bearerToken = az account get-access-token `
  --tenant $tenantId `
  --resource $audience `
  --query accessToken `
  --output tsv

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($bearerToken)) {
  throw 'Token acquisition failed. Verify the tenant, Application ID URI, and enterprise application for the Logic App API registration.'
}
```

Do not print, decode, save, or paste the token into documentation or chat.

If token acquisition requires consent or is blocked by tenant policy, ask the tenant administrator to approve the test client for the Logic App API. Do not create a client secret as a workaround.

## Step 6: Call the Logic App before allow-listing the user

```powershell
try {
  $blockedResponse = Invoke-WebRequest `
    -Method Post `
    -Uri "$logicAppUrl&scenario=USER-NOT-ALLOWED" `
    -Headers @{ Authorization = "Bearer $bearerToken" } `
    -ContentType 'application/json' `
    -Body '{"message":"Valid token, user not allow-listed"}' `
    -SkipHttpErrorCheck

  [int]$blockedResponse.StatusCode
}
finally {
  Remove-Variable bearerToken -ErrorAction SilentlyContinue
}
```

Expected with a valid token and a user absent from `allowedPrincipals`: `403`.

This proves that Easy Auth authenticated the token but rejected the principal during authorization.

## Step 7: Temporarily allow the lab user in Azure portal

1. Open the Logic App Standard resource.
2. Select **Settings** > **Authentication**.
3. Select **Edit** beside the Microsoft identity provider.
4. Under **Identity requirement**, select **Allow requests from specific identities**.
5. Edit **Allowed identities**.
6. Keep the existing Function managed-identity Object ID if one is present.
7. Add `{lab-user-object-id}` from Step 1.
8. Save the identity provider.

Do not replace the Function identity. Add the user as a second temporary identity.

## Step 8: Fetch a fresh token and call again

```powershell
$bearerToken = az account get-access-token `
  --tenant $tenantId `
  --resource $audience `
  --query accessToken `
  --output tsv

try {
  $result = Invoke-RestMethod `
    -Method Post `
    -Uri "$logicAppUrl&scenario=DIRECT-USER-TEST" `
    -Headers @{ Authorization = "Bearer $bearerToken" } `
    -ContentType 'application/json' `
    -Body '{"message":"Direct Easy Auth user test"}'

  $result | ConvertTo-Json -Depth 10
}
finally {
  Remove-Variable bearerToken -ErrorAction SilentlyContinue
}
```

Expected: HTTP `200` and a new succeeded Logic App run.

## Step 9: Verify the workflow run

1. Open Logic App Standard > **Workflows** > `httpTriggerWorkflow`.
2. Select **Run history**.
3. Refresh the list.
4. Open the newest **Succeeded** run.
5. Confirm the scenario is `DIRECT-USER-TEST` and inspect the authenticated principal.

## Step 10: Restore the authorization policy

Immediately after the test:

1. Return to Logic App Standard > **Settings** > **Authentication**.
2. Edit the Microsoft identity provider.
3. Remove `{lab-user-object-id}` from **Allowed identities**.
4. Keep the original Function managed-identity Object ID.
5. Save.

Fetch a fresh user token and repeat Step 6. Expected: `403` again.

## Final explanation for the attendee

- The app registration defines the protected API and its `api://{logic-app-client-id}` audience.
- The lab user's token proves a human identity; its `oid` claim contains `{lab-user-object-id}`.
- The Function token proves a workload identity; its `oid` claim contains `{function-managed-identity-object-id}`.
- Easy Auth first validates issuer, signature, lifetime, and audience, then checks the `oid` against Allowed identities.
- The direct user test validates Easy Auth without Function code. The managed-identity Function remains the intended production-style service-to-service caller.
