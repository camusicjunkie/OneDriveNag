#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    One-time per-machine registration of the Application event log source used by
    the OneDrive nag/telemetry script.
.DESCRIPTION
    Write-EventLog cannot register a new source from a non-elevated user context,
    so run this once per image/host (e.g. a GPO computer startup script). Without
    it, OneDriveNag falls back to writing a flat log file instead of events.
.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -File Register-OneDriveNagSource.ps1
#>
[CmdletBinding()]
param(
    # Event log source name; must match -LogSource on Invoke-OneDriveNag.ps1
    [string] $LogSource = 'OneDriveAdoption'
)

if (-not [System.Diagnostics.EventLog]::SourceExists($LogSource)) {
    New-EventLog -LogName Application -Source $LogSource
    Write-Verbose "Created event source '$LogSource'."
}
else {
    Write-Verbose "Event source '$LogSource' already exists."
}
