function Get-ODClientPath {
    <#
    .SYNOPSIS
        Returns the path to OneDrive.exe (per-machine install first), or $null when not installed.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $candidates = @(
        (Join-Path -Path $env:ProgramFiles -ChildPath 'Microsoft OneDrive\OneDrive.exe'),
        (Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath 'Microsoft OneDrive\OneDrive.exe'),
        (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Microsoft\OneDrive\OneDrive.exe')
    )

    $candidates | Where-Object { Test-Path -Path $_ } | Select-Object -First 1
}
