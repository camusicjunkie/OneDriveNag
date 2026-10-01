function Test-ODAccountConfigured {
    <#
    .SYNOPSIS
        Returns $true when a OneDrive Business account is configured for the user.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        # Registry key for the OneDrive Business sync account
        [Parameter(Mandatory)]
        [string] $AccountKeyPath,

        # Optional Entra tenant GUID to require an exact match; empty skips the check
        [string] $ExpectedTenantId = ''
    )

    $account = Get-ItemProperty -Path $AccountKeyPath -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($account.UserEmail)) { return $false }

    if (-not [string]::IsNullOrWhiteSpace($ExpectedTenantId) -and
        $account.ConfiguredTenantId -ne $ExpectedTenantId) {
        return $false
    }

    return $true
}
