# Assessment and improvement plan

## 1. Executive summary

This lab is designed to teach how a Function App can call a Logic App Standard workflow by using Microsoft Entra access tokens with Easy Auth, instead of SAS signatures.

The current repository has strong technical assets: infrastructure-as-code modules, a working Function caller sample, test and verification guides, troubleshooting content, and evidence-oriented scenario IDs. The structure does support the goal, but it is currently fragmented across many files and sometimes assumes prior identity/networking knowledge.

Main strengths:

- Core scenario is present and mostly consistent across README, lab docs, infra, and testing artifacts.
- Security-first implementation pattern exists (managed identity, token audience, allowed principals, private endpoint, private DNS).
- Helpful validation assets exist (scenario matrix, verification docs, troubleshooting).

Main gaps:

- Beginner conceptual explanations are not consistently introduced before implementation steps.
- CI/CD and private-network deployment caveats are not consolidated in a single, explicit “deployment constraints” learning section.
- External reference integration is incomplete: required blog references are not summarized in the lab itself, and one required blog was inaccessible during this assessment run.

Biggest risk for participants:

- Participants may follow deployment steps without understanding authentication versus authorization boundaries, then misdiagnose 401/403/network failures—especially in private networking and hosted-runner CI/CD contexts.

## 2. Current lab flow

Based on repository content, the effective current flow is:

1. Start from `README.md` and `START-HERE.md`.
2. Understand active scope (Lab 3 only) and target architecture.
3. Configure environment values using `.env.example` and deploy infra using `scripts/deploy.ps1`.
4. Follow Lab 3 guides:
   - `docs/lab3-passwordless-managed-identity-easy-auth.md`
   - `docs/lab3-testing-and-verification.md`
   - `docs/lab3-quick-reference-card.md`
5. Deploy Function code from `solution/` and workflow definition from `src/httpTriggerWorkflow/workflow.json`.
6. Validate behavior using scenario IDs and evidence docs:
   - `docs/evidence/scenario-ids.md`
   - `docs/evidence/findings.md`
   - `docs/lab3-testing-evidence-summary.md`
7. Troubleshoot with `docs/troubleshooting.md` and `DEPLOYMENT-FAQ.md`.

## 3. Target learning journey

Recommended learner journey for beginner-to-intermediate identity/networking audience:

1. **Understand the scenario**
   - Purpose: Explain business problem and why this lab exists.
   - Participant learns: What is being secured (Function → Logic App trigger) and what “secure by identity” means.
   - Files likely to change: `/home/runner/work/logicapp-easyauth-lab/logicapp-easyauth-lab/README.md`, `/home/runner/work/logicapp-easyauth-lab/logicapp-easyauth-lab/START-HERE.md`
   - Microsoft docs to include:
     - https://learn.microsoft.com/azure/logic-apps/single-tenant-overview-compare
     - https://learn.microsoft.com/azure/app-service/overview-authentication-authorization

2. **Understand Easy Auth**
   - Purpose: Explain Easy Auth role in front-door token validation.
   - Participant learns: Easy Auth middleware behavior, where it runs, and `authsettingsV2` basics.
   - Files likely to change: `/home/runner/work/logicapp-easyauth-lab/logicapp-easyauth-lab/docs/lab3-passwordless-managed-identity-easy-auth.md`
   - Microsoft docs to include:
     - https://learn.microsoft.com/azure/app-service/overview-authentication-authorization
     - https://learn.microsoft.com/azure/app-service/configure-authentication-provider-aad

3. **Understand the identity flow**
   - Purpose: Explain how Function managed identity gets token and how Logic App validates it.
   - Participant learns: audience/resource/scope (`api://.../.default`), token claims, `allowedPrincipals`.
   - Files likely to change: `/home/runner/work/logicapp-easyauth-lab/logicapp-easyauth-lab/docs/lab3-managed-identity-bearer-token-flow.md`
   - Microsoft docs to include:
     - https://learn.microsoft.com/azure/active-directory/managed-identities-azure-resources/overview
     - https://learn.microsoft.com/dotnet/azure/sdk/authentication/credential-chains

