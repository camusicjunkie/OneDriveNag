function Get-ODUserEmail {
    <#
    .SYNOPSIS
        Returns the user's address: the configured OneDrive account first, then AD (mail, UPN), then sAMAccountName.
    .DESCRIPTION
        Logs event 1012 when the AD lookup fails and the logon name is used instead.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # Registry key for the OneDrive Business sync account
        [Parameter(Mandatory)]
        [string] $AccountKeyPath,

        # Application log source for telemetry events
        [Parameter(Mandatory)]
        [string] $LogSource,

        # Flat file used only when the event source is not registered
        [Parameter(Mandatory)]
        [string] $FallbackLogPath,

        # Seconds before the AD lookup gives up (protects off-network laptops)
        [int] $TimeoutSeconds = 10
    )

    # The account OneDrive already knows is the most accurate address for a re-auth prompt
    $accountEmail = (Get-ItemProperty -Path $AccountKeyPath -ErrorAction SilentlyContinue).UserEmail
    if (-not [string]::IsNullOrWhiteSpace($accountEmail)) { return $accountEmail }

    try {
        $searcher = [ADSISearcher]"(&(objectCategory=user)(sAMAccountName=$env:USERNAME))"
        $searcher.ClientTimeout   = [timespan]::FromSeconds($TimeoutSeconds)
        $searcher.ServerTimeLimit = [timespan]::FromSeconds($TimeoutSeconds)
        $null = $searcher.PropertiesToLoad.AddRange([string[]]@('mail', 'userPrincipalName'))
        $result = $searcher.FindOne()

        if ($null -ne $result) {
            if ($result.Properties['mail'].Count -gt 0) {
                return [string]$result.Properties['mail'][0]
            }
            if ($result.Properties['userprincipalname'].Count -gt 0) {
                return [string]$result.Properties['userprincipalname'][0]
            }
        }
    }
    catch {
        # AD unreachable (off-network or timed out); fall back to the logon name
        Write-ODNagEvent -EventId 1012 -Stage 'EmailLookupFailed' -EntryType 'Warning' `
            -LogSource $LogSource -FallbackLogPath $FallbackLogPath `
            -Data @{ error = $_.Exception.Message; fallback = $env:USERNAME }
    }

    return $env:USERNAME
}
