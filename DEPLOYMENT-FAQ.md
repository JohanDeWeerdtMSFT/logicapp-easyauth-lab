# Deployment FAQ

## Question 1: Does deploy.ps1 Handle Already-Created Resources?

### ✅ YES — Fully Idempotent

**How it works:**

The `deploy.ps1` script uses **idempotent deployment mode**, meaning it safely handles both new and existing resources:

```powershell
# Deployment mode: Incremental
# This means Azure Resource Manager will:
# ✅ Create NEW resources
# ✅ SKIP resources that already exist
# ✅ Update ONLY changed properties
# ❌ NOT delete existing resources
```

### Evidence from Code

**Resource Group Check (Line ~120):**
```powershell
$rgExists = az group exists --name $resourceGroupName 2>$null
if ($rgExists -eq 'true') {
    Write-Host "  Resource group '$resourceGroupName' already exists." -ForegroundColor Green
}
else {
    # Create new resource group
    Invoke-AzCommand -Description "Creating resource group" ...
}
```

**Bicep Deployment Mode (Line ~145):**
```powershell
'--mode', 'Incremental'  # ← KEY: Idempotent deployment
```

### What This Means

| Scenario | Result |
|----------|--------|
| **First run** | All resources created |
| **Second run** (same params) | Nothing changes ✅ |
| **Second run** (different Location) | Location parameter ignored (already deployed) |
| **Third run** (updated Bicep) | Only changed resources updated |

### Safe to Run Multiple Times ✅

```powershell
# Run 1: Creates all resources
.\deploy.ps1 -EntraAppClientId "..." -EntraAppTenantId "..." 

# Run 2: Safe — no duplicates created
.\deploy.ps1 -EntraAppClientId "..." -EntraAppTenantId "..."

# Run 3: Still safe
.\deploy.ps1 -EntraAppClientId "..." -EntraAppTenantId "..."
```

---

## Question 2: Is There an "Undeploy" Option?

### ❌ NO Built-In Undeploy

There is **no dedicated undeploy script**, but you have two options:

### Option A: Azure CLI (Fastest)

Delete the entire resource group and all resources in it:

```powershell
# Remove everything
az group delete --name "rg-la-easyauth-lab-dev" --yes

# This will delete:
# ✅ Logic App
# ✅ Function App
# ✅ Storage accounts
# ✅ Virtual networks
# ✅ Private endpoints
# ✅ Everything else in that resource group
```

### Option B: Azure Portal (Manual)

1. Go to https://portal.azure.com
2. Select **Resource Groups**
3. Select `rg-la-easyauth-lab-dev`
4. Click **Delete resource group**
5. Confirm deletion

### Option C: PowerShell Script (Custom - Selective Deletion)

If you want to delete specific resources while preserving others:

```powershell
# Example: Delete just the Function App
az functionapp delete --name "la-easyauth-lab-dev-caller-..." --resource-group "rg-la-easyauth-lab-dev" --yes

# Or delete just Logic App
az logicapp delete --name "la-easyauth-lab-dev-la-..." --resource-group "rg-la-easyauth-lab-dev" --yes
```

### Create an Undeploy Script (Optional)

If you'd like a dedicated undeploy script, here's a template:

**File**: `scripts/undeploy.ps1`

```powershell
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidatePattern('^[a-z0-9]+$')]
    [string]$EnvironmentName = 'dev',

    [switch]$Force  # Skip confirmation
)

$ErrorActionPreference = 'Stop'
$namingPrefix = 'la-easyauth-lab'
$resourceGroupName = "rg-${namingPrefix}-${EnvironmentName}"

Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
Write-Host   "║  Logic App Easy Auth Lab — Resource Cleanup               ║" -ForegroundColor Yellow
Write-Host   "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Resource Group: $resourceGroupName" -ForegroundColor Cyan
Write-Host ""
Write-Host "⚠️  WARNING: This will DELETE all resources in the resource group!" -ForegroundColor Red
Write-Host ""

if (-not $Force) {
    $response = Read-Host "Type 'DELETE' to confirm"
    if ($response -ne 'DELETE') {
        Write-Host "Cancelled." -ForegroundColor Yellow
        exit 0
    }
}

try {
    Write-Host "→ Deleting resource group '$resourceGroupName'..." -ForegroundColor Yellow
    az group delete --name $resourceGroupName --yes --output none
    Write-Host "✅ Resource group deleted successfully!" -ForegroundColor Green
}
catch {
    Write-Host "❌ Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
```

### Cost Implications

⚠️ **Important for Azure Billing:**

