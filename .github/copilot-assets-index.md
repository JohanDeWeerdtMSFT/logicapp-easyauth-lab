# Copilot Assets Index

This index maps imported Copilot assets to the implementation lanes used in this repository.

## Lane Mapping

### Lane A: IaC Foundation
- Agents:
  - `.github/agents/azure-iac-generator.agent.md`
  - `.github/agents/azure-iac-exporter.agent.md`
  - `.github/agents/azure-principal-architect.agent.md`
- Instructions:
  - `.github/instructions/bicep-code-best-practices.instructions.md`
- Skills:
  - `.github/skills/azure-deployment-preflight.md`
  - `.github/skills/cloud-design-patterns/SKILL.md`

### Lane B: Logic App + Easy Auth
- Agents:
  - `.github/agents/azure-logic-apps-expert.agent.md`
  - `.github/agents/azure-principal-architect.agent.md`
- Instructions:
  - `.github/instructions/azure-logic-apps-power-automate.instructions.md`
- Skills:
  - `.github/skills/azure-architecture-autopilot/SKILL.md`

### Lane C: Evidence and Customer Artifacts
- Instructions:
  - `.github/instructions/evidence-refresh-and-docgen.instructions.md`
  - `.github/instructions/markdown-gfm.instructions.md`
- Prompts:
  - `.github/prompts/evidence-architecture-review.prompt.md`
- Skills:
  - `.github/skills/azure-evidence-docgen.md`
  - `.github/skills/azure-resource-visualizer.md`
  - `.github/skills/draw-io-diagram-generator.md`

### Lane D: Optional Platform Comparison
- Agents:
  - `.github/agents/principal-software-engineer.agent.md`
  - `.github/agents/devops-expert.agent.md`

## Recommended Invocation Order
1. Run Access Gate checks first.
2. Start Lanes A, B, and C in parallel.
3. Run Lane D only if comparison evidence is needed.
4. Use preflight skill before any deploy action.

## Notes
- This index is intentionally short and lane-oriented.
- Asset source copy was imported from your personal assets repo and merged into `.github`.