4. **Deploy prerequisites**
   - Purpose: Prevent deployment-time confusion.
   - Participant learns: minimum prerequisites, tenant/app registration values, role requirements.
   - Files likely to change: `/home/runner/work/logicapp-easyauth-lab/logicapp-easyauth-lab/README.md`, `/home/runner/work/logicapp-easyauth-lab/logicapp-easyauth-lab/DEPLOYMENT-FAQ.md`
   - Microsoft docs to include:
     - https://learn.microsoft.com/entra/identity-platform/quickstart-register-app
     - https://learn.microsoft.com/entra/identity-platform/scenario-protected-web-api-expose-scopes

5. **Deploy Function App and Logic App**
   - Purpose: Execute controlled deployment.
   - Participant learns: what IaC creates, what is post-deploy manual, and where runtime code is deployed.
   - Files likely to change: `/home/runner/work/logicapp-easyauth-lab/logicapp-easyauth-lab/docs/lab3-passwordless-managed-identity-easy-auth.md`, `/home/runner/work/logicapp-easyauth-lab/logicapp-easyauth-lab/docs/lab3-testing-and-verification.md`
   - Microsoft docs to include:
     - https://learn.microsoft.com/azure/logic-apps/create-single-tenant-workflows-azure-portal
     - https://learn.microsoft.com/azure/azure-functions/functions-deployment-technologies

6. **Configure authentication**
   - Purpose: Ensure caller and receiver trust settings are correct.
   - Participant learns: Easy Auth config, tenant constraints, principal allow-listing.
   - Files likely to change: `/home/runner/work/logicapp-easyauth-lab/logicapp-easyauth-lab/docs/lab3-passwordless-managed-identity-easy-auth.md`
   - Microsoft docs to include:
     - https://learn.microsoft.com/azure/app-service/configure-authentication-provider-aad
     - https://learn.microsoft.com/azure/app-service/overview-authentication-authorization

7. **Test end-to-end call**
   - Purpose: Verify secure call behavior and expected HTTP outcomes.
   - Participant learns: success/failure pattern differences (200, 401, 403, timeout).
   - Files likely to change: `/home/runner/work/logicapp-easyauth-lab/logicapp-easyauth-lab/docs/lab3-testing-and-verification.md`
   - Microsoft docs to include:
     - https://learn.microsoft.com/azure/azure-monitor/app/monitor-functions
     - https://learn.microsoft.com/azure/logic-apps/monitor-logic-apps

8. **Validate logs and tokens**
   - Purpose: Build confidence in identity path, not just HTTP status.
   - Participant learns: where to inspect traces, run history, and key validation indicators.
   - Files likely to change: `/home/runner/work/logicapp-easyauth-lab/logicapp-easyauth-lab/docs/lab3-testing-evidence-summary.md`, `/home/runner/work/logicapp-easyauth-lab/logicapp-easyauth-lab/docs/evidence/findings.md`
   - Microsoft docs to include:
     - https://learn.microsoft.com/azure/azure-monitor/app/logs-overview
     - https://learn.microsoft.com/azure/logic-apps/monitor-logic-apps

9. **Troubleshoot common issues**
   - Purpose: Reduce learner blockers and support self-recovery.
   - Participant learns: root-cause flow for identity, policy, DNS, and networking failures.
   - Files likely to change: `/home/runner/work/logicapp-easyauth-lab/logicapp-easyauth-lab/docs/troubleshooting.md`
   - Microsoft docs to include:
     - https://learn.microsoft.com/azure/active-directory/managed-identities-azure-resources/troubleshoot
     - https://learn.microsoft.com/azure/private-link/private-endpoint-dns

10. **Understand production and private networking considerations**
    - Purpose: Prevent production misapplication of lab assumptions.
    - Participant learns: deployment channel limitations, hosted-runner constraints, DNS requirements, operational caveats.
    - Files likely to change: new `/home/runner/work/logicapp-easyauth-lab/logicapp-easyauth-lab/docs/07-private-networking-and-cicd.md` (or equivalent), plus `/home/runner/work/logicapp-easyauth-lab/logicapp-easyauth-lab/README.md`
    - Microsoft docs to include:
      - https://learn.microsoft.com/azure/app-service/overview-private-endpoint
      - https://learn.microsoft.com/azure/azure-functions/functions-create-vnet
      - https://learn.microsoft.com/azure/devops/pipelines/agents/agents

## 4. Findings

