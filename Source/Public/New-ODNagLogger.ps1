function New-ODNagLogger {
    <#
    .SYNOPSIS
        Creates the logger object that Write-ODNagEvent writes through.
    .DESCRIPTION
        A plain object holding the log source, the fallback file path and a base context added to
        every event. The module keeps no state: the caller creates the logger once and passes it in.
        Context is a hashtable the caller may add to later, such as once the user's address is known.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        # Application log source; registered machine-side by GPP Registry (or Register-OneDriveNagSource.ps1)
        [Parameter(Mandatory)]
        [string] $LogSource,

        # Flat file used only when the event source is not registered
        [Parameter(Mandatory)]
        [string] $FallbackLogPath,

        # Fields added to every event
        [hashtable] $Context = @{}
    )

    [pscustomobject]@{
        LogSource       = $LogSource
        FallbackLogPath = $FallbackLogPath
        Context         = $Context
    }
}
