function Get-ODSyncStatus {
    <#
    .SYNOPSIS
        Runs ODSyncUtil and returns a result object: Available, ExitCode, Roots, Error.
    .DESCRIPTION
        Returns a wrapper object rather than a bare array. A function that returns an
        empty array hands $null to its caller, which used to make "no sync roots"
        indistinguishable from "ODSyncUtil failed".
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        # Full path to ODSyncUtil.exe
        [Parameter(Mandatory)]
        [string] $ExePath
    )

    $result = [pscustomobject]@{
        Available = $false
        ExitCode  = $null
        Roots     = @()
        Error     = $null
    }

    if (-not (Test-Path -Path $ExePath)) {
        $result.Error = "ODSyncUtil not found at $ExePath"
        return $result
    }

    try {
        # Join the lines: Windows PowerShell 5.1 would otherwise parse each output line as separate JSON
        $output = (& $ExePath 2>$null) -join [Environment]::NewLine
        $result.ExitCode = $LASTEXITCODE

        if (-not [string]::IsNullOrWhiteSpace($output)) {
            # Wrapping the call in parentheses makes 5.1 enumerate a JSON array instead of returning it as one object
            $result.Roots = @(($output | ConvertFrom-Json))
        }

        $result.Available = $true
    }
    catch {
        $result.Error = $_.Exception.Message
    }

    return $result
}
