function Test-ODClientRunning {
    <#
    .SYNOPSIS
        Returns $true when OneDrive.exe is running in the current user's session.
    .DESCRIPTION
        Filters by session ID so other users' OneDrive processes on a multi-session
        host don't count.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $sessionId = (Get-Process -Id $PID).SessionId
    $clients = Get-Process -Name 'OneDrive' -ErrorAction SilentlyContinue |
        Where-Object { $_.SessionId -eq $sessionId }

    return ($null -ne $clients)
}