| Priority | Area | Finding | Why it matters | Recommended fix | Suggested owner | Source or documentation reference |
| --- | --- | --- | --- | --- | --- | --- |
| High | Learning clarity | Concept explanations are spread across multiple files and not consistently ordered from “why” to “how.” | Beginners may deploy without understanding identity/security rationale. | Add a structured concepts-first section and unify cross-links in README and START-HERE. | Next Copilot implementation agent | `/home/runner/work/logicapp-easyauth-lab/logicapp-easyauth-lab/README.md`, `/home/runner/work/logicapp-easyauth-lab/logicapp-easyauth-lab/START-HERE.md` |
| High | Authentication correctness | Audience/resource/scope and `allowedPrincipals` rationale are present but not consistently beginner-framed before hands-on steps. | Misconfiguration here causes 401/403 and confusion about identity trust model. | Add explicit beginner explanations and validation checklist in concept and testing docs. | Next Copilot implementation agent | `/home/runner/work/logicapp-easyauth-lab/logicapp-easyauth-lab/docs/lab3-passwordless-managed-identity-easy-auth.md`, `/home/runner/work/logicapp-easyauth-lab/logicapp-easyauth-lab/docs/lab3-testing-and-verification.md` |
| High | Private networking + CI/CD | Private endpoint/VNet/private DNS are implemented in IaC, but deployment constraints for hosted runners are not consolidated as a mandatory caveat section. | Participants may expect GitHub-hosted or Microsoft-hosted agents to deploy into private-only environments without network reachability. | Add dedicated private-networking-and-CI/CD caveats doc and link it prominently. | Next Copilot implementation agent | `infra/modules/networking.bicep`, `infra/modules/logicapp.bicep`, Microsoft docs on private endpoint and agent networking |
| Medium | Troubleshooting | Existing troubleshooting is broad, but lab-specific triage flow (auth vs authorization vs DNS path) can be sharper. | Faster diagnosis improves lab completion rate and confidence. | Add decision tree and scenario-ID mapping for common failures. | Next Copilot implementation agent | `/home/runner/work/logicapp-easyauth-lab/logicapp-easyauth-lab/docs/troubleshooting.md`, `/home/runner/work/logicapp-easyauth-lab/logicapp-easyauth-lab/docs/evidence/scenario-ids.md` |
| Medium | Documentation authority | Required secondary blog references are not integrated into a formal caveat section; one blog is currently inaccessible from this environment. | Missing cross-source caveats weakens guidance on CI/CD and portal behavior nuances. | Include best-effort blog summaries with explicit accessibility status and pair each point with Microsoft Learn authoritative references. | Next Copilot implementation agent | Tech Community URL, azcloudsecurity URL, Microsoft Learn refs |
| Low | Repository usability | Some docs include pointers that indicate moved content, which may add navigation friction for first-time users. | Extra navigation hops can reduce clarity in a beginner lab. | Consolidate canonical paths and reduce “moved” indirections where possible. | Next Copilot implementation agent | `/home/runner/work/logicapp-easyauth-lab/logicapp-easyauth-lab/docs/lab3-managed-identity-bearer-token-flow.md` |

## 5. Missing explanations for beginners

