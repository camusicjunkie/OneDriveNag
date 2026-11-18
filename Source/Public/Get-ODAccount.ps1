function Get-ODAccount {
    <#
    .SYNOPSIS
        Reads the OneDrive Business account once and returns Configured, Email and TenantMatch.
    .DESCRIPTION
        A tenant mismatch makes the account not configured, but the registry email is still returned.
        With no registry email the address comes from AD (mail, then UPN), then the logon name.
        Logs event 1012 when the AD lookup fails or finds nothing and the logon name is used.
        -SkipDirectoryLookup goes straight to the logon name with no lookup and no event, so a re-check
        in the same run does not log 1012 twice.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        # Registry key for the OneDrive Business sync account
        [Parameter(Mandatory)]
        [string] $AccountKeyPath,

        # Logger from New-ODNagLogger
        [Parameter(Mandatory)]
        [pscustomobject] $Logger,

        # Optional Entra tenant GUID to require an exact match; empty skips the check
        [string] $ExpectedTenantId = '',

        # Seconds before the AD lookup gives up
        [int] $TimeoutSeconds = 10,

        # Skip the AD lookup and its 1012 event; for re-checks that only need Configured
        [switch] $SkipDirectoryLookup
    )

    $account = Get-ItemProperty -Path $AccountKeyPath -ErrorAction SilentlyContinue
    $hasEmail = -not [string]::IsNullOrWhiteSpace($account.UserEmail)

    $tenantMatch = [string]::IsNullOrWhiteSpace($ExpectedTenantId) -or
        $account.ConfiguredTenantId -eq $ExpectedTenantId

    $email = $null
    if ($hasEmail) { $email = [string]$account.UserEmail }
    elseif ($SkipDirectoryLookup) { $email = $env:USERNAME }
    else {
        try {
            $escaped = $env:USERNAME.Replace('\', '\5c').Replace('*', '\2a').Replace('(', '\28').Replace(')', '\29').Replace([string][char]0, '\00')
            $user = Find-ODDirectoryUser -Filter "(&(objectCategory=user)(sAMAccountName=$escaped))" -TimeoutSeconds $TimeoutSeconds
            if ($null -ne $user) {
                if (-not [string]::IsNullOrWhiteSpace($user.Mail)) { $email = $user.Mail }
                elseif (-not [string]::IsNullOrWhiteSpace($user.UserPrincipalName)) { $email = $user.UserPrincipalName }
            }
            $failure = if ($null -eq $email) { 'no directory entry found' }
        }
        catch { $failure = $_.Exception.Message }

        if ($null -eq $email) {
            Write-ODNagEvent -Logger $Logger -Event 'EmailLookupFailed' `
                -Data @{ error = $failure; fallback = $env:USERNAME }
            $email = $env:USERNAME
        }
    }

    [pscustomobject]@{
        Configured  = ($hasEmail -and $tenantMatch)
        Email       = $email
        TenantMatch = [bool]$tenantMatch
    }
}
