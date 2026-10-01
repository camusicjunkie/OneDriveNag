function Wait-ODClient {
    <#
    .SYNOPSIS
        Makes sure OneDrive.exe is running in this session, starting it in the background if needed.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        # Maximum seconds to wait for OneDrive.exe to appear
        [int] $TimeoutSeconds = 120,

        # Extra seconds after the process appears so the sync engine can register its roots
        [int] $SettleSeconds = 30
    )

    if (Test-ODClientRunning) { return $true }

    $exe = Get-ODClientPath
    if ($null -eq $exe) { return $false }

    Start-Process -FilePath $exe -ArgumentList '/background'

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-ODClientRunning) {
            Start-Sleep -Seconds $SettleSeconds
            return $true
        }
        Start-Sleep -Seconds 5
    }

    return $false
}
