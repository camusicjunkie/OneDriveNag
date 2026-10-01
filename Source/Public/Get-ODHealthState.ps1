function Get-ODHealthState {
    <#
    .SYNOPSIS
        Classifies ODSyncUtil output as Healthy, NeedsReauth, NotSignedIn, Degraded, or Unknown.
    .DESCRIPTION
        Collects the text of every State/Status/Label property on every sync root and
        matches it against the patterns. Detail carries that raw text into telemetry so
        you can confirm in Splunk which values your OneDrive build actually emits, then
        tighten AuthPattern before you rely on it.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        # Result object from Get-ODSyncStatus
        [Parameter(Mandatory)]
        [pscustomobject] $SyncStatus,

        # Regex for state/label text that means the sign-in has expired or is missing
        [string] $AuthPattern = 'sign.?in|signed.?out|auth|credential',

        # Regex for problems worth logging that a sign-in would not fix (no prompt)
        [string] $DegradedPattern = 'error|paused|blocked|full'
    )

    if (-not $SyncStatus.Available) {
        return [pscustomobject]@{ State = 'Unknown'; Detail = $SyncStatus.Error }
    }

    if ($SyncStatus.Roots.Count -eq 0) {
        return [pscustomobject]@{ State = 'NotSignedIn'; Detail = 'No sync roots reported' }
    }

    $stateText = foreach ($root in $SyncStatus.Roots) {
        foreach ($property in $root.PSObject.Properties) {
            if ($property.Name -match 'State|Status|Label') { [string]$property.Value }
        }
    }
    $detail = ($stateText -join ' | ')
    if ($detail.Length -gt 500) { $detail = $detail.Substring(0, 500) }

    $state = 'Healthy'
    if ($detail -match $AuthPattern) {
        $state = 'NeedsReauth'
    }
    elseif ($detail -match $DegradedPattern) {
        $state = 'Degraded'
    }

    return [pscustomobject]@{ State = $state; Detail = $detail }
}
