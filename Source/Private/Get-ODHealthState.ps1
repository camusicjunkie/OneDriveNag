function Get-ODHealthState {
    <#
    .SYNOPSIS
        Runs ODSyncUtil and classifies the account as Healthy, NeedsReauth, NotSignedIn, Degraded, or Unknown.
    .DESCRIPTION
        Matches the patterns against each sync root's CurrentStateString and Label only, so a
        service name can't trigger a state. The worst root wins: NeedsReauth, Degraded,
        Unknown, then Healthy. A non-zero exit is Unknown; exit 0 with no roots is NotSignedIn.
        Detail carries service name, numeric CurrentState and the text fields per root into
        telemetry so you can confirm in Splunk which values your OneDrive build emits.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        # Full path to ODSyncUtil.exe
        [Parameter(Mandatory)]
        [string] $ExePath,

        # Regex for state/label text that means the sign-in has expired or is missing
        [string] $AuthPattern = 'signed.?out|sign.?in (required|needed)|auth|credential',

        # Regex for state/label text that means the client isn't running or reports an unrecognised state
        [string] $UnknownPattern = 'Unknown \(\d+\)|Start OneDrive',

        # Regex for problems worth logging that a sign-in would not fix (no prompt)
        [string] $DegradedPattern = 'error|paused|blocked|full'
    )

    $run = Invoke-ODSyncUtil -ExePath $ExePath

    if ($run.ExitCode -ne 0) {
        return [pscustomobject]@{ State = 'Unknown'; Detail = "ODSyncUtil exit code $($run.ExitCode)" }
    }

    $roots = @()
    if (-not [string]::IsNullOrWhiteSpace($run.Output)) {
        try {
            # Parentheses make 5.1 enumerate a JSON array instead of returning it as one object
            $roots = @(($run.Output | ConvertFrom-Json))
        }
        catch {
            return [pscustomobject]@{ State = 'Unknown'; Detail = "Unparseable ODSyncUtil output: $($_.Exception.Message)" }
        }
    }

    if ($roots.Count -eq 0) {
        return [pscustomobject]@{ State = 'NotSignedIn'; Detail = 'No sync roots reported' }
    }

    $rank = @{ Healthy = 0; Unknown = 1; Degraded = 2; NeedsReauth = 3 }
    $state = 'Healthy'
    $parts = foreach ($root in $roots) {
        $text = "$($root.CurrentStateString) $($root.Label)"
        $rootState = if ($text -match $AuthPattern) { 'NeedsReauth' }
        elseif ($text -match $DegradedPattern) { 'Degraded' }
        elseif ($text -match $UnknownPattern) { 'Unknown' }
        else { 'Healthy' }
        if ($rank[$rootState] -gt $rank[$state]) { $state = $rootState }

        '{0} [{1}] {2} | {3}' -f $root.ServiceName, $root.CurrentState, $root.CurrentStateString, $root.Label
    }

    $detail = $parts -join '; '
    if ($detail.Length -gt 500) { $detail = $detail.Substring(0, 500) }

    return [pscustomobject]@{ State = $state; Detail = $detail }
}
