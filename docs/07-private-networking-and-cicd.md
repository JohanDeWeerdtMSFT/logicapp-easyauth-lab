# Private networking and CI/CD

The active classroom path keeps the Function App and Logic App public while Easy Auth protects the Logic App trigger. The shared storage account remains private. This split keeps the identity lesson deployable from a normal workstation without weakening the managed-identity flow.

## Classroom baseline

| Surface | Classroom setting | Security control |
| --- | --- | --- |
| Logic App endpoint | Public | Easy Auth `Return401`, allowed audience, and `allowedPrincipals` |
| Function App endpoint | Public | Function-key-protected trigger; Easy Auth `AllowAnonymous` behind the lab guard |
| Storage account | Private | Blob, Queue, Table, and File private endpoints plus managed-identity RBAC |
| Function-to-Logic-App call | Public HTTPS | Entra bearer token issued to the Function managed identity |

Use the normal deployment command without `-EnablePrivateAppNetworking` for this mode.
If an earlier deployment created a Logic App private endpoint, `scripts/deploy.ps1` removes that retained endpoint after a successful public-mode deployment because incremental ARM deployments do not delete resources omitted from the template.

## Optional private app ingress

Add `-EnablePrivateAppNetworking` to create private Logic App ingress. The identity flow does not change, but deployment and testing must originate from a network that can resolve and reach both:

- `<logic-app>.azurewebsites.net`
- `<logic-app>.scm.azurewebsites.net`

Microsoft Learn states that Visual Studio Code and Azure CLI deployment to a private Standard Logic App work only from inside the virtual network. See [Secure Standard logic apps with private endpoints](https://learn.microsoft.com/azure/logic-apps/secure-single-tenant-workflow-virtual-network-private-endpoint).

## Executor matrix

| Executor | ARM/Bicep | ZIP/Kudu to public classroom apps | ZIP/Kudu to private apps |
| --- | --- | --- | --- |
| Developer workstation | Yes | Yes | Only with VNet route and private DNS |
| GitHub-hosted runner | Yes | Yes | No private reachability by default |
| Azure DevOps Microsoft-hosted agent | Yes | Yes | No private reachability by default |
| Self-hosted runner or agent in the VNet | Yes | Yes | Recommended |

Infrastructure deployment uses the Azure Resource Manager control plane. Workflow and Function content deployment use App Service SCM/Kudu, so private ingress affects them differently.

## DNS requirements

Private ingress requires the `privatelink.azurewebsites.net` zone to be linked to the executor's reachable VNet. The zone must contain both the app and `.scm` records. A TCP connection alone is not sufficient; DNS, routing, and TLS must all reach the Azure private endpoint.

## Portal and run-history caveat

The classroom baseline uses `Return401` and excludes only `/runtime/*` from Easy Auth. Logic Apps run-history requests can therefore reach the runtime and use the runtime's own authorization, while the public workflow trigger under `/api/*` still requires a valid Entra bearer token. A direct unsigned trigger call continues to return HTTP 401.

The Azure portal does not expose `excludedPaths`. Keep this setting in Bicep so later deployments do not restore the run-history HTTP 401 failure.

References:

- [App Service authentication and authorization](https://learn.microsoft.com/azure/app-service/overview-authentication-authorization)
- [Easy Auth configuration for Logic App Standard through CI/CD](https://techcommunity.microsoft.com/blog/integrationsonazureblog/easy-auth-configuration-for-logic-app-standard-through-cicd/4520539)
- [Deploy files to App Service](https://learn.microsoft.com/azure/app-service/deploy-zip)
- [App Service private endpoints](https://learn.microsoft.com/azure/app-service/overview-private-endpoint)
- [Azure Pipelines agents](https://learn.microsoft.com/azure/devops/pipelines/agents/agents)
