---
applyTo: '**'
description: 'Instructions for Copilot agents reviewing and improving the Azure Logic App Easy Auth lab.'
---

# Lab review instructions

Use these instructions when reviewing or improving this repository as an Azure hands-on lab.

## Repository context

This repository contains a hands-on lab for Azure Logic App Standard, Azure Functions, and App Service Authentication, also known as Easy Auth.

The intended learning goal is to help participants understand how a Function App can trigger a Logic App Standard workflow by using Microsoft Entra authentication instead of SAS tokens.

The target audience is technical but beginner-to-intermediate for identity and networking. Assume participants have limited experience with:

- Microsoft Entra ID
- OAuth 2.0 and OpenID Connect
- App Service Authentication / Easy Auth
- Managed identities
- Azure Functions
- Logic App Standard
- Private endpoints
- Virtual networks
- Private DNS
- CI/CD deployments into private Azure environments

The lab should explain concepts before using them.

## Mandatory Microsoft Learn MCP usage

For Microsoft technology research, use the Microsoft Learn MCP server first.

The repository is expected to have the Microsoft Learn MCP server configured as an HTTP MCP server with this endpoint:

https://learn.microsoft.com/api/mcp

Use the Microsoft Learn MCP tools when researching documentation, especially:

- MicrosoftLearn/microsoft_docs_search
- MicrosoftLearn/microsoft_docs_fetch
- MicrosoftLearn/microsoft_code_sample_search

Prefer official Microsoft Learn documentation over general web results.

Use Microsoft Learn documentation for recommendations about:

- App Service Authentication and Authorization / Easy Auth
- Azure Functions authentication
- Managed identities
- Logic App Standard
- Microsoft Entra ID app registrations
- OAuth 2.0 access tokens
- Private endpoints
- Virtual network integration
- Private DNS
- CI/CD deployments to private Azure resources
- Monitoring and troubleshooting Azure-hosted applications

Where useful, include Microsoft Learn training modules or self-paced learning paths.

Use non-Microsoft sources only as secondary context. Clearly label them as blog, community, or non-authoritative guidance.

## Review mode versus implementation mode

When asked to review the lab, do not immediately rewrite the full lab.

First create or update this file:

ASSESSMENT_AND_PLAN.md

The main output should be a readable assessment and a concrete improvement plan that another Copilot agent can execute in a follow-up task.

Only make small, low-risk fixes during the review task if they are necessary to produce the assessment file.

Do not perform broad restructuring, large documentation rewrites, or code changes during the review task unless the user explicitly asks for implementation.

## Repository inspection scope

Inspect the repository before making recommendations.

Review, where present:

- README files
- Markdown lab instructions
- Source code
- Azure Functions code
- Logic App workflow definitions
- Bicep, ARM, Terraform, or other infrastructure files
- GitHub Actions workflows
- Deployment scripts
- Configuration files
- Diagrams
- Existing docs folders
- Existing labs folders

Do not assume repository behavior without inspecting files.

If something cannot be determined from the repository, say so explicitly in ASSESSMENT_AND_PLAN.md.

## Key questions to answer in the assessment

Explicitly answer these questions:

1. Does the lab clearly explain the purpose of Easy Auth?
2. Does the lab explain why Easy Auth is preferred over SAS tokens in this scenario?
3. Does the lab explain the authentication flow between the Function App and the Logic App?
4. Does the lab explain which identity is used to call the Logic App?
5. Does the lab explain how Microsoft Entra ID validates the caller?
6. Does the lab explain what access token is requested and why?
7. Does the lab explain the difference between authentication and authorization?
8. Does the lab explain how the participant can validate that the flow works?
9. Does the lab include troubleshooting guidance?
10. Does the lab configure or mention private endpoints, virtual networks, private DNS, access restrictions, or disabled public network access?
11. If private networking is configured or intended, does the lab warn about deployment limitations?
12. Does the lab explain that GitHub-hosted runners or Azure DevOps Microsoft-hosted agents may not be able to deploy into private environments unless network access is available?
13. Does the lab explain possible portal, monitoring, and run-history limitations for Logic App Standard when private networking is used?

## Private networking and CI/CD review

Validate whether the repository creates or configures any of the following:

- Virtual networks
- Subnets
- Private endpoints
- Private DNS zones
- Regional VNet integration
- Public network access restrictions
- Access restrictions
- Locked-down Logic App Standard networking
- Locked-down Function App networking

If private networking is present, intended, or recommended, explain the deployment impact clearly.

Assess whether deployment would likely work or fail from:

- Developer laptop
- GitHub-hosted runner
- Azure DevOps Microsoft-hosted agent
- Self-hosted GitHub runner inside the VNet
- Self-hosted Azure DevOps agent inside the VNet

Explain DNS and network reachability requirements.

Do not guess. If the repository does not contain enough information to determine the behavior, state that clearly.

## Required secondary references

Review and summarize these two articles as part of the assessment:

- Microsoft Tech Community blog: https://techcommunity.microsoft.com/blog/integrationsonazureblog/easy-auth-configuration-for-logic-app-standard-through-cicd/4520539
- Community blog: https://azcloudsecurity.io/blog/logic-app-standard-easy-auth.

For each article:

- Provide a short summary
- Explain why it matters to this lab
- Identify caveats that should be added to the lab
- Explain CI/CD implications
- Explain monitoring or portal implications
- Explain private networking implications, if relevant

Prefer Microsoft Learn as the authoritative source whenever official documentation exists.

## Required ASSESSMENT_AND_PLAN.md structure

Create or update ASSESSMENT_AND_PLAN.md with these sections:

# Assessment and improvement plan