| Concept | Beginner-friendly explanation | Where to add | Official documentation link |
| --- | --- | --- | --- |
| Easy Auth | Easy Auth is built-in authentication middleware in App Service-hosted apps that checks incoming tokens before your workflow/function logic runs. | `docs/lab3-passwordless-managed-identity-easy-auth.md` intro | https://learn.microsoft.com/azure/app-service/overview-authentication-authorization |
| App Service Authentication | This is the platform feature set behind Easy Auth, including identity provider config, token validation, and auth enforcement behavior. | README “What You Will Achieve” or concepts doc | https://learn.microsoft.com/azure/app-service/configure-authentication-provider-aad |
| Microsoft Entra ID | Entra issues the access token that proves caller identity to the receiving app. | README architecture + concepts | https://learn.microsoft.com/entra/fundamentals/whatis |
| App registration | App registration defines application identity metadata in Entra (client ID, audience, exposed API). | prerequisites section | https://learn.microsoft.com/entra/identity-platform/quickstart-register-app |
| Managed identity | Managed identity is an Azure-managed service principal that lets apps request tokens without stored secrets. | concepts + deployment prerequisites | https://learn.microsoft.com/azure/active-directory/managed-identities-azure-resources/overview |
| Access token | A short-lived JWT used by caller to prove identity and authorization context to receiver. | identity flow section | https://learn.microsoft.com/entra/identity-platform/access-tokens |
| Audience | Audience (`aud`) identifies the intended API; receiver checks it to reject tokens meant for other resources. | identity flow + validation checklist | https://learn.microsoft.com/entra/identity-platform/access-token-claims-reference |
| Resource | Resource is the API identifier the caller wants a token for (often `api://<client-id>`). | identity flow section | https://learn.microsoft.com/entra/identity-platform/scopes-oidc |
| Scope | Scope communicates permissions; service-to-service pattern commonly uses `/.default` with app roles/permissions. | identity flow + code explanation | https://learn.microsoft.com/entra/identity-platform/scenario-protected-web-api-expose-scopes |
| Authentication vs authorization | Authentication answers “who are you”; authorization answers “are you allowed.” Easy Auth + `allowedPrincipals` demonstrate both. | concept doc + troubleshooting quick table | https://learn.microsoft.com/azure/app-service/overview-authentication-authorization |
| Function-to-Logic-App call flow | Function MI gets token from Entra, sends token to Logic App endpoint, Easy Auth validates token and principal before trigger runs. | architecture section + testing guide | https://learn.microsoft.com/azure/logic-apps/single-tenant-overview-compare |
| SAS token vs Entra-authenticated call | SAS uses shared secret-like signatures; Entra token flow is identity-based, short-lived, and centrally governed. | comparison section + README key takeaways | https://learn.microsoft.com/azure/storage/common/storage-sas-overview |
| Private endpoint | Private endpoint gives private IP access path so app endpoint is reachable only via private network routes. | private networking caveats doc | https://learn.microsoft.com/azure/app-service/overview-private-endpoint |
| Private DNS | Private DNS maps service hostnames to private endpoint IPs for in-VNet name resolution. | networking validation + troubleshooting | https://learn.microsoft.com/azure/private-link/private-endpoint-dns |
| VNet integration | VNet integration routes outbound app traffic through selected subnet/network controls. | deployment + networking sections | https://learn.microsoft.com/azure/azure-functions/functions-networking-options |
| CI/CD runner network access | Hosted runners/agents may lack network path and DNS to private endpoints; self-hosted inside reachable network is often required. | dedicated CI/CD caveats doc | https://learn.microsoft.com/azure/devops/pipelines/agents/agents |

## 6. Private networking and CI/CD caveats

### Repository evidence

From IaC modules, the repository does configure private networking patterns:

- VNet + subnets (`snet-app-integration`, `snet-privateendpoints`) and private DNS zone link are created in `infra/modules/networking.bicep`.
- Logic App module (`infra/modules/logicapp.bicep`) can disable public network access when private endpoint is configured (`publicNetworkAccess: Disabled`).
- Private endpoint and private DNS zone group are configured for Logic App host.
- Function App caller module uses VNet integration for outbound traffic (`vnetRouteAllEnabled: true`).

### What changes when public access is disabled

- Inbound access to the Logic App host is limited to private endpoint path.
- Any deployment/management channel that relies on public reachability can fail unless private reachability is available.
- DNS must resolve service hostnames to private IPs from the caller/deployment environment.

### CI/CD agent implications

- **GitHub-hosted runner:** likely fails for private-only deployment paths when endpoint is not publicly reachable and DNS/private routing are unavailable.
- **Azure DevOps Microsoft-hosted agent:** same risk profile as GitHub-hosted for private-only resources.
- **Developer laptop:** may work only if connected to the VNet path (VPN/ExpressRoute/peering) and DNS is correctly configured.
- **Self-hosted GitHub runner inside VNet:** generally suitable when it has private DNS and route reachability.
- **Self-hosted Azure DevOps agent inside VNet:** generally suitable under same conditions.

### DNS and reachability requirements

- Private DNS zone (`privatelink.azurewebsites.net`) must be linked to the correct VNet.
- A records/CNAME resolution chain must resolve app hostnames to private endpoint IP.
- NSG/UDR/firewall policy must allow required control/data paths.

### Participant warnings to add

- Warn that hosted CI runners may be unable to deploy to private-only app endpoints.
- Warn that private DNS misconfiguration can present as generic timeout/auth failures.
- Warn that production pipelines may need self-hosted agents in reachable networks.

### Portal/monitoring limitations to call out

