function Start-ODClient {
    <#
    .SYNOPSIS
        Starts OneDrive so it shows its sign-in UI; -Restart cycles a running client first.
        Returns $false, and logs event 1013, when OneDrive.exe is not installed.
    .NOTES
        Launching an already-running client usually just opens the OneDrive folder.
        Restarting makes the client re-check its token on startup, which should bring
        up the sign-in window when the token has expired. Confirm this on your build.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        # Application log source for telemetry events
        [Parameter(Mandatory)]
        [string] $LogSource,

        # Flat file used only when the event source is not registered
        [Parameter(Mandatory)]
        [string] $FallbackLogPath,

        # Shut down a running client first so it re-checks its token when it starts
        [switch] $Restart,

        # Extra key/value fields to add to the event
        [hashtable] $Data = @{}
    )

    $exe = Get-ODClientPath
    if ($null -eq $exe) {
        Write-ODNagEvent -EventId 1013 -Stage 'ClientNotFound' -EntryType 'Error' `
            -LogSource $LogSource -FallbackLogPath $FallbackLogPath -Data $Data
        return $false
    }

    if ($Restart -and (Test-ODClientRunning)) {
        Start-Process -FilePath $exe -ArgumentList '/shutdown' -Wait
    }

    Start-Process -FilePath $exe
    return $true
}
