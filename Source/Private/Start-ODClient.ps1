function Start-ODClient {
    <#
    .SYNOPSIS
        The one way to start, background-start or restart the OneDrive client.
    .DESCRIPTION
        Default: launches OneDrive so it shows its sign-in UI.
        -Background: starts the client hidden if it is not running, waits for the process to
        appear, then waits the settle time so the sync engine can register its roots. Returns
        whether the client is running; returns at once if it already is.
        -Restart: shuts down a running client, waits up to 30 seconds for OneDrive.exe to exit,
        then starts it again.
        When OneDrive.exe cannot be found, event 1013 is logged, nothing is started and the
        result is $false.
    .NOTES
        Restarting makes the client re-check its token on startup, which should bring
        up the sign-in window when the token has expired. Confirm this on your build.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        # Logger from New-ODNagLogger
        [Parameter(Mandatory)]
        [pscustomobject] $Logger,

        # Start the client hidden if needed and wait until it is running and settled
        [switch] $Background,

        # Shut down a running client first so it re-checks its token when it starts
        [switch] $Restart,

        # With -Background: maximum seconds to wait for OneDrive.exe to appear
        [int] $TimeoutSeconds = 120,

        # With -Background: extra seconds after the process appears so the sync engine can register its roots
        [int] $SettleSeconds = 30
    )

    if ($Background -and -not $Restart -and (Test-ODClientRunning)) { return $true }

    $exe = Get-ODClientPath
    if ($null -eq $exe) {
        Write-ODNagEvent -Logger $Logger -Event 'ClientNotFound'
        return $false
    }

    if ($Restart -and (Test-ODClientRunning)) {
        Start-Process -FilePath $exe -ArgumentList '/shutdown' -Wait
        # Time is counted in sleeps, not read from the clock
        $waited = 0
        while ((Test-ODClientRunning) -and $waited -lt 30) {
            Start-Sleep -Seconds 1
            $waited++
        }
    }

    if (-not $Background) {
        Start-Process -FilePath $exe
        return $true
    }

    Start-Process -FilePath $exe -ArgumentList '/background'
    $waited = 0
    while ($waited -lt $TimeoutSeconds) {
        if (Test-ODClientRunning) {
            Start-Sleep -Seconds $SettleSeconds
            return $true
        }
        Start-Sleep -Seconds 5
        $waited += 5
    }
    return $false
}
