#Requires -Modules Pester

<#
    Focused tests for the Lab 3 deployment and runtime-wait helpers.

    Run with:
        Invoke-Pester ./labs/lab3-bearer-token/tests
#>

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' '..' '..' 'scripts' 'lib' 'EasyAuthLab.psm1'
    Import-Module $modulePath -Force
}

Describe 'Test-StorageAuthorizationPolicy' {
    It 'passes when private ingress and Shared Key access are both in place' {
        $result = Test-StorageAuthorizationPolicy -StorageAccountName 'sa1' `
            -PublicNetworkAccess 'Disabled' -AllowSharedKeyAccess $true
        $result.compliant | Should -BeTrue
        $result.sharedKeyConflict | Should -BeFalse
    }

    It 'treats an unset allowSharedKeyAccess value as allowed' {
        $result = Test-StorageAuthorizationPolicy -StorageAccountName 'sa1' `
            -PublicNetworkAccess 'Disabled' -AllowSharedKeyAccess $null
        $result.compliant | Should -BeTrue
    }

    It 'detects the WS1 Shared Key policy conflict with actionable guidance' {
        $result = Test-StorageAuthorizationPolicy -StorageAccountName 'sa1' `
            -PublicNetworkAccess 'Disabled' -AllowSharedKeyAccess $false
        $result.sharedKeyConflict | Should -BeTrue
        $result.compliant | Should -BeFalse
        $result.message | Should -Match 'StorageAccount_DisableLocalAuth_Modify'
        $result.message | Should -Match 'exemption'
        $result.message | Should -Match 'App Service Environment v3'
    }

    It 'fails when public network access is not disabled' {
        $result = Test-StorageAuthorizationPolicy -StorageAccountName 'sa1' `
            -PublicNetworkAccess 'Enabled' -AllowSharedKeyAccess $true
        $result.publicAccessCompliant | Should -BeFalse
        $result.compliant | Should -BeFalse
        $result.message | Should -Match 'Do not enable public storage access'
    }
}

Describe 'Wait-RuntimeHttpStatus' {
    It 'succeeds as soon as the runtime returns the expected status' {
        $result = Wait-RuntimeHttpStatus -Probe { 403 } -ExpectedStatus 403 -Sleep { }
        $result.succeeded | Should -BeTrue
        $result.attempts | Should -Be 1
        $result.refreshInvoked | Should -BeFalse
    }

    It 'keeps retrying while ARM state has propagated but the runtime has not' {
        $script:calls = 0
        $result = Wait-RuntimeHttpStatus -Probe {
            $script:calls++
            if ($script:calls -lt 3) { 200 } else { 403 }
        } -ExpectedStatus 403 -Sleep { }
        $result.succeeded | Should -BeTrue
        $result.attempts | Should -Be 3
    }

    It 'invokes the refresh action once when retries alone are not enough' {
        $script:refreshCount = 0
        $result = Wait-RuntimeHttpStatus -Probe {
            if ($script:refreshCount -eq 0) { 200 } else { 403 }
        } -ExpectedStatus 403 -RefreshAfterAttempts 2 -RefreshAction {
            $script:refreshCount++
        } -Sleep { }
        $result.succeeded | Should -BeTrue
        $result.refreshInvoked | Should -BeTrue
        $script:refreshCount | Should -Be 1
    }

    It 'reports a timeout with the observed status instead of throwing' {
        $result = Wait-RuntimeHttpStatus -Probe { 200 } -ExpectedStatus 403 `
            -MaximumAttempts 3 -Sleep { }
        $result.succeeded | Should -BeFalse
        $result.attempts | Should -Be 3
        $result.lastStatus | Should -Be 200
    }

    It 'does not throw when the probe itself fails, so restoration can still run' {
        { Wait-RuntimeHttpStatus -Probe { throw 'network error' } -ExpectedStatus 403 `
                -MaximumAttempts 2 -Sleep { } } | Should -Not -Throw
    }
}

Describe 'validate.ps1 B6 restoration safety' {
    BeforeAll {
        $script:validateScript = Get-Content (Join-Path $PSScriptRoot '..' '..' '..' 'scripts' 'validate.ps1') -Raw
    }

    It 'removes temporary payload files in a finally block' {
        $script:validateScript | Should -Match 'Remove-Item \$originalPayloadPath, \$mutationPayloadPath'
    }

    It 'clears in-memory key and token variables' {
        $script:validateScript | Should -Match 'Remove-Variable functionKey, functionHeaders'
        $script:validateScript | Should -Match 'Remove-Variable wrongAudienceToken'
    }

    It 'verifies the restored principal through an HTTP 200 probe' {
        $script:validateScript | Should -Match 'B6-restored'
    }
}
