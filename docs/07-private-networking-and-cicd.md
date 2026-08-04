# Private networking and CI/CD

The active classroom path keeps the Function App and Logic App public while Easy Auth protects the Logic App trigger. The shared storage account remains private. This split keeps the identity lesson deployable from a normal workstation without weakening the managed-identity flow.

## Classroom baseline

| Surface | Classroom setting | Security control |
| --- | --- | --- |
| Logic App endpoint | Public | Easy Auth `Return401`, allowed audience, and `allowedPrincipals` |
| Function App endpoint | Public | Easy Auth `AllowAnonymous`; lab-only test harness |
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

The classroom baseline uses `Return401` so an anonymous trigger call proves HTTP 401. Strict Easy Auth can affect Logic Apps portal runtime operations such as callback URL retrieval or run details because those requests also traverse App Service authentication. Treat `AllowAnonymous` or carefully scoped excluded runtime paths as an advanced manageability investigation, not the secured classroom baseline.

References:

- [App Service authentication and authorization](https://learn.microsoft.com/azure/app-service/overview-authentication-authorization)
- [Deploy files to App Service](https://learn.microsoft.com/azure/app-service/deploy-zip)
- [App Service private endpoints](https://learn.microsoft.com/azure/app-service/overview-private-endpoint)
- [Azure Pipelines agents](https://learn.microsoft.com/azure/devops/pipelines/agents/agents)
