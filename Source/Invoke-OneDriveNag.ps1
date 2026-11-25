#Requires -Version 5.1
<#
.SYNOPSIS
    Prompts the user to sign in, or sign back in, to OneDrive when needed, and logs
    telemetry events for Splunk.
.DESCRIPTION
    Deployed by a computer-side GPP Scheduled Task that runs as BUILTIN\Users with
    "Run only when user is logged on". Triggers are at logon, on session reconnect,
    and on unlock, repeating every few hours. The repeat catches the roughly weekly
    DISA token expiry in the middle of a session.

    Events are defined once, in the private event table (Get-ODNagEventTable). Their IDs and
    meanings are listed in the README. A new event goes in that table and in the README.

.EXAMPLE
    powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Program Files\OneDriveNag\Invoke-OneDriveNag.ps1"
#>
[CmdletBinding()]
param(
    # Folder holding OneDriveNag.psd1/.psm1, OneDrivePrompt.xaml and ODSyncUtil.exe
    [string] $ModuleRoot = $PSScriptRoot,

    # Seconds to wait for OneDrive.exe to start before evaluating its state
    [int] $ClientWaitSeconds = 120,

    # Minutes before an unanswered prompt closes itself and is logged as timed out
    [int] $PromptTimeoutMinutes = 30,

    # Optional Entra tenant GUID for a strict account match
    [string] $ExpectedTenantId = '',

    # Registry key for the OneDrive Business sync account
    [string] $AccountKeyPath = 'HKCU:\Software\Microsoft\OneDrive\Accounts\Business1',

    # Application log source; must match the one Register-OneDriveNagSource.ps1 registers
    [string] $LogSource = 'OneDriveAdoption',

    # Flat file used only when the event source is not registered
    [string] $FallbackLogPath = (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'OneDriveAdoption\nag.log')
)

# Remove any trailing backslash: in a quoted argument, \" escapes the closing quote
$ModuleRoot = $ModuleRoot.TrimEnd('\')

# WPF needs a single-threaded apartment; relaunch with -STA and pass the parameters along
if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    # Forward the trimmed root, not the value as passed
    if ($PSBoundParameters.ContainsKey('ModuleRoot')) { $PSBoundParameters['ModuleRoot'] = $ModuleRoot }

    # Quote for the Windows command line: backslashes before a quote (or the closing quote) are
    # doubled and embedded quotes are escaped, so a trailing backslash or a quote can't break the arguments
    $quote = {
        param([string] $Value)
        '"' + ([regex]::Replace($Value, '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
    }
    $forwarded = foreach ($entry in $PSBoundParameters.GetEnumerator()) {
        '-{0}' -f $entry.Key
        & $quote ([string]$entry.Value)
    }
    $arguments = @('-STA', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (& $quote $PSCommandPath)) + $forwarded
    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList $arguments
    return
}


# One run per session: a "Local\" mutex is scoped to this session, so repeat triggers can't stack dialogs
$mutex = [System.Threading.Mutex]::new($false, 'Local\OneDriveNag')
if (-not $mutex.WaitOne(0)) { return }

try {
    Import-Module -Name (Join-Path -Path $ModuleRoot -ChildPath 'OneDriveNag.psd1') -Force

    # One logger for the run; Invoke-ODNagRun adds to its context as the account and health state become known
    $logger = New-ODNagLogger -LogSource $LogSource -FallbackLogPath $FallbackLogPath

    $healthMarker = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'OneDriveAdoption\healthy.flag'

    Invoke-ODNagRun -Logger $logger -ModuleRoot $ModuleRoot -AccountKeyPath $AccountKeyPath `
        -ExpectedTenantId $ExpectedTenantId -HealthMarkerPath $healthMarker `
        -ClientWaitSeconds $ClientWaitSeconds -PromptTimeoutMinutes $PromptTimeoutMinutes
}
finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
