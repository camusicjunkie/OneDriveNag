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
          Events  Events to log, each with EventId, Stage, EntryType and Data (extra fields).
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

    $ids = if ($Kind -eq 'FirstLogin') {
        @{ SignIn = 1001; Later = 1002; Other = 1004 }
    }
    else {
        @{ SignIn = 1006; Later = 1007; Other = 1008 }
    }

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
            Events = @(@{ EventId = 1014; Stage = "${Kind}SignedInElsewhere"; EntryType = 'Information'; Data = $data })
            Launch = 'None'
        }
    }

    switch ($Action) {
        'SignIn' {
            $event = @{ EventId = $ids.SignIn; Stage = "${Kind}Acted"; EntryType = 'Information'; Data = @{} }
            $launch = if ($Kind -eq 'Reauth') { 'Restart' } else { 'Start' }
        }
        'Later' {
            $event = @{ EventId = $ids.Later; Stage = "${Kind}Deferred"; EntryType = 'Warning'; Data = @{} }
            $launch = 'None'
        }
        default {
            $event = @{ EventId = $ids.Other; Stage = "${Kind}$Action"; EntryType = 'Warning'; Data = @{} }
            $launch = 'None'
        }
    }

    [pscustomobject]@{ Events = @($event); Launch = $launch }
}
