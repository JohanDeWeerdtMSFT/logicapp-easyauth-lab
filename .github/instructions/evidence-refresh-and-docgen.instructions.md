---
description: "Refresh latest Azure Easy Auth lab evidence and regenerate architecture documentation artifacts"
applyTo: "documentation/**/*,documentation/architecture/scripts/**/*,refresh-azure-scan.ps1,README.md,HANDOFF.md,LANES.md,CHECKLIST.md"
---

# Evidence Refresh And Documentation Generation Rule

Use this rule for any request to re-scan Azure and regenerate architecture documentation for the Logic App Standard Easy Auth lab.

## Primary Objective

Keep documentation evidence-based, timestamp-aligned, and track-oriented around the two core validations:

1. Track A: Portal manageability
2. Track B: Trigger security

## Required Workflow

1. Verify authentication first:
	- Azure auth context must be valid.
	- Subscription context must match the active lab subscription.
2. Run a fresh Azure scan with a new timestamp folder.
3. Regenerate or update documentation from the latest evidence only.
4. Keep customer-facing summary aligned with current validation matrix and findings log.

## Non-Negotiable Constraints

1. No runtime code modifications when executing this workflow.
2. Live inventory scans are primary truth; IaC/docs are secondary and must align.
3. Perform clean scan + clean rewrite inside auto-generated sections.
4. Customer-facing documentation must remain readable and low-jargon.
5. Do not introduce Power Platform assumptions unless explicitly added to scope by the user.

## Evidence Sources (Preferred)

- Azure scan root:
  - `documentation/azure-scan/azure/<resource-group>/<timestamp>/`
- Core files for claims:
  - `resources.json`
  - `privateEndpoints.json`
  - `vnets.json`
  - `subnets.json`
  - `privateDnsZones.json`
  - `privateDnsLinks.json`
  - `natGateways.json`
  - `appIdentityAndAuth.json`
  - `logicAppAuthSettingsV2.json`
  - `workflowRunHistory.json`
  - `appInsightsTrackAQueries.json`
  - `appInsightsTrackBQueries.json`

If a collector cannot retrieve an artifact, create file with `[]` and document the reason in notes.

## Documentation Targets

- Primary report:
  - `README.md`
- Handoff controls:
  - `HANDOFF.md`
  - `LANES.md`
  - `CHECKLIST.md`

## Topic Coverage Matrix (Required In Primary Report)

Ensure the generated primary report covers each topic below with evidence-backed detail:

1. Executive Summary
	- Problem statement, validation status, and findings summary.
2. Architecture Overview
	- Major components and responsibility split.
3. Platform And Network Architecture
	- VNet, subnets, private endpoints, private DNS, and access interpretation.
4. Identity, Authentication, And Zero Trust
	- Managed identity usage, Easy Auth status, and trust boundaries.
5. Easy Auth Configuration Modes
	- `Return401` vs `AllowAnonymous` and intended behavior.
6. Validation Track A (Portal Manageability)
	- Run history, run details, inputs/outputs, and rerun/resubmit evidence.
7. Validation Track B (Trigger Security)
	- Valid token, invalid token, wrong audience/principal, no-token, and SAS-mode outcomes.
8. Optional Function App Comparison Lane
	- Include only as non-blocking reference evidence.
9. Inventory Overview
	- Azure resource inventory snapshot.
10. Operational Notes
	- Known limitations and unresolved validation items.
11. WAF And CAF Alignment
	- Principle-aligned statements only; no compliance certification claims.
12. Evidence And Last Updated
	- Explicit scan paths, timestamps, and correlation IDs.
13. Diagram Sources
	- Mermaid sources as secondary representation.

## Authoring Rules

1. Never invent architecture claims. If missing, write `Not found in deployment evidence`.
2. Keep summary content aligned with active lane outputs and scenario IDs.
3. Keep timestamp and evidence-path references synchronized across markdown, HTML, and diagram artifacts.
4. Prefer targeted cleanup in active docs/config over mass-editing archived/raw evidence.

## Easy Auth Clarification Rules

1. Distinguish verified vs unverified findings explicitly:
	- Mark Track A behavior as verified only when portal observations are evidenced.
	- Mark Track B behavior as verified only when status/result evidence is captured.
2. Distinguish auth behavior from networking behavior when private endpoint mode is enabled.
3. For Easy Auth, use neutral wording unless explicit values are present in evidence:
	- Recommended phrase: `unknown from scan artifacts`.

## Diagram Generation Rules

1. Mermaid in HTML must be rendered using `<div class="mermaid">...</div>`, not only `<pre>`.
2. Do not use ASCII-art diagrams for customer-facing architecture sections; replace with Mermaid and/or embedded image artifacts.
3. Keep source text in a collapsible `<details>` block when needed for transparency.
4. For Mermaid 10.9.5 compatibility:
	- Use quoted node labels when labels are complex.
	- Do not use `<br/>` or other HTML tags inside Mermaid node labels.
	- Keep node labels as simple single-line text.
	- If multi-line labels are needed, use surrounding markdown paragraphs.
	- Never use escaped `\\n`, HTML entities, or other special syntax within quoted node labels.
5. For Azure icon-based diagrams, use repo skills:
	- `azure-architecture-autopilot`
	- `azure-resource-visualizer`
	- `draw-io-diagram-generator`

## Additional Copilot Assets To Use

When running this workflow, explicitly leverage these helpers before large updates:

1. Repo agents to compose for execution:
	- `azure-principal-architect.agent.md`
	- `azure-iac-generator.agent.md`
	- `azure-logic-apps-expert.agent.md`
2. Repo instructions to apply during updates:
	- `bicep-code-best-practices.instructions.md`
	- `azure-logic-apps-power-automate.instructions.md`
	- `evidence-refresh-and-docgen.instructions.md`
3. Repo index for lane mapping:
	- `.github/copilot-assets-index.md`

## Reusable Prompt Blueprint

Use the stored prompt blueprint for high-rigor clean-slate architecture rewrite runs:

- `.github/prompts/evidence-architecture-review.prompt.md`

Guidance:

1. Prefer reusing this blueprint over ad-hoc long prompts.
2. Keep project-specific values in a short Run Inputs header before execution.
3. Treat blueprint sections as workflow phases, not optional suggestions.

## Completion Checklist

1. Latest scan timestamp is reflected in docs.
2. Primary report claims map to actual evidence files.
3. Diagram artifacts render (Mermaid and/or icon diagram).
4. Track A and Track B sections both contain evidence-backed outcomes.
5. Changed files are scoped and intentional.
6. Markdown links and anchors are valid.
7. Broken links are repaired to existing targets; do not replace links with placeholder text.
