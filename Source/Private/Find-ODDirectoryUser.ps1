function Find-ODDirectoryUser {
    <#
    .SYNOPSIS
        Runs one LDAP user search and returns the Mail and UserPrincipalName, or $null when nothing matches.
    #>
    [CmdletBinding()]
    param(
        # Complete LDAP filter, already escaped
        [Parameter(Mandatory)]
        [string] $Filter,

        # Seconds before the search gives up (protects off-network laptops)
        [int] $TimeoutSeconds = 10
    )

    $searcher = [ADSISearcher]$Filter
    $searcher.ClientTimeout   = [timespan]::FromSeconds($TimeoutSeconds)
    $searcher.ServerTimeLimit = [timespan]::FromSeconds($TimeoutSeconds)
    $null = $searcher.PropertiesToLoad.AddRange([string[]]@('mail', 'userPrincipalName'))
    $result = $searcher.FindOne()
    if ($null -eq $result) { return $null }

    [pscustomobject]@{
        Mail              = if ($result.Properties['mail'].Count -gt 0) { [string]$result.Properties['mail'][0] }
        UserPrincipalName = if ($result.Properties['userprincipalname'].Count -gt 0) { [string]$result.Properties['userprincipalname'][0] }
    }
}