## 1. Executive summary

Provide a concise and readable summary of the current quality of the lab.

Include:

- What the lab is trying to teach
- Whether the current structure supports that goal
- Main strengths
- Main gaps
- Biggest risk for participants

Make this section understandable for the lab owner, not only for deep technical readers.

## 2. Current lab flow

Summarize the current lab flow as it exists today.

Describe the major steps participants are expected to follow.

Do not invent steps. Base this section only on repository contents.

## 3. Target learning journey

Describe the recommended learning journey as a clear step-by-step manual.

Include these kinds of steps where appropriate:

1. Understand the scenario
2. Understand Easy Auth
3. Understand the identity flow
4. Deploy prerequisites
5. Deploy the Function App and Logic App
6. Configure authentication
7. Test the end-to-end call
8. Validate logs and tokens
9. Troubleshoot common issues
10. Understand production and private networking considerations

For each recommended step, include:

- Purpose of the step
- What the participant should learn
- Which repository files likely need changes
- Official Microsoft documentation links to include

## 4. Findings

Create a findings table with these columns:

- Priority
- Area
- Finding
- Why it matters
- Recommended fix
- Suggested owner
- Source or documentation reference

Use these priority values:

- Critical
- High
- Medium
- Low

For Suggested owner, use "Next Copilot implementation agent" unless the finding requires clarification from the repository owner.

Prioritize findings that affect:

- Learning clarity
- Authentication correctness
- Security
- Deployment reliability
- Private networking
- Troubleshooting

## 5. Missing explanations for beginners

List concepts that need better explanation for the target audience.

At minimum consider:

- Easy Auth
- App Service Authentication
- Microsoft Entra ID
- App registration
- Managed identity
- Access token
- Audience
- Resource
- Scope
- Authentication versus authorization
- Function-to-Logic-App call flow
- SAS token versus Entra-authenticated call
- Private endpoint
- Private DNS
- VNet integration
- CI/CD runner network access

For each concept, provide:

- Beginner-friendly explanation
- Where the explanation should be added
- Official Microsoft documentation link

## 6. Private networking and CI/CD caveats

Create a dedicated section explaining:

- Whether the repository currently configures private networking
- What changes if public access is disabled
- Why GitHub-hosted runners or Azure DevOps Microsoft-hosted agents may not be able to deploy into a private environment
- When a self-hosted runner or agent inside the VNet is required
- What DNS configuration is required
- What participant warnings should be added to the lab
- What portal or monitoring limitations may appear for Logic App Standard when private networking is used

Use Microsoft Learn documentation wherever available.

Also include short summaries of the Microsoft Tech Community and community blog references listed above.

## 7. Proposed repository changes

Create a concrete change plan for the next implementation agent.

Group changes by file.

For each file, include:

- File path
- Change type: create, update, delete, or rename
- Summary of the change
- Detailed instructions
- Acceptance criteria

If new files are recommended, explain their purpose.

Possible files may include:

- README.md
- docs/01-prerequisites.md
- docs/02-easyauth-concepts.md
- docs/03-deployment.md
- docs/04-function-to-logicapp-auth-flow.md
- docs/05-validation.md
- docs/06-troubleshooting.md
- docs/07-private-networking-and-cicd.md
- An architecture diagram file, if useful

Do not create the full rewritten lab in the review task unless small fixes are obvious and low risk.

## 8. Copilot implementation plan

Create a section written specifically for the next Copilot agent.

Make it actionable and task-oriented.

Organize it into these phases:

### Phase 1: Documentation structure

Include:

- Task
- Files to modify
- Expected outcome
- Acceptance criteria

### Phase 2: Identity and Easy Auth explanation

Include:

- Task
- Files to modify
- Expected outcome
- Acceptance criteria

### Phase 3: Deployment guidance

Include:

- Task
- Files to modify
- Expected outcome
- Acceptance criteria

### Phase 4: Validation and troubleshooting

Include:

- Task
- Files to modify
- Expected outcome
- Acceptance criteria

### Phase 5: Private networking and CI/CD caveats

Include:

- Task
- Files to modify
- Expected outcome
- Acceptance criteria

### Phase 6: Final review

Include:

- Task
- Files to modify
- Expected outcome
- Acceptance criteria

## 9. Acceptance criteria for the improved lab

Define final acceptance criteria for the improved repository.

Include criteria such as:

- A beginner can understand the scenario before deploying
- Prerequisites are clearly listed
- Easy Auth and Microsoft Entra ID concepts are explained before implementation
- The Function App to Logic App authentication flow is documented
- Official Microsoft Learn links are included for all major concepts
- The lab includes validation steps
- The lab includes troubleshooting steps
- Private networking and CI/CD caveats are documented
- The lab avoids SAS tokens for the primary secured flow
- The lab clearly states what is demo or lab-only versus production-ready

## 10. Open questions

List any questions that the next agent or repository owner should clarify before making major changes.

Do not block the assessment on these questions.

## Writing standards

Write clearly and practically.

Avoid vague recommendations.

Do not only say "add more documentation". Specify what to add and where.

Use beginner-friendly language for conceptual explanations.

Keep the assessment readable for both technical and non-technical lab owners.

Include official Microsoft Learn links for every major Microsoft recommendation.

If a recommendation is based on a blog or community source, clearly label that source.

Do not overstate certainty. If repository evidence is incomplete, state the limitation.

## Completion behavior

After creating or updating ASSESSMENT_AND_PLAN.md, provide a final response that includes:

- The file path that was changed
- A short summary of what was assessed
- The biggest gaps found
- The first recommended task for the next Copilot implementation agent

If a pull request is required, create a pull request with a concise title and summary.
