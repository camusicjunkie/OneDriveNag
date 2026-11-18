function Invoke-ODSyncUtil {
    <#
    .SYNOPSIS
        Runs ODSyncUtil and returns its raw output and exit code.
    .DESCRIPTION
        The only place the process is started, so tests can mock it. Output is joined into
        one string: Windows PowerShell 5.1 would otherwise parse each line as separate JSON.
        A missing or unlaunchable executable returns exit code -1 with the reason as output.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        # Full path to ODSyncUtil.exe
        [Parameter(Mandatory)]
        [string] $ExePath
    )

    if (-not (Test-Path -Path $ExePath)) {
        return [pscustomobject]@{ Output = "ODSyncUtil not found at $ExePath"; ExitCode = -1 }
    }

    try {
        $output = (& $ExePath 2>$null) -join [Environment]::NewLine
        return [pscustomobject]@{ Output = $output; ExitCode = $LASTEXITCODE }
    }
    catch {
        return [pscustomobject]@{ Output = $_.Exception.Message; ExitCode = -1 }
    }
}
