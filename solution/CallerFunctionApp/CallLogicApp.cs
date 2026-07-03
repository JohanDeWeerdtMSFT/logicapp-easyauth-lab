using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Azure.Core;
using Azure.Identity;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;

namespace CallerFunctionApp;

/// <summary>
/// HTTP-triggered Azure Function that demonstrates the managed identity bearer token flow.
///
/// Flow:
///   1. Acquire a bearer token from Entra ID using this Function App's system-assigned managed identity.
///   2. POST to the Logic App HTTP trigger, passing the token in the Authorization header.
///   3. Easy Auth on the Logic App validates the token, checks the allowed principals list,
///      and either passes the request through or rejects with 401/403.
///
/// Required application settings (configure in Azure Portal or local.settings.json):
///   LOGIC_APP_URL                      — Full Logic App callback URL (including SAS parameters)
///   LOGIC_APP_AUDIENCE                 — Entra ID client ID of the Logic App app registration (api://<client-id>)
///   WEBSITE_AUTH_AAD_ALLOWED_TENANTS   — Entra ID tenant ID for token acquisition
/// </summary>
public class CallLogicApp
{
    private readonly ILogger<CallLogicApp> _logger;
    private readonly IHttpClientFactory _httpClientFactory;

    public CallLogicApp(ILogger<CallLogicApp> logger, IHttpClientFactory httpClientFactory)
    {
        _logger = logger;
        _httpClientFactory = httpClientFactory;
    }