- The repository’s evidence and findings already highlight manageability sensitivity around Easy Auth modes (`Return401` vs `AllowAnonymous`) for runtime/portal operations.
- Lab should explicitly state that some portal operations and run-history experiences can vary by auth/network posture and endpoint reachability.

### Required secondary references (best effort status)

1. **Microsoft Tech Community blog**  
   URL: https://techcommunity.microsoft.com/blog/integrationsonazureblog/easy-auth-configuration-for-logic-app-standard-through-cicd/4520539  
   - Access status in this run: page title was reachable, but article body content was not retrievable from this environment.  
   - Relevance: expected to discuss Easy Auth configuration through CI/CD for Logic App Standard.  
   - Caveat for lab: include explicit CI/CD sequencing, auth configuration ordering, and deployment-path caveats in private networking modes.  
   - CI/CD implication: treat auth configuration as part of repeatable IaC/pipeline flow, not ad-hoc portal-only steps.  
   - Monitoring/portal implication: validate post-deployment manageability scenarios, not only deployment success.  
   - Private networking implication: pipeline executor network placement matters when endpoints are private.

2. **Community blog (azcloudsecurity)**  
   URL: https://azcloudsecurity.io/blog/logic-app-standard-easy-auth  
   - Access status in this run: site shell reachable, but article body content not retrievable from this environment.  
   - Relevance: expected practical guidance on Logic App Standard Easy Auth and operational caveats.  
   - Caveat for lab: add explicit “community guidance is non-authoritative; validate against Microsoft Learn” note.  
   - CI/CD implication: emphasize deterministic deployment and validation checks after auth changes.  
   - Monitoring/portal implication: include expected runtime visibility checks in verification steps.  
   - Private networking implication: reinforce DNS + reachability dependencies for secure/private patterns.

> Note: This assessment is not blocked by inaccessible external body content; recommendations above are anchored primarily in repository evidence and official Microsoft Learn documentation.

## 7. Proposed repository changes

### File: `/home/runner/work/logicapp-easyauth-lab/logicapp-easyauth-lab/README.md`

- Change type: update
- Summary: improve entry flow, concept-first framing, and private networking/CI-CD warning signposts.
- Detailed instructions:
  - Add a short “Before you deploy” section with identity and networking prerequisites.
  - Add explicit warning box for private endpoint + hosted runner limitations.
  - Link directly to a dedicated private networking and CI/CD caveats doc.
- Acceptance criteria:
  - Beginners can identify prerequisites before running scripts.
  - Private deployment limitations are visible in first-screen documentation.

### File: `/home/runner/work/logicapp-easyauth-lab/logicapp-easyauth-lab/START-HERE.md`

- Change type: update
- Summary: make navigation strictly linear for first-time learners.
- Detailed instructions:
  - Add mandatory read order (concepts → deploy → validate → troubleshoot).
  - Reduce optional path ambiguity in quick-start sequence.
- Acceptance criteria:
  - A first-time user can complete Lab 3 without guessing next file.

### File: `/home/runner/work/logicapp-easyauth-lab/logicapp-easyauth-lab/docs/lab3-passwordless-managed-identity-easy-auth.md`

- Change type: update
- Summary: strengthen beginner explanations for authn/authz and token details.
- Detailed instructions:
  - Add short glossary block for audience/resource/scope/allowedPrincipals.
  - Add “why this is preferred over SAS for this lab” section.
- Acceptance criteria:
  - Doc explicitly explains which identity calls the Logic App and how Entra validates caller.

### File: `/home/runner/work/logicapp-easyauth-lab/logicapp-easyauth-lab/docs/lab3-testing-and-verification.md`

- Change type: update
- Summary: tighten validation and diagnostic pathways.
- Detailed instructions:
  - Add a concise failure triage table mapping 401/403/timeout to next checks.
  - Add token-claim and DNS verification checkpoints.
- Acceptance criteria:
  - User can distinguish auth failure from authorization and network failure in <10 minutes.

### File: `/home/runner/work/logicapp-easyauth-lab/logicapp-easyauth-lab/docs/troubleshooting.md`

- Change type: update
- Summary: convert broad troubleshooting into lab-specific decision path.
- Detailed instructions:
  - Add a decision tree structure (identity → policy → network).
  - Cross-link each branch to scenario IDs and commands already in repo.
