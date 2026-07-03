# Azure Easy Auth Lab: Passwordless Authentication

## 🎓 Welcome!

This lab teaches you how to implement **passwordless, Zero Trust authentication** between Azure services using **Managed Identity** and **Easy Auth**.

By the end, you'll understand how to securely connect Azure services **without storing any credentials** in code or configuration.

---

## 📖 What You'll Learn

### Core Concepts
- **Managed Identity** — Passwordless credentials automatically managed by Azure
- **Bearer Tokens** — How token-based authentication works
- **Easy Auth** — Built-in authentication middleware for App Services
- **Zero Trust** — Never trust, always verify (identity-based security)

### Real-World Skills
- Deploy secure Azure infrastructure with Bicep (Infrastructure-as-Code)
- Write .NET code that acquires bearer tokens
- Configure Microsoft Entra ID (Azure AD) authentication
- Monitor and debug authentication flows
- Use private endpoints for network security

### What You'll Build
```
Function App (caller)
    ↓ Uses managed identity to get bearer token
    ↓ HTTPS POST to Logic App with Authorization: Bearer <token>
    ↓
Logic App (receiver)
    ↓ Easy Auth validates token
    ↓ Accepts request from Function App (in allowedPrincipals)
    ↓ Returns 200 OK
```

**Key Insight:** No passwords, API keys, or SAS signatures anywhere! 🔐

---

## ⏱️ Time Required

- **First time** (create all infrastructure): 30-45 minutes
- **Subsequent times** (just run setup.ps1): 15-20 minutes
- **Lab walkthrough** (understanding concepts): 30-45 minutes

---

## ✅ Prerequisites

### Tools You Need

