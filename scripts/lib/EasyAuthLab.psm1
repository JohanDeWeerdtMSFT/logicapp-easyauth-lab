<#
.SYNOPSIS
    Shared helpers for the Logic App Easy Auth lab scripts.

.DESCRIPTION
    Contains the pure, testable logic used by scripts/deploy.ps1 and
    scripts/validate.ps1:

    - Test-StorageAuthorizationPolicy evaluates the *effective* storage account
      settings after deployment, so an inherited Azure Policy Modify effect that
      silently overrides the requested WS1-compatible configuration is detected
      instead of being reported as success.
    - Wait-RuntimeHttpStatus waits for an actual HTTP outcome instead of trusting
      ARM configuration state, because App Service Authentication runtime
      enforcement lags behind the authsettingsV2 resource.

    No function in this module prints or returns Function keys, bearer tokens,
    storage keys, or connection strings.
#>

function Test-StorageAuthorizationPolicy {
    <#
    .SYNOPSIS
        Evaluates the effective storage account authorization settings.

    .PARAMETER StorageAccountName
        Name of the storage account, used only for messages.

    .PARAMETER PublicNetworkAccess
        Effective publicNetworkAccess value read back from Azure.

    .PARAMETER AllowSharedKeyAccess
        Effective allowSharedKeyAccess value read back from Azure. Azure returns
        $null when the property was never set, which means Shared Key access is
        allowed.

    .OUTPUTS
        PSCustomObject with compliance flags and an actionable message.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$StorageAccountName,

        [string]$PublicNetworkAccess,

        [object]$AllowSharedKeyAccess
    )

    $publicAccessCompliant = ($PublicNetworkAccess -eq 'Disabled')

    # A null value means the property is unset, which leaves Shared Key access enabled.
    $sharedKeyConflict = ($null -ne $AllowSharedKeyAccess) -and (-not [bool]$AllowSharedKeyAccess)

    $messages = [System.Collections.Generic.List[string]]::new()

    if (-not $publicAccessCompliant) {
        $messages.Add(
            "Storage account '$StorageAccountName' reports publicNetworkAccess '$PublicNetworkAccess' but the classroom path requires 'Disabled'. Do not enable public storage access; re-run the deployment and investigate any policy or manual change that re-enabled it.")
    }

    if ($sharedKeyConflict) {
        $messages.Add(@"
Storage account '$StorageAccountName' reports allowSharedKeyAccess = false, but the template requests true.
An inherited Azure Policy Modify assignment (for example 'StorageAccount_DisableLocalAuth_Modify', display name
'SFI-ID4.2.1 Storage Accounts - Safe Secrets Standard', assignment 'MCAPSGovDeployPolicies') overrides the requested value.
Logic App Standard on a Workflow Service Plan (WS1) cannot run with storage account key access disabled, so the Logic App
host will fail to start or lose run history.
Remedies (all require governance-owner approval; this script never creates policy exemptions automatically):
  1. Request a time-limited, resource-scoped Azure Policy exemption for this storage account.
  2. Deploy the lab into a subscription or management group without the DisableLocalAuth Modify assignment.
  3. Host the Logic App on App Service Environment v3, which is the documented option that supports disabling key access.
Reference: https://learn.microsoft.com/azure/logic-apps/create-single-tenant-workflows-azure-portal#set-up-managed-identity-access-to-your-storage-account
"@)
    }

    return [pscustomobject]@{
        storageAccountName    = $StorageAccountName
        publicAccessCompliant = $publicAccessCompliant
        sharedKeyConflict     = $sharedKeyConflict
        compliant             = ($publicAccessCompliant -and -not $sharedKeyConflict)
        message               = ($messages -join "`n`n")
    }
}

function Wait-RuntimeHttpStatus {
    <#
    .SYNOPSIS
        Waits until a probe reports the expected HTTP status code.

    .DESCRIPTION
        ARM returning a new authsettingsV2 policy does not mean the App Service
        Authentication runtime is enforcing it yet. This helper polls the actual
        request path and, when bounded retries are not enough, invokes the
        supplied minimal refresh action once before continuing to retry.

    .PARAMETER Probe
        Script block returning the observed HTTP status code as an integer.

    .PARAMETER ExpectedStatus
        HTTP status code that indicates runtime enforcement has taken effect.

    .PARAMETER RefreshAction
        Optional script block performing the smallest safe refresh (for example
        an App Service restart). Invoked at most once.

    .PARAMETER RefreshAfterAttempts
        Attempt number from which RefreshAction is invoked.

    .OUTPUTS
        PSCustomObject with succeeded, attempts, lastStatus, and refreshInvoked.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Probe,

        [Parameter(Mandatory)]
        [int]$ExpectedStatus,

        [scriptblock]$RefreshAction,

        [int]$MaximumAttempts = 12,

        [int]$DelaySeconds = 10,

        [int]$RefreshAfterAttempts = 6,

        [scriptblock]$Sleep = { param($seconds) Start-Sleep -Seconds $seconds }
    )

    $lastStatus = $null
    $refreshInvoked = $false

    for ($attempt = 1; $attempt -le $MaximumAttempts; $attempt++) {
        try {
            $lastStatus = [int](& $Probe)
        }
        catch {
            # A transient request error is treated as "not yet enforcing" so the
            # caller's restoration path still runs.
            $lastStatus = -1
        }

        if ($lastStatus -eq $ExpectedStatus) {
            return [pscustomobject]@{
                succeeded      = $true
                attempts       = $attempt
                lastStatus     = $lastStatus
                refreshInvoked = $refreshInvoked
            }
        }

        if ($attempt -eq $MaximumAttempts) {
            break
        }

        if (-not $refreshInvoked -and $RefreshAction -and $attempt -ge $RefreshAfterAttempts) {
            & $RefreshAction
            $refreshInvoked = $true
        }

        & $Sleep $DelaySeconds
    }

    return [pscustomobject]@{
        succeeded      = $false
        attempts       = $MaximumAttempts
        lastStatus     = $lastStatus
        refreshInvoked = $refreshInvoked
    }
}

Export-ModuleMember -Function Test-StorageAuthorizationPolicy, Wait-RuntimeHttpStatus
