function Resolve-ODAccountEmail {
    <#
    .SYNOPSIS
        Returns the address to show the user: registry email, then AD mail, AD UPN, then the logon name.
    .DESCRIPTION
        The AD lookup runs only when the registry has no email. Logs event 1012 when the lookup fails
        or finds nothing and the logon name is used.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # Email from the registry (Get-ODAccount); empty means look it up
        [string] $RegistryEmail = '',

        # Logger from New-ODNagLogger
        [Parameter(Mandatory)]
        [pscustomobject] $Logger,

        # Seconds before the AD lookup gives up
        [int] $TimeoutSeconds = 10
    )

    if (-not [string]::IsNullOrWhiteSpace($RegistryEmail)) { return $RegistryEmail }

    $email = $null
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
    $email
}
