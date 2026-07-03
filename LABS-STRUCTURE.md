# Easy Auth Lab Structure

This repository contains three progressive labs demonstrating passwordless authentication patterns with Azure Logic Apps and Azure Functions.

## Directory Organization

```
EasyAuth/
├── labs/                              # Lab implementations
│   ├── lab1-easyauth/                 # Lab 1: Easy Auth Basics
│   │   ├── docs/                      # Lab 1 documentation
│   │   ├── infra/                     # Lab 1 infrastructure (Bicep)
│   │   └── workflows/                 # Lab 1 Logic App workflows
│   │
│   ├── lab2-managed-identity/         # Lab 2: Managed Identity Basics
│   │   ├── docs/                      # Lab 2 documentation
│   │   ├── infra/                     # Lab 2 infrastructure (Bicep)
│   │   └── workflows/                 # Lab 2 Logic App workflows
│   │
│   └── lab3-bearer-token/             # Lab 3: Bearer Token Authentication
│       ├── docs/                      # Lab 3 documentation
│       ├── functions/                 # Azure Function App source code
│       ├── workflows/                 # Logic App workflows
│       ├── infra/                     # Infrastructure (Bicep)
│       ├── scripts/                   # Lab 3 deployment scripts
│       └── tests/                     # Test scripts and evidence
│
├── guides/                            # Customer-facing guides
│   ├── BEARER-TOKEN-TESTING-GUIDE.md  # How to test bearer token flow
│   ├── BEARER-TOKEN-FIX-SUMMARY.md    # Summary of the solution
│   ├── LAB-IMPLEMENTATION-SUMMARY.md  # Implementation details
│   ├── DEPLOYMENT-QUICK-REF.md        # Quick reference for deployment
│   ├── TEST-EXECUTION-RESULTS.md      # Test results and verification
│   ├── E2E-TEST-SUMMARY.md            # End-to-end test summary
│   ├── troubleshooting.md             # Troubleshooting guide
│   └── decision-guidance.md           # Architecture decision guidance
│
├── scripts/                           # Top-level scripts
│   ├── deploy.ps1                     # Main deployment script
│   ├── validate.ps1                   # Validation script
│   └── setup.ps1                      # Setup script
│
├── infra/                             # Shared infrastructure
│   ├── main.bicep                     # Root Bicep template
│   ├── main.json                      # Compiled ARM template
│   ├── modules/                       # Reusable Bicep modules
│   └── params/                        # Parameter files by region
│
├── src/                               # Shared source code
│   ├── workflows/                     # Logic App workflow definitions
│   ├── host.json                      # Function App host config
│   └── local.settings.json            # Local development settings
│
├── documentation/                     # Generated documentation
│   ├── index.html                     # Documentation home
│   ├── architecture/                  # Architecture diagrams
│   └── evidence/                      # Implementation evidence
│
├── .github/                           # GitHub configuration
│   ├── instructions/                  # Coding guidelines
│   ├── skills/                        # Agent skills
│   └── workflows/                     # CI/CD workflows
│
├── README.md                          # Main readme
├── START-HERE.md                      # Getting started guide
├── CHECKLIST.md                       # Implementation checklist
├── HANDOFF.md                         # Handoff documentation
└── LANES.md                           # Work breakdown
```

## Lab Overview

### Lab 1: Easy Auth Basics
- **Goal**: Understand Azure Easy Auth middleware
- **Components**: Logic App with Easy Auth enabled
- **Learning**: How Easy Auth validates bearer tokens
- **Location**: `labs/lab1-easyauth/`

### Lab 2: Managed Identity Basics
- **Goal**: Introduce Managed Identity for passwordless authentication
- **Components**: Function App with system-assigned identity, Logic App with Easy Auth
- **Learning**: How system-assigned identities work without storing secrets
- **Location**: `labs/lab2-managed-identity/`

### Lab 3: Bearer Token Authentication
- **Goal**: Implement end-to-end bearer token authentication
- **Components**: 
  - Function App (caller) with Managed Identity
  - Logic App (receiver) with Easy Auth
  - Bearer token flow via HTTP
