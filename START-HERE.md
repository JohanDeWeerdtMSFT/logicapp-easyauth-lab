# How to Use This Repository

Welcome! This repository contains production-tested security patterns for Azure Logic App Standard. This guide helps you navigate to exactly what you need.

---

## I'm New — Where Do I Start?

### Start with: [README.md](README.md)

The README contains:
- Overview of all three security patterns
- A 6-step learning path
- Quick links to all documentation

**Read time:** 10 minutes

---

## I Need to Deploy Lab 1, Lab 2, or Lab 3

### Lab 1: Entra ID Authentication with Easy Auth

**What you'll learn:** How to enforce Entra ID identity verification on Logic App HTTP triggers while preserving Azure portal management.

**Go to:** 
1. Read [README.md — Lab 1 Section](README.md#lab-1--easy-auth-with-entra-id-authentication)
2. Deploy using Bicep: [infra/main.bicep](infra/main.bicep) with `deployFuncCallerDemo = false`
3. Test using [docs/lab3-testing-and-verification.md](docs/lab3-testing-and-verification.md) (adapted for Lab 1)

**Bicep infrastructure:** [infra/modules/](infra/modules/)

**Decision:** Use Lab 1 if you need to enforce identity per Logic App with minimal architectural overhead.

---

### Lab 2: Centralized Gateway Security with APIM

**What you'll learn:** How to consolidate JWT validation at API Management instead of configuring each Logic App individually.

**Go to:**
1. Read [README.md — Lab 2 Section](README.md#lab-2--centralized-gateway-security-with-apim) (coming soon)
2. Deploy using Bicep: [infra/apim-lab/main.bicep](infra/apim-lab/main.bicep)
3. Test: Check [documentation/architecture/lab2-apim.html](documentation/architecture/lab2-apim.html)

**Bicep infrastructure:** [infra/apim-lab/](infra/apim-lab/)

**Decision:** Use Lab 2 if you have many Logic Apps that need consistent JWT validation and you want to manage authentication centrally.

---

### Lab 3: Secure Service-to-Service Calls with Managed Identity

**What you'll learn:** How to enable Function Apps (or other services) to call Logic Apps using bearer tokens with automatic credential rotation.

**Go to:**
1. Read [README.md — Lab 3 Section](README.md#lab-3--secure-service-to-service-calls-with-managed-identity--bearer-tokens)
2. Deployment: Start with [docs/lab3-testing-evidence-summary.md](docs/lab3-testing-evidence-summary.md) — it includes step-by-step deployment
3. Complete Testing Guide: [docs/lab3-testing-and-verification.md](docs/lab3-testing-and-verification.md)
4. Quick Reference: [docs/lab3-quick-reference-card.md](docs/lab3-quick-reference-card.md) (printable)

**Bicep infrastructure:** [infra/modules/](infra/modules/) — Lab 3 extends Lab 1 in the same resource group

**Decision:** Use Lab 3 if you need app-to-app communication without managing secrets, rotating credentials, or storing connection strings.

---

## I Need to Understand the Differences Between Labs

### Go to: [docs/decision-guidance.md](docs/decision-guidance.md)

This document explains:
- Trade-offs between the three patterns
- When to use each pattern
- Real-world decision criteria
- Architecture comparisons

---

## I Want to Test Lab 3 and Collect Evidence

### Complete Test & Deployment Path:

1. **Quick overview:** [docs/lab3-testing-evidence-summary.md](docs/lab3-testing-evidence-summary.md) — 10 minute read
2. **Step-by-step:** [docs/lab3-testing-and-verification.md](docs/lab3-testing-and-verification.md) — follow all sections
3. **Quick reference:** [docs/lab3-quick-reference-card.md](docs/lab3-quick-reference-card.md) — use during testing

These guides include:
- Complete C# code for the test Function App
- Infrastructure verification checklist
- How to invoke the function and monitor logs
- How to collect evidence (JWT tokens, logs, execution history)
- Troubleshooting for 6 common errors

---

## I Want to Review the Architecture

### Interactive HTML Documentation

- **Lab 3 Complete Guide:** [documentation/architecture/lab3-bearer-token-flow.html](documentation/architecture/lab3-bearer-token-flow.html) — Open in browser
  - 13 comprehensive sections
  - Mermaid diagrams showing data flow
  - JWT token structure breakdown
  - C# code examples
  - Easy Auth validation process
  - Bearer token vs SAS token comparison

- **Home Page:** [documentation/index.html](documentation/index.html) — Open in browser
  - Overview of all three patterns
  - Architectural diagrams
  - Decision guidance

### Markdown Documentation

- **Lab 3 Deep-Dive:** [docs/lab3-managed-identity-bearer-token-flow.md](docs/lab3-managed-identity-bearer-token-flow.md)
- **Decision Guidance:** [docs/decision-guidance.md](docs/decision-guidance.md)

---

## I Want to Use the Bicep Infrastructure in My Own Project

### Bicep Modules

Lab 3 infrastructure includes reusable Bicep modules:

| Module | Location | Purpose |
|--------|----------|---------|
| Function App with Bearer Token Support | [infra/modules/functionapp-caller.bicep](infra/modules/functionapp-caller.bicep) | S1 plan, managed identity, VNet integration |
| Logic App with Easy Auth | [infra/modules/logicapp.bicep](infra/modules/logicapp.bicep) | WS1 plan, private endpoint protection |
| Easy Auth Configuration | [infra/modules/easyauth.bicep](infra/modules/easyauth.bicep) | AllowAnonymous + allowedPrincipals filter |
| Virtual Network & Private Endpoints | [infra/modules/networking.bicep](infra/modules/networking.bicep) | VNet, subnets, private DNS, private endpoints |

**How to use:**
1. Copy the modules that match your needs
2. Create a new Bicep file that calls these modules with your parameters
3. Reference [infra/main.bicep](infra/main.bicep) as an example of how to compose them

---

## I Found an Issue or Have Questions

### Check the Troubleshooting Sections

- **Lab 3 Testing:** [docs/lab3-testing-and-verification.md#troubleshooting-checklist](docs/lab3-testing-and-verification.md#troubleshooting-checklist) — Common issues and fixes
- **Quick Reference:** [docs/lab3-quick-reference-card.md#common-errors--quick-fixes](docs/lab3-quick-reference-card.md#common-errors--quick-fixes)

---

## Quick Navigation Map

```
README.md
├─ Overview of all three patterns
├─ Learning Path (6 steps)
├─ Lab 1: Easy Auth
├─ Lab 2: APIM-Centric
└─ Lab 3: Managed Identity

docs/decision-guidance.md
└─ When to use each pattern

docs/lab3-testing-evidence-summary.md
├─ What's deployed
├─ 4-step testing process
└─ Evidence collection

docs/lab3-testing-and-verification.md
├─ Prerequisites & setup
├─ Infrastructure verification
├─ Create test Function App (C# code)
├─ Deploy to Azure
├─ Run & monitor tests
├─ Collect evidence
└─ Troubleshooting checklist

docs/lab3-quick-reference-card.md
├─ Pre-test checklist
├─ Code essentials
├─ Test execution steps
├─ Success indicators
└─ Common errors & fixes

documentation/
├─ index.html (home page with all patterns)
└─ architecture/
    ├─ lab3-bearer-token-flow.html (13-section deep-dive)
    └─ [other lab documentation]

infra/
├─ main.bicep (Lab 1 & 3)
├─ apim-lab/main.bicep (Lab 2)
└─ modules/ (reusable components)
```

---

## File Structure by Customer Need

**I want to learn:** → README.md → docs/decision-guidance.md → documentation/

**I want to test Lab 3:** → docs/lab3-testing-evidence-summary.md → docs/lab3-testing-and-verification.md → docs/lab3-quick-reference-card.md

**I want to deploy Lab 1:** → README.md (Lab 1 section) → infra/main.bicep

**I want to deploy Lab 2:** → README.md (Lab 2 section) → infra/apim-lab/main.bicep

**I want to deploy Lab 3:** → docs/lab3-testing-evidence-summary.md → docs/lab3-testing-and-verification.md → infra/main.bicep

**I want reference code:** → docs/lab3-testing-and-verification.md (C# examples) → documentation/architecture/lab3-bearer-token-flow.html (code + diagrams)

**I need Bicep modules:** → infra/modules/ → review [infra/main.bicep](infra/main.bicep) for usage examples

---

## Document Quality

All documentation in this repository is:
- ✅ Customer-ready with professional tone
- ✅ Step-by-step with clear instructions
- ✅ Complete with code examples
- ✅ Tested in production environments
- ✅ Linked and cross-referenced

---

**Questions?** Start with the README, then follow the learning path that matches your need.
