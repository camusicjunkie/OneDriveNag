function Get-ODNagDecision {
    <#
    .SYNOPSIS
        Decides what one run logs, which prompt it shows, and what happens to the health marker.
    .DESCRIPTION
        Pure: it reads nothing and writes nothing. The caller gathers the facts, passes them in,
        and carries out the result. Health state matters only when the account is configured and
        the client is running.

        Returns an object with:
          Events  Zero or more event names to log, from the event table.
          Prompt  'FirstLogin', 'Reauth', or $null for no prompt.
          Marker  'Set', 'Clear' or 'Keep'.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        # Whether a OneDrive Business account is configured
        [Parameter(Mandatory)]
        [bool] $AccountConfigured,

        # Whether OneDrive.exe is running in this session
        [Parameter(Mandatory)]
        [bool] $ClientRunning,

        # The classified health state
        [Parameter(Mandatory)]
        [ValidateSet('Healthy', 'NeedsReauth', 'NotSignedIn', 'Degraded', 'Unknown')]
        [string] $HealthState,

        # Whether the healthy marker file exists
        [Parameter(Mandatory)]
        [bool] $MarkerPresent
    )

    $events = @()
    $prompt = $null
    $marker = 'Keep'

    if (-not $AccountConfigured) {
        $prompt = 'FirstLogin'
    }
    elseif (-not $ClientRunning) {
        $events = @('StatusUnknown')
    }
    else {
        switch ($HealthState) {
            'Healthy' {
                if (-not $MarkerPresent) {
                    $events = @('Healthy')
                    $marker = 'Set'
                }
            }
            { $_ -in 'NeedsReauth', 'NotSignedIn' } {
                $prompt = 'Reauth'
                $marker = 'Clear'
            }
            'Degraded' {
                $events = @('Degraded')
                $marker = 'Clear'
            }
            default {
                $events = @('StatusUnknown')
            }
        }
    }

    [pscustomobject]@{ Events = $events; Prompt = $prompt; Marker = $marker }
}