- **Key Pattern**: Passwordless service-to-service communication
- **Location**: `labs/lab3-bearer-token/`
- **Features**:
  - DefaultAzureCredential for token acquisition
  - Token scope: `{logicAppClientId}/.default`
  - Authorization header in HTTP request
  - Easy Auth validation on Logic App

## Getting Started

1. **Start here**: [START-HERE.md](./START-HERE.md)
2. **Review guides**: Check `/guides/` for testing and implementation guides
3. **Choose your lab**: Navigate to the appropriate `/labs/` folder
4. **Review documentation**: Each lab has its own `/docs/` with instructions
5. **Deploy infrastructure**: Use the Bicep templates in `/infra/`
6. **Deploy code**: Use scripts in `/scripts/` or lab-specific scripts

## File Organization Principles

### ✅ What's in Each Lab Directory

Each lab folder contains:
- **`docs/`**: Lab-specific documentation
- **`infra/`**: Infrastructure as Code (Bicep templates)
- **`workflows/`**: Logic App workflow definitions
- **`functions/`** (Lab 3 only): Function App source code
- **`scripts/`** (Lab 3 only): Deployment and test scripts
- **`tests/`** (Lab 3 only): Test evidence and results

### ✅ What's in `/guides/`

Customer-facing documentation:
- Testing procedures
- Implementation summaries
- Troubleshooting guidance
- Deployment quick references
- Architecture decisions

### ✅ What's in `/scripts/`

Top-level deployment scripts:
- `deploy.ps1`: Main deployment
- `validate.ps1`: Infrastructure validation
- `setup.ps1`: Environment setup

### ✅ What's in `/infra/`

Shared infrastructure templates:
- `main.bicep`: Root template
- `modules/`: Reusable components
- `params/`: Parameter files for different regions

## Removed Files

The following temporary and intermediate files have been removed for cleaner organization:

- ❌ `ANONYMIZATION-COMPLETE.md` (metadata)
- ❌ `ANONYMIZATION-VERIFICATION.md` (metadata)
- ❌ `TOKEN-FIX-ANALYSIS.md` (analysis artifact)
- ❌ `test-results.txt` (temporary output)
- ❌ `token.txt` (security issue)
- ❌ `func-apps.txt` (temporary list)
- ❌ `funcapp-list.json` (temporary config)
- ❌ Zip artifacts and temporary configurations
- ❌ Duplicate `Ores-easyauth/` directory
- ❌ Old variant deployment scripts
- ❌ Temporary test scripts

## Quick Reference

### Finding Lab 3 Bearer Token Implementation

```
labs/lab3-bearer-token/
├── functions/CallerFunctionApp/          ← Function App code
│   └── CallLogicApp.cs                   ← Bearer token implementation
├── workflows/httpTriggerWorkflow/        ← Logic App HTTP trigger
├── infra/                                ← Bicep templates
├── scripts/test-bearer-token.ps1         ← Test script
└── docs/                                 ← Testing guides and results
    ├── BEARER-TOKEN-TEST-EVIDENCE.md
    └── lab3-*.md files
```

### Customer Delivery Files

All anonymized customer-ready documentation is in `/guides/`:
- `BEARER-TOKEN-TESTING-GUIDE.md`
- `LAB-IMPLEMENTATION-SUMMARY.md`
- `TEST-EXECUTION-RESULTS.md`

## Navigation

- **Learning Path**: Lab 1 → Lab 2 → Lab 3
- **Implementation**: Start with `/guides/BEARER-TOKEN-TESTING-GUIDE.md`
- **Troubleshooting**: See `/guides/troubleshooting.md`
- **Architecture**: See `/guides/decision-guidance.md`

## Related Files

- **Getting Started**: [START-HERE.md](./START-HERE.md)
- **Implementation Plan**: [CHECKLIST.md](./CHECKLIST.md)
- **Handoff Details**: [HANDOFF.md](./HANDOFF.md)
