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
/// HTTP-triggered Azure Function that demonstrates PASSWORDLESS authentication via Managed Identity + Easy Auth.
///
/// Downstream Flow (No Client Secret Required):
///   1. Acquire a bearer token from Entra ID using this Function App's system-assigned managed identity.
///      Token scope = LOGIC_APP_AUDIENCE + "/.default".
///   2. POST to the Logic App HTTP trigger URL, passing the token in the Authorization header.
///   3. Easy Auth middleware on the Logic App:
///      • Validates the Bearer token signature (issued by Entra ID)
///      • Checks that the caller's principal ID is in allowedPrincipals
///      • Sets X-MS-CLIENT-PRINCIPAL-* headers for the workflow to inspect
///   4. Logic App accepts or rejects the request based on token validation.
///
/// The downstream call needs no callback signature, client secret, or stored token.
/// The managed-identity bearer token is its authentication mechanism.
///
/// Required application settings (configure in Azure Portal or local.settings.json):
///   LOGIC_APP_URL                      — Full invoke URL for the Logic App workflow
///                                         Format: https://<logicapp>.azurewebsites.net/api/<name>/triggers/When_a_HTTP_request_is_received/invoke?api-version=2022-05-01
///   LOGIC_APP_AUDIENCE                 — Application ID URI exposed by the Logic App registration
///   WEBSITE_AUTH_AAD_ALLOWED_TENANTS   — Entra ID tenant ID for token acquisition (optional, defaults to current tenant)
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
        [HttpTrigger(AuthorizationLevel.Function, "post", Route = null)] HttpRequestData req,
        CancellationToken cancellationToken)
    {
        _logger.LogInformation("CallLogicApp function triggered.");

        try
        {
            // ── Step 1: Read required configuration from app settings ──────────────────────────
            var logicAppUrl = Environment.GetEnvironmentVariable("LOGIC_APP_URL");

            if (string.IsNullOrWhiteSpace(logicAppUrl))
            {
                _logger.LogError("Missing required app setting: LOGIC_APP_URL");
                var badRequest = req.CreateResponse(HttpStatusCode.BadRequest);
                await badRequest.WriteAsJsonAsync(new
                {
                    error  = "MissingConfiguration",
                    detail = "LOGIC_APP_URL must be configured as an application setting.",
                    fix    = "In Azure Portal: Function App → Configuration → Application settings"
                }, HttpStatusCode.BadRequest, cancellationToken);
                return badRequest;
            }

            ScenarioRequest? scenarioRequest;
            try
            {
                scenarioRequest = await ReadScenarioRequestAsync(req, cancellationToken);
            }
            catch (JsonException ex)
            {
                _logger.LogWarning(ex, "Caller request body is not valid JSON.");
                var invalidRequest = req.CreateResponse(HttpStatusCode.BadRequest);
                await invalidRequest.WriteAsJsonAsync(new
                {
                    error = "InvalidRequest",
                    detail = "Request body must be valid JSON, for example: {\"scenario\":\"B1\"}."
                }, HttpStatusCode.BadRequest, cancellationToken);
                return invalidRequest;
            }

            var scenario = string.IsNullOrWhiteSpace(scenarioRequest?.Scenario)
                ? "default"
                : scenarioRequest.Scenario.Trim();
            var logicAppRequestUrl = AddQueryParameter(logicAppUrl, "scenario", scenario);

            // ── Step 2: Acquire bearer token from this Function App's managed identity ──────────
            var accessToken = await GetAccessTokenAsync(cancellationToken);
            var tokenClaims = ReadTokenClaims(accessToken.Token);
            _logger.LogInformation(
                "Bearer token acquired. Expiry: {Expiry}",
                accessToken.ExpiresOn.ToString("o"));
            _logger.LogInformation(
                "Token claims inspected locally. Audience: {Audience}; Issuer: {Issuer}; " +
                "Object ID: {ObjectId}; Caller app claim: {CallerAppId}; Expires: {ExpiresOn}",
                tokenClaims.Audience,
                tokenClaims.Issuer,
                tokenClaims.ObjectId,
                tokenClaims.CallerAppId,
                tokenClaims.ExpiresOn);

            // ── Step 3: POST to Logic App with bearer token in Authorization header ───────────
            // NOTE: No SAS signature or callback URL is needed.
            //       The Bearer token in the Authorization header provides authentication.
            //       Easy Auth on the Logic App validates the token signature, audience, and caller principal.
            var payload = new
            {
                message   = "Test from CallerFunctionApp",
                source    = Environment.GetEnvironmentVariable("WEBSITE_SITE_NAME") ?? "local-dev",
                scenario,
                timestamp = DateTime.UtcNow
            };

            var logicAppResponse = await CallLogicAppWithTokenAsync(
                logicAppRequestUrl,
                accessToken.Token,
                payload,
                cancellationToken);

            _logger.LogInformation("Logic App call completed successfully (bearer token validated by Easy Auth).");

            var ok = req.CreateResponse(HttpStatusCode.OK);
            await ok.WriteAsJsonAsync(new
            {
                status          = "success",
                message         = "Bearer token flow verified — Easy Auth accepted the request.",
                scenario,
                logicAppResponse,
                tokenClaims,
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
            }, HttpStatusCode.Unauthorized, cancellationToken);
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
            }, HttpStatusCode.Forbidden, cancellationToken);
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
            }, HttpStatusCode.InternalServerError, cancellationToken);
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
            }, HttpStatusCode.InternalServerError, cancellationToken);
            return res;
        }
    }

    // ── Private helpers ──────────────────────────────────────────────────────────────────────────

    private static async Task<ScenarioRequest?> ReadScenarioRequestAsync(
        HttpRequestData request,
        CancellationToken cancellationToken)
    {
        using var reader = new StreamReader(
            request.Body,
            Encoding.UTF8,
            detectEncodingFromByteOrderMarks: true,
            bufferSize: 1024,
            leaveOpen: true);
        var json = await reader.ReadToEndAsync(cancellationToken);
        return string.IsNullOrWhiteSpace(json)
            ? null
            : JsonSerializer.Deserialize<ScenarioRequest>(json, new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            });
    }

    private static string AddQueryParameter(string url, string name, string value)
    {
        var separator = url.Contains('?', StringComparison.Ordinal) ? '&' : '?';
        return $"{url}{separator}{Uri.EscapeDataString(name)}={Uri.EscapeDataString(value)}";
    }

    private static TokenClaims ReadTokenClaims(string token)
    {
        var segments = token.Split('.');
        if (segments.Length != 3)
        {
            throw new InvalidOperationException("The acquired access token is not a three-segment JWT.");
        }

        var payload = segments[1].Replace('-', '+').Replace('_', '/');
        payload += (payload.Length % 4) switch
        {
            2 => "==",
            3 => "=",
            0 => string.Empty,
            _ => throw new InvalidOperationException("The acquired access token has invalid Base64Url encoding.")
        };

        using var document = JsonDocument.Parse(Convert.FromBase64String(payload));
        var claims = document.RootElement;
        var expiresOn = claims.TryGetProperty("exp", out var expiryClaim) && expiryClaim.TryGetInt64(out var expiry)
            ? DateTimeOffset.FromUnixTimeSeconds(expiry)
            : (DateTimeOffset?)null;

        return new TokenClaims(
            GetStringClaim(claims, "aud"),
            GetStringClaim(claims, "iss"),
            GetStringClaim(claims, "oid"),
            GetStringClaim(claims, "azp") ?? GetStringClaim(claims, "appid"),
            expiresOn);
    }

    private static string? GetStringClaim(JsonElement claims, string claimName)
    {
        if (!claims.TryGetProperty(claimName, out var claim))
        {
            return null;
        }

        return claim.ValueKind switch
        {
            JsonValueKind.String => claim.GetString(),
            JsonValueKind.Array => string.Join(",", claim.EnumerateArray().Select(value => value.GetString())),
            _ => claim.ToString()
        };
    }

    /// <summary>
    /// Acquires a bearer token for the Logic App resource using DefaultAzureCredential.
    /// Uses the Logic App's Entra app registration client ID (GUID format) as the resource identifier.
    /// This is recognized by Entra ID and allows token acquisition for service-to-service calls.
    /// In Azure: resolves to the Function App system-assigned managed identity.
    /// Locally: resolves to the Azure CLI signed-in user (run: az login --tenant {tenantId}).
    /// </summary>
    private async Task<AccessToken> GetAccessTokenAsync(CancellationToken cancellationToken)
    {
        var tenantId = Environment.GetEnvironmentVariable("WEBSITE_AUTH_AAD_ALLOWED_TENANTS");

        // LOGIC_APP_AUDIENCE is the app setting deployed alongside this Function App
        // (see infra/modules/functionapp-caller.bicep) and it must match one of the
        // allowedAudiences configured on the Logic App's Easy Auth (infra/modules/easyauth.bicep).
        // Its value is the Application ID URI, e.g. api://<logic-app-app-registration-client-id>.
        var logicAppAudience = Environment.GetEnvironmentVariable("LOGIC_APP_AUDIENCE");
        if (string.IsNullOrWhiteSpace(logicAppAudience))
        {
            throw new InvalidOperationException(
                "LOGIC_APP_AUDIENCE is required. Find the Application ID URI in Microsoft Entra ID " +
                "> App registrations > the Logic App API registration > Expose an API.");
        }

        // DefaultAzureCredential tries: env vars → managed identity → Azure CLI → Visual Studio → …
        // In production the managed identity is used automatically.
        var credential = new DefaultAzureCredential(new DefaultAzureCredentialOptions
        {
            TenantId = tenantId
        });

        _logger.LogInformation(
            "Acquiring token for Logic App (audience): {Audience}, tenant: {TenantId}",
            logicAppAudience, tenantId ?? "<default>");

        // Use the Application ID URI (audience) as the resource for token acquisition.
        // This scope format is what Entra ID expects for app-to-app authentication and
        // matches the aud claim validated by Easy Auth's allowedAudiences.
        return await credential.GetTokenAsync(
            new TokenRequestContext(scopes: [$"{logicAppAudience}/.default"]),
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

        _logger.LogInformation("POST → Logic App: {Url}", url);

        var response = await client.SendAsync(request, cancellationToken);

        _logger.LogInformation(
            "Logic App response: HTTP {StatusCode}",
            (int)response.StatusCode);

        response.EnsureSuccessStatusCode();

        return await response.Content.ReadAsStringAsync(cancellationToken);
    }

    private sealed record TokenClaims(
        string? Audience,
        string? Issuer,
        string? ObjectId,
        string? CallerAppId,
        DateTimeOffset? ExpiresOn);

    private sealed record ScenarioRequest(string? Scenario);
}