    [Function("CallLogicApp")]
    public async Task<HttpResponseData> Run(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = null)] HttpRequestData req,
        CancellationToken cancellationToken)
    {
        _logger.LogInformation("CallLogicApp function triggered.");

        try
        {
            // ── Step 1: Acquire bearer token from this Function App's managed identity ──────────
            var accessToken = await GetAccessTokenAsync(cancellationToken);
            _logger.LogInformation(
                "Bearer token acquired. Expiry: {Expiry}",
                accessToken.ExpiresOn.ToString("o"));

            // ── Step 2: Read required configuration from app settings ─────────────────────────
            var logicAppUrl = Environment.GetEnvironmentVariable("LOGIC_APP_URL");
            var audience    = Environment.GetEnvironmentVariable("LOGIC_APP_AUDIENCE");

            if (string.IsNullOrWhiteSpace(logicAppUrl) || string.IsNullOrWhiteSpace(audience))
            {
                _logger.LogError(
                    "Missing required app settings: LOGIC_APP_URL={LogicAppUrl}, LOGIC_APP_AUDIENCE={Audience}",
                    logicAppUrl ?? "<not set>",
                    audience ?? "<not set>");

                var badRequest = req.CreateResponse(HttpStatusCode.BadRequest);
                await badRequest.WriteAsJsonAsync(new
                {
                    error  = "MissingConfiguration",
                    detail = "LOGIC_APP_URL and LOGIC_APP_AUDIENCE must both be configured as application settings.",
                    fix    = "In Azure Portal: Function App → Configuration → Application settings"
                }, cancellationToken);
                return badRequest;
            }

            // ── Step 3: POST to Logic App with bearer token in Authorization header ───────────
            var payload = new
            {
                message   = "Test from CallerFunctionApp",
                source    = Environment.GetEnvironmentVariable("WEBSITE_SITE_NAME") ?? "local-dev",
                timestamp = DateTime.UtcNow
            };

            var logicAppResponse = await CallLogicAppWithTokenAsync(
                logicAppUrl,
                accessToken.Token,
                payload,
                cancellationToken);

            _logger.LogInformation("Logic App call completed successfully.");

            var ok = req.CreateResponse(HttpStatusCode.OK);
            await ok.WriteAsJsonAsync(new
            {
                status          = "success",
                message         = "Bearer token flow verified — Easy Auth accepted the request.",
                logicAppResponse,
                tokenExpiry     = accessToken.ExpiresOn,
                timestamp       = DateTime.UtcNow
            }, cancellationToken);
            return ok;
        }
        catch (HttpRequestException ex) when (ex.StatusCode == HttpStatusCode.Unauthorized)
        {
            // Easy Auth rejected the token — wrong audience, expired token, or invalid signature.
            _logger.LogError(ex,
                "401 Unauthorized. Easy Auth rejected the bearer token. " +
                "Check: LOGIC_APP_AUDIENCE matches the Logic App app registration client ID, " +
                "and the token issuer matches the configured tenant.");

            var res = req.CreateResponse(HttpStatusCode.Unauthorized);
            await res.WriteAsJsonAsync(new
            {
                error  = "Unauthorized",
                detail = ex.Message,
                hints  = new[]
                {
                    "Verify LOGIC_APP_AUDIENCE = api://<logic-app-client-id>",
                    "Verify WEBSITE_AUTH_AAD_ALLOWED_TENANTS matches the tenant where the Logic App is registered",
                    "Confirm the Logic App Easy Auth is enabled with platform.enabled = true"
                }
            }, cancellationToken);
            return res;
        }
        catch (HttpRequestException ex) when (ex.StatusCode == HttpStatusCode.Forbidden)
        {
            // Token is valid but this identity is not in allowedPrincipals.
            _logger.LogError(ex,
                "403 Forbidden. Token valid but principal is not in allowedPrincipals. " +
                "Add the Function App managed identity Object ID to the Logic App Easy Auth allowedPrincipals list.");

            var res = req.CreateResponse(HttpStatusCode.Forbidden);
            await res.WriteAsJsonAsync(new
            {
                error  = "Forbidden",
                detail = ex.Message,
                hints  = new[]
                {
                    "Get Function App Object ID: az webapp identity show --name <func-app-name> --resource-group <rg>",
                    "Add to Logic App Easy Auth: authsettingsV2 → identityProviders → azureActiveDirectory → validation → allowedPrincipals → identities"
                }
            }, cancellationToken);
            return res;
        }
        catch (CredentialUnavailableException ex)
        {
            // Managed identity is not configured or not reachable.
            _logger.LogError(ex,
                "Managed identity credential unavailable. " +
                "Ensure the Function App has a system-assigned managed identity enabled.");

            var res = req.CreateResponse(HttpStatusCode.InternalServerError);
            await res.WriteAsJsonAsync(new
            {
                error  = "CredentialUnavailable",
                detail = ex.Message,
                hints  = new[]
                {
                    "Enable system-assigned managed identity: Function App → Identity → System assigned → On",
                    "When running locally, sign in with: az login --tenant <tenant-id>"
                }
            }, cancellationToken);
            return res;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Unexpected error in CallLogicApp.");
            var res = req.CreateResponse(HttpStatusCode.InternalServerError);
            await res.WriteAsJsonAsync(new
            {
                error  = "InternalError",
                detail = ex.Message
            }, cancellationToken);
            return res;
        }
    }

    // ── Private helpers ──────────────────────────────────────────────────────────────────────────

    /// <summary>
    /// Acquires a bearer token for the Logic App audience using DefaultAzureCredential.
    /// In Azure: resolves to the Function App system-assigned managed identity.
    /// Locally: resolves to the Azure CLI signed-in user (run: az login --tenant {tenantId}).
    /// </summary>
    private async Task<AccessToken> GetAccessTokenAsync(CancellationToken cancellationToken)
    {
        var tenantId  = Environment.GetEnvironmentVariable("WEBSITE_AUTH_AAD_ALLOWED_TENANTS");
        var audience  = Environment.GetEnvironmentVariable("LOGIC_APP_AUDIENCE")
                        ?? throw new InvalidOperationException("LOGIC_APP_AUDIENCE app setting is not configured.");

        // DefaultAzureCredential tries: env vars → managed identity → Azure CLI → Visual Studio → …
        // In production the managed identity is used automatically.
        var credential = new DefaultAzureCredential(new DefaultAzureCredentialOptions
        {
            TenantId = tenantId
        });

        _logger.LogInformation(
            "Acquiring token for audience: {Audience}, tenant: {TenantId}",
            audience, tenantId ?? "<default>");

        return await credential.GetTokenAsync(
            new TokenRequestContext(scopes: [$"{audience}/.default"]),
            cancellationToken);
    }

    /// <summary>
    /// POSTs a JSON payload to the Logic App callback URL with the bearer token
    /// in the Authorization header. Easy Auth validates this token server-side.
    /// </summary>
    private async Task<string> CallLogicAppWithTokenAsync(
        string url,
        string bearerToken,
        object payload,
        CancellationToken cancellationToken)
    {
        var client = _httpClientFactory.CreateClient("LogicAppClient");

        var json    = JsonSerializer.Serialize(payload, new JsonSerializerOptions { WriteIndented = false });
        var content = new StringContent(json, Encoding.UTF8, "application/json");

        using var request = new HttpRequestMessage(HttpMethod.Post, url)
        {
            Content = content
        };

        // This is the header Easy Auth inspects to validate the caller's identity.
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearerToken);

        _logger.LogInformation("POST → Logic App: {Url}", MaskSasSignature(url));

        var response = await client.SendAsync(request, cancellationToken);

        _logger.LogInformation(
            "Logic App response: HTTP {StatusCode}",
            (int)response.StatusCode);

        response.EnsureSuccessStatusCode();

        return await response.Content.ReadAsStringAsync(cancellationToken);
    }

    /// <summary>
    /// Masks the SAS signature query parameter before logging the URL to avoid leaking secrets.
    /// </summary>
    private static string MaskSasSignature(string url)
    {
        var uri = new Uri(url);
        var query = uri.Query;
        if (query.Contains("sig="))
        {
            var masked = System.Text.RegularExpressions.Regex.Replace(
                query, @"sig=[^&]+", "sig=***");
            return $"{uri.GetLeftPart(UriPartial.Path)}{masked}";
        }
        return url;
    }
}
