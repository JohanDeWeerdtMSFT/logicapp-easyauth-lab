# Mission

Build and validate **two complementary Azure labs** that demonstrate different security patterns for Logic App Standard HTTP triggers, helping the customer make informed architecture decisions.

## Lab 1 — Easy Auth–Centric Security

Validate that Easy Auth (`authsettingsV2`) can secure Logic App Standard HTTP triggers **without breaking portal manageability**, using the `AllowAnonymous` + `allowedPrincipals` pattern from [azcloudsecurity.io](https://azcloudsecurity.io/posts/logic-app-standard-easy-auth/).

- Resource Group: `rg-la-easyauth-lab-dev`
- Goal: Prove Easy Auth works for **limited numbers of apps** when configured correctly
- Key insight: Use `AllowAnonymous` (not `Return401`) — requests with an Authorization header are still validated; SAS keys remain available as a trigger mechanism

## Lab 2 — APIM-Centric Security (No Easy Auth on Host)

Demonstrate centralized JWT validation at API Management, with backend Logic Apps protected via network access restrictions instead of Easy Auth.

- Resource Group: `rg-la-easyauth-lab-apim-dev`
- Goal: Prove APIM-fronted architecture works at scale (hundreds of apps) without per-app Easy Auth or Private Endpoints

> Some references combine API Management and Easy Auth for defense‑in‑depth identity enforcement. While valid, enabling Easy Auth on Logic Apps Standard can introduce operational complexity and runtime manageability risks. This lab demonstrates an alternative pattern where API Management enforces identity centrally, and backend Logic Apps are protected using network-level access restrictions, reducing the need for per-app Private Endpoints and preserving portal functionality.

# Hard Access Gate (must pass before coding)

1. Verify Azure MCP access in subscription `6851693c-0b74-4462-8da8-cd498b088827`.
2. Verify GitHub authentication and repository creation permission.
3. Ensure repository exists and is private: `logicapp-easyauth-lab`.

# Primary Scope

1. Logic App Standard is primary and blocking for both labs.
2. **Lab 1 Tracks**:
   - Track A: Portal manageability with AllowAnonymous + SAS disable
   - Track B: Trigger security (Entra token enforcement despite AllowAnonymous)
3. **Lab 2 Tracks**:
   - Track C: APIM JWT validation (valid/invalid/missing token)
   - Track D: Backend isolation (Logic App unreachable without APIM)
   - Track E: Portal manageability (confirmed working — no Easy Auth)
4. Cross-lab comparison and decision guidance.

# Regions

1. Primary: `westeurope`.
2. Fallback: `swedencentral`.

# Required Deliverables

1. `infra/` modular Bicep templates (Lab 1: Easy Auth modules).
2. `infra/apim-lab/` Bicep templates (Lab 2: APIM + Logic App).
3. `scripts/deploy.ps1` for Lab 1 what-if + deploy flow.
4. `scripts/validate.ps1` for Lab 1 Track A and Track B execution.
5. `README.md` with evidence matrix and conclusions for Lab 1.
6. `docs/apim-lab-plan.md` with architecture and validation for Lab 2.
7. `docs/decision-guidance.md` — customer-facing comparison of both patterns.
8. `docs/evidence/findings.md` with consolidated findings from both labs.

# Stop/Go Gates

1. Access Gate: Azure MCP + GitHub access validated.
2. Merge Gate: lane outputs aligned on contracts and IDs.
3. Deploy Gate: what-if and validations pass for both labs.
4. Evidence Gate: complete matrix with correlation IDs and screenshots.
5. Comparison Gate: decision guidance document completed with trade-off analysis.

# Copilot CLI Kickoff Prompt

Paste this into Copilot CLI:

```text
Read HANDOFF.md, LANES.md, CHECKLIST.md.
Execute Hard Access Gate first and stop if any gate fails.
Then run lanes:
- Lane A: IaC scaffold + modules (both labs)
- Lane B: Lab 1 — Easy Auth with AllowAnonymous + SAS disable pattern
- Lane C: Lab 2 — APIM + Logic App (no Easy Auth)
- Lane D: Evidence templates and findings log
- Lane E: Decision guidance document
Use merge gates between lanes, then deploy both labs.
Run Track A/B (Lab 1) and Track C/D/E (Lab 2) validations.
Update README and decision guidance continuously.
```