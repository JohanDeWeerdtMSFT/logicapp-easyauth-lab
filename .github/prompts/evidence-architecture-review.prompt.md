# Evidence Architecture Review Prompt Blueprint

Use this blueprint for clean-slate architecture review runs that refresh Azure evidence for the Easy Auth lab and regenerate customer-facing documentation focused on Logic App Standard behavior.

## Run Inputs

- Subscription ID: <subscription-id>
- Resource Group: <resource-group>
- Logic App Name: <logic-app-standard-name>
- Primary customer doc: README.md

## Mandatory Mode

- Use Azure Principal Architect reasoning mode for architecture analysis and documentation structure.
- Use diagram skills in this order:
  1. Azure icon-based diagrams (preferred)
  2. draw.io diagram generation and SVG export
  3. Mermaid as secondary/source representation only

## Non-Negotiable Rules

1. Source of truth is live inventory scan output.
2. Never invent architecture elements.
3. If data is missing, write `Not found in deployment evidence`.
4. Documentation/diagram work only; no runtime code changes.
5. Perform clean scan and clean rewrite (within auto-generated sections).
6. Keep scope tied to Logic App Standard Easy Auth validation tracks:
  - Track A: Portal manageability
  - Track B: Trigger security

## Step 0: Documentation Boundaries

Ensure auto-generated sections exist once in customer document. Keep edits inside those sections.

Required sections:

- Executive Summary
- Architecture Overview
- Main Architecture Diagram
- Diagram Legend
- Platform And Network Architecture
- Identity, Authentication And Zero Trust
- Easy Auth Configuration Modes
- Validation Tracks (Track A and Track B)
- Optional Function App Comparison Lane
- Inventory Overview
- Operational Notes
- Alignment With WAF And CAF
- Evidence And Last Updated
- Diagram Sources (Mermaid)

## Step 1: Clean Inventory Scan

Write fresh timestamped outputs under:

- documentation/azure-scan/azure/<resource-group>/<timestamp>/

Azure minimum files:

- resources.json
- vnets.json
- subnets.json
- privateEndpoints.json
- privateDnsZones.json
- privateDnsLinks.json
- natGateways.json
- appIdentityAndAuth.json
- logicAppAuthSettingsV2.json
- workflowRunHistory.json
- appInsightsTrackAQueries.json
- appInsightsTrackBQueries.json

If a collector cannot retrieve an artifact, create file with [] and document reason in notes.

## Step 2: Architecture Story Planning

Build narrative in this order:

1. Executive Summary
2. High-Level Overview
3. Network and Platform Architecture
4. Identity and Zero Trust
5. Easy Auth Mode Design (Return401 vs AllowAnonymous)
6. Validation Track A (Portal Manageability)
7. Validation Track B (Trigger Security)
8. Optional Function Comparison Notes
9. Inventory Overview
10. Operational Notes
11. WAF and CAF Alignment

## Step 3: Diagram Strategy

Required primary visuals:

1. Overall Architecture Diagram
2. Network and Private Endpoint Diagram
3. Track A Portal Interaction Flow Diagram
4. Track B Trigger Security Flow Diagram

Rules:

- Embed SVGs directly in customer doc.
- Add legend and short reading guidance for each diagram set.
- Keep Mermaid as secondary source under diagram sources.
- Mermaid compatibility: prefer quoted labels and <br/> breaks for Mermaid 10.9.5.

## Step 4: Content Accuracy Rules

- Mark portal-manageability findings as Verified only when run-history and run-detail behavior is evidenced.
- Distinguish Easy Auth behavior from networking restrictions when private endpoint mode is enabled.
- For Easy Auth, use `unknown from scan artifacts` unless explicit `authsettingsV2` values are captured.
- For Track B, include status and evidence for: valid token, invalid token, wrong audience/principal, and no-token scenarios.

## Step 5: Finalization

Append:

- Evidence paths and timestamps
- Diagram source appendix
- Short change summary with validated hypotheses, unresolved gaps, and recommended operating mode

## Asset References

Use with:

- .github/instructions/evidence-refresh-and-docgen.instructions.md
- .github/skills/azure-evidence-docgen.md
- .github/skills/azure-architecture-autopilot/SKILL.md
- .github/skills/azure-resource-visualizer.md
- .github/skills/draw-io-diagram-generator.md
- .github/instructions/infra-doc-sync.instructions.md
- HANDOFF.md
- LANES.md
- CHECKLIST.md
