function Get-ODPromptResult {
    <#
    .SYNOPSIS
        Decides what to log and whether to launch the client after a prompt closes.
    .DESCRIPTION
        Pure: the caller shows the prompt, re-checks the account, passes the answers in, and
        carries out the result. The user may have signed in through OneDrive's own window while
        the prompt was open, so the re-check comes first: a Reauth prompt is acted on only while
        the state is still NeedsReauth or NotSignedIn, and a FirstLogin prompt only while no
        account is configured. Otherwise it logs 1014 and launches nothing.

        Returns an object with:
          Events  Events to log, each with Event (the event table name) and Data (extra fields).
          Launch  'Start', 'Restart' or 'None'. Only a Reauth SignIn restarts.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        # What the user did with the dialog
        [Parameter(Mandatory)]
        [ValidateSet('SignIn', 'Later', 'TimedOut', 'Dismissed')]
        [string] $Action,

        # Which prompt was shown
        [Parameter(Mandatory)]
        [ValidateSet('FirstLogin', 'Reauth')]
        [string] $Kind,

        # Re-check result for a FirstLogin prompt: whether an account is now configured
        [bool] $AccountConfigured = $false,

        # Re-check result for a Reauth prompt: the health state now
        [ValidateSet('Healthy', 'NeedsReauth', 'NotSignedIn', 'Degraded', 'Unknown')]
        [string] $HealthState = 'NeedsReauth'
    )

    $stillNeedsAction = if ($Kind -eq 'FirstLogin') {
        -not $AccountConfigured
    }
    else {
        $HealthState -in 'NeedsReauth', 'NotSignedIn'
    }

    if (-not $stillNeedsAction) {
        $data = @{ action = $Action }
        if ($Kind -eq 'Reauth') { $data['syncState'] = $HealthState }
        return [pscustomobject]@{
            Events = @(@{ Event = "${Kind}SignedInElsewhere"; Data = $data })
            Launch = 'None'
        }
    }

    switch ($Action) {
        'SignIn' {
            $event = @{ Event = "${Kind}Acted"; Data = @{} }
            $launch = if ($Kind -eq 'Reauth') { 'Restart' } else { 'Start' }
        }
        'Later' {
            $event = @{ Event = "${Kind}Deferred"; Data = @{} }
            $launch = 'None'
        }
        default {
            $event = @{ Event = "${Kind}$Action"; Data = @{} }
            $launch = 'None'
        }
    }

    [pscustomobject]@{ Events = @($event); Launch = $launch }
}