- Acceptance criteria:
  - Troubleshooting starts with a clear first check and avoids duplicate checks.

### File: `/home/runner/work/logicapp-easyauth-lab/logicapp-easyauth-lab/docs/07-private-networking-and-cicd.md`

- Change type: create
- Summary: central source for private networking, deployment-path, runner placement, DNS, and portal/manageability caveats.
- Detailed instructions:
  - Explain deployment feasibility matrix by executor type (laptop/hosted/self-hosted).
  - Explain DNS prerequisites and private endpoint behavior.
  - Include authoritative Microsoft Learn links; label community references as secondary.
- Acceptance criteria:
  - Reader can decide whether hosted or self-hosted pipeline agent is required.

## 8. Copilot implementation plan

### Phase 1: Documentation structure

- Task: Reorganize entry docs into a strict beginner-first progression.
- Files to modify: `README.md`, `START-HERE.md`
- Expected outcome: clear “start here → concepts → deployment → validation → troubleshooting” path.
- Acceptance criteria: no ambiguous first steps; private networking caveat visible early.

### Phase 2: Identity and Easy Auth explanation

- Task: Add concise explanations of Easy Auth, Entra token flow, and authn/authz boundaries.
- Files to modify: `docs/lab3-passwordless-managed-identity-easy-auth.md`, `docs/lab3-managed-identity-bearer-token-flow.md`
- Expected outcome: beginner can explain who calls what, with which token, and why.
- Acceptance criteria: terms audience/resource/scope/allowedPrincipals are explained in-context.

### Phase 3: Deployment guidance

- Task: Clarify prerequisite data and deployment order.
- Files to modify: `README.md`, `DEPLOYMENT-FAQ.md`, `docs/lab3-passwordless-managed-identity-easy-auth.md`
- Expected outcome: fewer setup/deployment misconfigurations.
- Acceptance criteria: prerequisite checklist includes Entra app registration and tenant/client IDs.

### Phase 4: Validation and troubleshooting

- Task: Improve verification and root-cause navigation.
- Files to modify: `docs/lab3-testing-and-verification.md`, `docs/troubleshooting.md`, `docs/evidence/scenario-ids.md`
- Expected outcome: fast path from symptom to root cause.
- Acceptance criteria: explicit mappings for 401 vs 403 vs timeout and required evidence capture.

### Phase 5: Private networking and CI/CD caveats

- Task: Add consolidated caveats and deployment matrix for private environments.
- Files to modify: `docs/07-private-networking-and-cicd.md` (new), `README.md`
- Expected outcome: users understand hosted-runner limitations and when self-hosted is required.
- Acceptance criteria: matrix covers developer laptop, GitHub-hosted, ADO-hosted, and self-hosted options.

### Phase 6: Final review

- Task: Perform consistency and link-quality pass across updated docs.
- Files to modify: all touched markdown docs
- Expected outcome: no conflicting guidance and no broken key links.
- Acceptance criteria: all major concepts reference official Microsoft Learn; secondary references clearly labeled.

## 9. Acceptance criteria for the improved lab

- A beginner can understand the scenario before deploying.
- Prerequisites are clearly listed and ordered.
- Easy Auth and Microsoft Entra ID concepts are explained before implementation.
- The Function App to Logic App authentication flow is documented clearly.
- Official Microsoft Learn links are included for all major concepts.
- The lab includes validation steps with expected outcomes.
- The lab includes troubleshooting steps with root-cause flow.
- Private networking and CI/CD caveats are documented in a dedicated section.
- The lab avoids SAS tokens for the primary secured flow.
- The lab clearly separates lab/demo shortcuts from production-ready guidance.

## 10. Open questions

1. Should the lab require private networking by default for all participants, or provide a public-network quickstart variant for first-run learning?
2. Which CI/CD system is primary for the intended audience (GitHub Actions, Azure DevOps, or both) so deployment guidance can be prioritized?
3. Should the lab include a fully automated workflow deployment path (CLI/zip/ARM) to reduce portal dependency?
4. Is APIM intentionally out of scope for all learner tracks, or should an optional “production extension” track be added?
5. Which identity constraints are mandatory for learner completion versus advanced hardening steps?
6. Should portal manageability tradeoffs (`Return401` vs `AllowAnonymous`) be explicitly tested as required outcomes or optional advanced scenarios?
