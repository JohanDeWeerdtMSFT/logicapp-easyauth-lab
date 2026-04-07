# Mission
Build a reproducible Azure lab for Logic App Standard Easy Auth to validate the portal-manageability issue and secure mitigations.

# Hard Access Gate (must pass before coding)
1. Verify Azure MCP access in subscription `6851693c-0b74-4462-8da8-cd498b088827`.
2. Verify GitHub authentication and repository creation permission.
3. Ensure repository exists and is private: `logicapp-easyauth-lab`.

# Primary Scope
1. Logic App Standard is primary and blocking.
2. Track A: Portal manageability validation.
3. Track B: Trigger security validation.
4. Function Apps are optional and non-blocking (comparison only).

# Regions
1. Primary: `westeurope`.
2. Fallback: `swedencentral`.

# Required Deliverables
1. `infra/` modular Bicep templates.
2. `scripts/deploy.ps1` for what-if + deploy flow.
3. `scripts/validate.ps1` for Track A and Track B execution.
4. `README.md` with evidence matrix and conclusions.

# Stop/Go Gates
1. Access Gate: Azure MCP + GitHub access validated.
2. Merge Gate: lane outputs aligned on contracts and IDs.
3. Deploy Gate: what-if and validations pass.
4. Evidence Gate: complete matrix with correlation IDs and screenshots.

# Copilot CLI Kickoff Prompt
Paste this into Copilot CLI:

```text
Read HANDOFF.md, LANES.md, CHECKLIST.md.
Execute Hard Access Gate first and stop if any gate fails.
Then run lanes in parallel:
- Lane A: IaC scaffold + modules
- Lane B: Logic App + authsettingsV2 modes (Return401/AllowAnonymous)
- Lane C: Evidence templates and findings log
- Lane D: optional Function comparison
Use merge gates between lanes, then run what-if + deploy.
Run Track A and Track B validations and update README continuously.
```