| Tool | What It Does | Where to Get It |
|------|-------------|-----------------|
| **Azure CLI** | Command-line tool for Azure | [Download here](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) |
| **PowerShell** 7.0+ | Script automation | [Download here](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell) |
| **.NET 8 SDK** | Build & run C# code | [Download here](https://dotnet.microsoft.com/download/dotnet/8.0) |
| **Git** | Clone the repository | [Download here](https://git-scm.com/downloads) |
| **Text Editor** | Edit .env file | Any editor (VS Code, Notepad, etc.) |

### Azure Account

- **Free Azure subscription** ([Create one here](https://azure.microsoft.com/en-us/free/))
- **Owner or Contributor role** (to create resources)
- **Access to Microsoft Entra ID** (included in all Azure subscriptions)

### Verify You're Ready

Run these commands to check if everything is installed:

```bash
# Check each tool
az --version
pwsh --version  # or 'powershell' on older Windows
dotnet --version
git --version
```

**If any command fails**, install that tool before continuing.

---

## 🚀 Getting Started (3 Easy Steps)

### Step 1: Clone the Repository and Configure

```bash
# Clone the lab
git clone https://github.com/JohanDeWeerdtMSFT/logicapp-easyauth-lab.git
cd logicapp-easyauth-lab

# Copy the configuration template
cp .env.example .env

# Open .env in your editor
notepad .env              # Windows
# OR
nano .env                 # Mac/Linux
```

**Edit `.env` with your Azure values** (you need 5 values):

```env
# 1. Your subscription ID
AZURE_SUBSCRIPTION_ID=00000000-0000-0000-0000-000000000000

# 2. Your tenant ID (Entra ID directory ID)
AZURE_TENANT_ID=00000000-0000-0000-0000-000000000000

# 3. Azure region (closest to you)
AZURE_REGION=westeurope

# 4. Environment name (dev/test/prod)
ENVIRONMENT_NAME=dev

# 5. Your email (tags resources)
YOUR_EMAIL=you@example.com
```

**How to find these values:**

```bash
# Get your subscription ID
az account list --query "[].{name:name, subscriptionId:id}" --output table

# Get your tenant ID
az account show --query tenantId --output tsv

# List available regions
az account list-locations --query "[].name" -o table
```

### Step 2: Sign In and Deploy

```bash
# Sign in to Azure
az login --tenant <your-tenant-id>

# Deploy the infrastructure (reads .env automatically)
./setup.ps1

# Wait... (takes 15-20 minutes)
# Azure is creating:
#   • Resource Group
#   • Virtual Network
#   • Logic App Standard
#   • Function App
#   • Easy Auth configuration
#   • Application Insights
```

**What happens:** The `setup.ps1` script reads your `.env` file and creates all Azure resources automatically using Bicep (Infrastructure as Code).

### Step 3: Learn the Lab

Open the lab documentation and start learning:

```bash
# Open in VS Code
code docs/lab3-passwordless-managed-identity-easy-auth.md

# Or open in Notepad/TextEdit
notepad docs\lab3-passwordless-managed-identity-easy-auth.md  # Windows
open docs/lab3-passwordless-managed-identity-easy-auth.md     # Mac
```

**The lab guide explains:**
- How Managed Identity works (step by step)
- How bearer tokens are created and validated
- How Easy Auth protects your Logic App
- How to test the complete flow
- How to troubleshoot common issues

---

## 📁 Repository Structure

```
logicapp-easyauth-lab/
│
├── README.md                              ← You are here
├── .env.example                           ← Copy to .env and customize
├── setup.ps1                              ← Run this to create infrastructure
│
├── docs/
│   ├── lab3-passwordless-...md            ← Main lab (start here!)
│   ├── REFACTORING-NOTES.md               ← How we removed callback URLs
│   ├── troubleshooting.md                 ← Common problems & fixes
│   └── DEPLOYMENT-QUICK-REF.md            ← Quick reference for experts
│
├── infra/                                 ← Infrastructure as Code (Bicep)
│   ├── main.bicep                         ← Main template
│   ├── params/                            ← Configuration per region
│   └── modules/                           ← Reusable components
│
└── solution/                              ← .NET application code
    ├── CallerFunctionApp/                 ← Function App project
    ├── deploy.ps1                         ← Deploy code to Azure
    └── CallerFunctionApp.sln              ← Visual Studio solution
```

---

## 🔑 Key Concepts Explained Simply

### What is Managed Identity?

Normally, to call an API, you need credentials (username/password). But then:
- You must store them somewhere (risky!)
- You must rotate them (tedious!)
- They can be leaked or stolen (bad!)

**Managed Identity solves this:**
- Azure generates credentials automatically
- Azure stores them securely (you never see them)
- Azure rotates them automatically (you don't think about it)
- Your code just uses `DefaultAzureCredential` and it works

Think of it like an employee badge:
- The badge is issued automatically when you join
- The building validates it at each checkpoint
- It expires and gets renewed automatically
- You never have to manage it yourself

### What is a Bearer Token?

A bearer token is a temporary proof that says: *"I am Function App X, and Entra ID says so."*

It's like a concert ticket:
- Ticket issuer (Entra ID) signs the ticket
- Bouncer (Easy Auth) checks the signature and lets you in
- Ticket expires after the concert (token expires after 1 hour)
- Can't fake it because of the signature

Bearer tokens are passed in the `Authorization` header:
```
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

### What is Easy Auth?

Easy Auth is a security checkpoint built into Azure App Services:

```
Request arrives at Function App
    ↓
Easy Auth middleware intercepts it
    ↓
If no Authorization header → reject (403)
If Authorization header present:
    • Extract the token
    • Validate the signature (is it really from Entra ID?)
    • Check if it's expired
    • Check if caller is in allowedPrincipals (whitelist)
    ↓
If all checks pass → let request through
If any check fails → reject (401 or 403)
```

### What is Zero Trust?

The old way: "Trust everything on the network"
```
Companies had firewalls, then everything inside was trusted (bad!)
```

The new way: "Never trust, always verify"
```
Every request must prove its identity
Every user/app must authenticate
Every action is logged and monitored
```

---

## 🏗️ Architecture Diagram

```
┌──────────────────────────────────────────────────────────────┐
│  Your Azure Subscription                                     │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Virtual Network (10.0.0.0/16)                        │  │
│  │                                                         │  │
│  │  ┌──────────────────────────────────────────────────┐  │  │
│  │  │  Subnet 1: Apps (10.0.0.0/24)                   │  │  │
│  │  │                                                   │  │  │
│  │  │  ┌────────────────────────────────────────────┐  │  │  │
│  │  │  │  Function App (Caller)                      │  │  │  │
│  │  │  │  • .NET 8 application                       │  │  │  │
│  │  │  │  • System-assigned Managed Identity         │  │  │  │
│  │  │  │  • DefaultAzureCredential to get tokens     │  │  │  │
│  │  │  │  • Easy Auth (AllowAnonymous + validate     │  │  │  │
│  │  │  │    bearer token from client)                │  │  │  │
│  │  │  └────────────────────────────────────────────┘  │  │  │
│  │  │                    │                                │  │  │
│  │  │         POST /api/workflows/... with               │  │  │
│  │  │         Authorization: Bearer <token>              │  │  │
│  │  │                    │                                │  │  │
│  │  │                    ↓                                │  │  │
│  │  │  ┌────────────────────────────────────────────┐  │  │  │
│  │  │  │  Logic App Standard (Receiver)             │  │  │  │
│  │  │  │  • HTTP-triggered workflow                 │  │  │  │
│  │  │  │  • System-assigned Managed Identity        │  │  │  │
│  │  │  │  • Easy Auth validates bearer token        │  │  │  │
│  │  │  │  • Only Function App in allowedPrincipals  │  │  │  │
│  │  │  │  • Returns 200 OK with response            │  │  │  │
│  │  │  └────────────────────────────────────────────┘  │  │  │
│  │  └──────────────────────────────────────────────────┘  │  │
│  │                                                         │  │
│  │  ┌──────────────────────────────────────────────────┐  │  │
│  │  │  Supporting Services                            │  │  │
│  │  │  • Application Insights (monitoring)            │  │  │
│  │  │  • Storage Account (Function App state)        │  │  │
│  │  │  • Private Endpoints (network security)        │  │  │
│  │  └──────────────────────────────────────────────────┘  │  │
│  │                                                         │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Microsoft Entra ID (Token Authority)                 │  │
│  │  • Issues bearer tokens                               │  │
│  │  • Validates token signatures                         │  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

---

## 🧹 Cleanup (Delete Resources)

When you're done and want to avoid Azure charges:

```bash
# Delete the resource group (removes everything)
az group delete --name "rg-easyauth-lab-dev" --yes

# Verify it's deleted
az group list --query "[].name"
```

**Tip:** You can also pause/delete resources individually in the [Azure Portal](https://portal.azure.com).

---

## ❓ Troubleshooting Quick Links

**Problem: Setup script fails**
→ See [docs/troubleshooting.md](docs/troubleshooting.md#setup-script-fails)

**Problem: Can't sign in to Azure**
→ See [docs/troubleshooting.md](docs/troubleshooting.md#cant-sign-in-to-azure)

**Problem: Easy Auth returns 401 Unauthorized**
→ See [docs/troubleshooting.md](docs/troubleshooting.md#easy-auth-returns-401)

**Problem: Function App can't acquire token**
→ See [docs/troubleshooting.md](docs/troubleshooting.md#function-app-cant-acquire-token)

---

## 📚 Additional Resources

### Microsoft Documentation
- [Azure Managed Identities](https://learn.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/overview)
- [Easy Auth & Authorization](https://learn.microsoft.com/en-us/azure/app-service/overview-authentication-authorization)
- [Microsoft Entra ID](https://learn.microsoft.com/en-us/entra/fundamentals/whatis)
- [Bicep Language Reference](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/file)

### Security Resources
- [Zero Trust Security](https://www.microsoft.com/en-us/security/business/zero-trust)
- [Azure Security Benchmark](https://learn.microsoft.com/en-us/security/benchmark/azure/)
- [OWASP API Security](https://owasp.org/www-project-api-security/)

### Learning Resources
- [Azure Learn (free)](https://learn.microsoft.com/en-us/azure/)
- [AZ-900 Certification](https://learn.microsoft.com/en-us/credentials/certifications/azure-fundamentals/)
- [AZ-204 Certification](https://learn.microsoft.com/en-us/credentials/certifications/azure-developer/)

---

## 🤝 Contributing

Found a bug or have a suggestion?

1. **Check existing issues** on GitHub
2. **File a new issue** with:
   - What you expected
   - What actually happened
   - Your OS and tool versions
   - Relevant error messages

---

## 📝 License

This lab is provided as-is for educational purposes.

---

## 🎯 Next Steps

**Start here:** [START-HERE.md](START-HERE.md) — Quick navigation guide for all paths

### For Lab 3 (Bearer Token + Managed Identity)

1. ✅ **Open:** [START-HERE.md](START-HERE.md) → Path B
2. ✅ **Read:** Overview of what you're building
3. ✅ **Review:** Infrastructure summary ([docs/lab3-testing-evidence-summary.md](docs/lab3-testing-evidence-summary.md))
4. ✅ **Deploy:** Run `scripts/deploy.ps1` to create infrastructure
5. ✅ **Test:** Follow [labs/lab3-bearer-token/docs/lab3-testing-and-verification.md](labs/lab3-bearer-token/docs/lab3-testing-and-verification.md) (complete step-by-step guide with C# code)
6. ✅ **Verify:** Check Application Insights logs for success
7. ✅ **Implement:** Use patterns in your own projects

---

**Ready to start?** Open [START-HERE.md](START-HERE.md) and choose your path! 🚀