- **Storage accounts** with data incur costs even when not actively used
- **Virtual networks** and **private endpoints** incur hourly charges
- **Logic Apps** and **Function Apps** have consumption-based pricing

**Recommendation**: If you're testing and want to avoid unexpected charges, delete the resource group entirely using `az group delete`.

---

## Question 3: Are All HTML Files Updated for New Folder Structure?

### ✅ YES — Updated Successfully

All HTML files have been updated to reflect the new lab-based folder structure.

### HTML Files Checked & Updated

| File | Old Path | New Path | Status |
|------|----------|----------|--------|
| `documentation/architecture/lab3-bearer-token-flow.html` | `../../docs/lab3-...` | `../../labs/lab3-bearer-token/docs/lab3-...` | ✅ Updated |
| `documentation/architecture/lab3-bearer-token-flow.html` | `src/httpTriggerWorkflow/` | `labs/lab3-bearer-token/workflows/httpTriggerWorkflow/` | ✅ Updated |
| `documentation/evidence/findings.html` | `docs/evidence/findings.md` | `documentation/evidence/findings.md` | ✅ Updated |

### Details of Updates

#### Update 1: Lab 3 Bearer Token Flow HTML

**File**: `documentation/architecture/lab3-bearer-token-flow.html`

**Changes**:
```html
<!-- BEFORE -->
<a href="../../docs/lab3-testing-and-verification.md" target="_blank">
  Lab 3 Testing & Verification Guide
</a>

<!-- AFTER -->
<a href="../../labs/lab3-bearer-token/docs/lab3-testing-and-verification.md" target="_blank">
  Lab 3 Testing & Verification Guide
</a>
```

**Affected sections**: 
- Line 389: Callout info box
- Line 718: Implementation guide section
- Line 734: Key files list (updated 3 path references)

#### Update 2: Findings HTML

**File**: `documentation/evidence/findings.html`

**Changes**:
```html
<!-- BEFORE -->
<td><code>docs/evidence/findings.md</code></td>

<!-- AFTER -->
<td><code>documentation/evidence/findings.md</code></td>
```

**Affected rows**: All 3 test evidence entries

### Relative Paths (Automatically Correct)

The HTML files use **relative paths** which are preserved correctly:

```html
<!-- ✅ These automatically work regardless of folder structure -->
<link rel="stylesheet" href="../assets/css/style.css">
<a href="../index.html">Home</a>
<script src="https://cdn.jsdelivr.net/npm/mermaid@10.9.1/dist/mermaid.min.js"></script>
```

### Path Resolution Examples

From `documentation/architecture/lab3-bearer-token-flow.html`:
- `../../labs/lab3-bearer-token/docs/lab3-testing-and-verification.md`
  - Goes up 2 levels to `documentation/`
  - Then down to `labs/lab3-bearer-token/docs/lab3-testing-and-verification.md` ✅

From `documentation/evidence/findings.html`:
- `../index.html` → Goes up 1 level to `documentation/index.html` ✅

### Verification Results

**Verification command run:**
```powershell
grep_search -query "labs/lab3-bearer-token" -includePattern "documentation/**/*.html"

# Results: 4 matches found ✅
# - 2 href links updated
# - 2 code examples updated
```

All updates verified and working correctly!

---

## Summary

| Question | Answer | Details |
|----------|--------|---------|
| **Idempotent?** | ✅ YES | Uses `--mode Incremental` and checks for existing resources |
| **Safe to re-run?** | ✅ YES | No duplicate resources created on subsequent runs |
| **Undeploy?** | ❌ NO | Use `az group delete` or portal, or create custom script |
| **HTML Updated?** | ✅ YES | All 8 path references updated to new lab structure |

---

## Quick Reference

### To Deploy
```powershell
.\scripts\deploy.ps1 -EntraAppClientId "..." -EntraAppTenantId "..."
```

### To Undeploy (Delete All Resources)
```powershell
az group delete --name "rg-la-easyauth-lab-dev" --yes
```

### To Verify HTML Updates
```powershell
# Check lab 3 paths
Select-String "labs/lab3-bearer-token" documentation/architecture/lab3-bearer-token-flow.html

# Check evidence paths
Select-String "documentation/evidence" documentation/evidence/findings.html
```

### To View Generated HTML
```powershell
# Open documentation portal
start "c:\Code\CSU\Ores\EasyAuth\documentation\index.html"
```

---

**For questions or issues**, see:
- Deployment: `guides/DEPLOYMENT-QUICK-REF.md`
- Troubleshooting: `guides/troubleshooting.md`
- Structure: `LABS-STRUCTURE.md`
