<#
.SYNOPSIS
    Points lab users to the current safe Easy Auth tests.

.DESCRIPTION
    The previous script contained environment-specific identifiers and printed
    part of an access token. Use one of the canonical scripts instead:

    - From a lab PC, run scripts/demo-easyauth.ps1 to test the Function caller.
    - Without Function code, follow docs/lab3-direct-pc-testing.md.
    - Inside managed-identity-enabled App Service, use
      scripts/call-logicapp-with-managed-identity.ps1.
#>

throw 'This historical test was retired. Use scripts/demo-easyauth.ps1 or docs/lab3-direct-pc-testing.md.'
