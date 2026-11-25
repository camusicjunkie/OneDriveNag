function Get-ODAccount {
    <#
    .SYNOPSIS
        Reads the OneDrive Business account from the registry and returns Configured, Email and TenantMatch.
    .DESCRIPTION
        A tenant mismatch makes the account not configured, but the registry email is still returned.
        Email is the registry value only, or $null when there is none. This function never logs and
        never queries AD; Resolve-ODAccountEmail turns the registry email into the address to show.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        # Registry key for the OneDrive Business sync account
        [Parameter(Mandatory)]
        [string] $AccountKeyPath,

        # Optional Entra tenant GUID to require an exact match; empty skips the check
        [string] $ExpectedTenantId = ''
    )

    $account = Get-ItemProperty -Path $AccountKeyPath -ErrorAction SilentlyContinue
    $hasEmail = -not [string]::IsNullOrWhiteSpace($account.UserEmail)

    $tenantMatch = [string]::IsNullOrWhiteSpace($ExpectedTenantId) -or
        $account.ConfiguredTenantId -eq $ExpectedTenantId

    [pscustomobject]@{
        Configured  = ($hasEmail -and $tenantMatch)
        Email       = if ($hasEmail) { [string]$account.UserEmail } else { $null }
        TenantMatch = [bool]$tenantMatch
    }
}
