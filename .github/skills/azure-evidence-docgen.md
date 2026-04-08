---
name: azure-evidence-docgen
description: Refresh latest Azure and Power Platform evidence, then regenerate customer/internal architecture docs and diagrams (Mermaid and Azure-icon based) in a repeatable way. Use for scan, evidence sync, architecture narrative updates, and diagram refresh.
---

# Azure Evidence Docgen

Use this skill when the request is to refresh cloud evidence and regenerate architecture documentation artifacts.

## Use Cases

- "Refresh Azure and Power Platform scans"
- "Regenerate customer-demo-setup from latest evidence"
- "Update architecture docs after infra changes"
- "Fix Mermaid and keep icon diagrams in sync"

## Required Inputs

- Azure subscription and target resource group
- Power Platform environment name/ID
- Documentation targets (customer/internal)

## Execution Workflow

1. Verify auth contexts (Azure + Power Platform/Dataverse).
2. Create new timestamped evidence folders.
3. Refresh Azure evidence and Power Platform evidence.
4. Update customer/internal docs using evidence-only claims.
5. Regenerate diagrams:
   - Mermaid diagrams in HTML (`<div class="mermaid">...</div>`)
   - **CRITICAL: DO NOT use `<br/>` or HTML tags inside Mermaid node labels** — this causes "Syntax error in text" parser failures in Mermaid 10.9.5. Keep node labels as simple single-line text and use surrounding HTML for multi-line descriptions instead.
   - Azure icon-based diagrams via repo visualizer/autopilot skills
6. Validate anchors/links/timestamps and keep hubs synchronized.

## Required Documentation Narrative Order

When generating `documentation/architecture/customer-demo-setup.html`, keep this chapter order so the document reads like a coherent architecture book:

1. Executive Summary
2. High-Level Architecture Overview
3. Platform And Network Architecture
4. Identity, Authentication, And Zero Trust
5. Power Platform To Azure Integration
6. Application Architecture (Python to Microservices)
7. Secure Automation And Connector Flow
8. Inventory Overview
9. Operational Notes
10. Alignment With Microsoft Best Practices (WAF/CAF)
11. Evidence And Last Updated
12. Diagram Sources (Mermaid secondary)

## Evidence-Only Writing Rules

1. Do not invent claims; if absent, write `Not found in deployment evidence`.
2. Keep verified and unverified paths explicit.
3. Treat EasyAuth as `unknown from scan artifacts` unless explicit enabled/disabled values are captured.
4. Keep customer and internal narratives separated and cross-linked.

## Mermaid Compatibility Rules

1. Use rendered Mermaid containers, not source-only pre blocks.
2. Keep source text in `<details>` when transparency is needed.
3. For Mermaid 10.9.5:
   - Use quoted labels for complex node text.
   - Prefer `<br/>` line breaks over escaped `\\n` in flowchart labels.

## Reusable Prompt Template

For full clean-slate scan and rewrite sessions, use:

- `.github/prompts/evidence-architecture-review.prompt.md`

This template encodes mandatory constraints, topic coverage, scan requirements, and diagram strategy.

## Additional Awesome Copilot Assets To Invoke

### Discovery helpers

- `suggest-awesome-github-copilot-agents`
- `suggest-awesome-github-copilot-skills`
- `suggest-awesome-github-copilot-instructions`

### Repo agents

- `.github/agents/azure-principal-architect.agent.md`
- `.github/agents/azure-iac-generator.agent.md`
- `.github/agents/azure-logic-apps-expert.agent.md`
- `.github/agents/power-platform-expert.agent.md`

### Repo instructions

- `.github/instructions/infra-doc-sync.instructions.md`
- `.github/instructions/azure-logic-apps-power-automate.instructions.md`
- `.github/instructions/dataverse-mcp-agent.instructions.md`
- `.github/instructions/evidence-refresh-and-docgen.instructions.md`

### Repo skills

- `.github/skills/azure-architecture-autopilot/SKILL.md`
- `.github/skills/azure-resource-visualizer.md`
- `.github/skills/draw-io-diagram-generator.md`
- `.github/skills/azure-deployment-preflight.md`

## Completion Checklist

1. New evidence timestamp is reflected in docs and diagram metadata.
2. Customer and internal hub links still resolve.
3. Mermaid diagrams render without parser errors.
4. Icon-based architecture artifact is updated.
5. Operational defaults in active docs/config remain aligned with current resource group/environment.
