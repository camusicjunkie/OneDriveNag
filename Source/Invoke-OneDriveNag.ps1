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

    Event IDs (source OneDriveAdoption, Application log, JSON message):
        1000 / 1001 / 1002 / 1004   first-login  shown / acted / deferred / timed-out-or-dismissed
        1005 / 1006 / 1007 / 1008   re-auth      shown / acted / deferred / timed-out-or-dismissed
        1003                        healthy (logged once each time the account recovers)
        1010                        unknown (client not running, or ODSyncUtil unavailable); no prompt
        1011                        degraded (a problem sign-in won't fix); no prompt
        1012                        AD email lookup failed; the logon name is used instead (warning)
        1013                        OneDrive.exe not found when starting the client (error)
        1014                        signed in through OneDrive's own window while the prompt was open; no action taken
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
    $forwarded = foreach ($entry in $PSBoundParameters.GetEnumerator()) {
        '-{0}' -f $entry.Key
        '"{0}"' -f $entry.Value
    }
    $arguments = @('-STA', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath)) + $forwarded
    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList $arguments
    return
}


function Invoke-NagPrompt {
    <#
    .SYNOPSIS
        Shows the first-login or re-auth prompt, acts on the user's choice, and logs each step.
    #>
    [CmdletBinding()]
    param(
        # Which prompt to show; selects the text and the event IDs
        [Parameter(Mandatory)]
        [ValidateSet('FirstLogin', 'Reauth')]
        [string] $Kind,

        # Path to the prompt XAML
        [Parameter(Mandatory)]
        [string] $XamlPath,

        # Address shown in the prompt
        [Parameter(Mandatory)]
        [string] $UserEmail,

        # Application log source for telemetry events
        [Parameter(Mandatory)]
        [string] $LogSource,

        # Flat file used only when the event source is not registered
        [Parameter(Mandatory)]
        [string] $FallbackLogPath,

        # Registry key for the OneDrive Business sync account, for the re-check after the prompt
        [Parameter(Mandatory)]
        [string] $AccountKeyPath,

        # Full path to ODSyncUtil.exe, for the re-check after the prompt
        [Parameter(Mandatory)]
        [string] $SyncUtilPath,

        # Optional Entra tenant GUID for a strict account match
        [string] $ExpectedTenantId = '',

        # Fields added to every telemetry event
        [hashtable] $Context = @{},

        # Minutes before the prompt closes itself
        [int] $TimeoutMinutes = 30
    )

    $log = @{ LogSource = $LogSource; FallbackLogPath = $FallbackLogPath; Data = $Context }

    $profiles = @{
        FirstLogin = @{
            Ids     = @{ Shown = 1000; SignIn = 1001; Later = 1002; Other = 1004 }
            Title   = 'Sign in to OneDrive'
            Message = 'Your files are moving to OneDrive. Please sign in now so your Desktop and Documents back up automatically. It takes about 20 seconds with your CAC.'
        }
        Reauth     = @{
            Ids     = @{ Shown = 1005; SignIn = 1006; Later = 1007; Other = 1008 }
            Title   = 'Sign back in to OneDrive'
            Message = 'Your OneDrive session has expired and your files have stopped backing up. Please sign in again with your CAC to resume syncing.'
        }
    }
    $selected = $profiles[$Kind]

    Write-ODNagEvent -EventId $selected.Ids.Shown -Stage "${Kind}Shown" @log

    $action = Show-ODNagDialog -XamlPath $XamlPath -UserEmail $UserEmail `
        -Title $selected.Title -Message $selected.Message -TimeoutMinutes $TimeoutMinutes

    # Re-check before acting: the user may have signed in through OneDrive's own window while ours was open
    $recheck = if ($Kind -eq 'FirstLogin') {
        @{ AccountConfigured = [bool](Get-ODAccount -AccountKeyPath $AccountKeyPath -ExpectedTenantId $ExpectedTenantId `
                -LogSource $LogSource -FallbackLogPath $FallbackLogPath).Configured }
    }
    else {
        @{ HealthState = (Get-ODHealthState -ExePath $SyncUtilPath).State }
    }

    $result = Get-ODPromptResult -Action $action -Kind $Kind @recheck
    foreach ($e in $result.Events) {
        $data = $Context.Clone()
        foreach ($key in $e.Data.Keys) { $data[$key] = $e.Data[$key] }
        Write-ODNagEvent -EventId $e.EventId -Stage $e.Stage -EntryType $e.EntryType `
            -LogSource $LogSource -FallbackLogPath $FallbackLogPath -Data $data
    }
    if ($result.Launch -ne 'None') {
        $null = Start-ODClient -Restart:($result.Launch -eq 'Restart') -Data $Context `
            -LogSource $LogSource -FallbackLogPath $FallbackLogPath
    }
}


# One run per session: a "Local\" mutex is scoped to this session, so repeat triggers can't stack dialogs
$mutex = [System.Threading.Mutex]::new($false, 'Local\OneDriveNag')
if (-not $mutex.WaitOne(0)) { return }

try {
    Import-Module -Name (Join-Path -Path $ModuleRoot -ChildPath 'OneDriveNag.psd1') -Force

    $xamlPath = Join-Path -Path $ModuleRoot -ChildPath 'OneDrivePrompt.xaml'
    $syncUtilPath = Join-Path -Path $ModuleRoot -ChildPath 'ODSyncUtil.exe'
    $healthMarker = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'OneDriveAdoption\healthy.flag'

    # Wait for the client before reading any state: a not-yet-started client looks "signed out"
    $clientRunning = Start-ODClient -Background -TimeoutSeconds $ClientWaitSeconds -LogSource $LogSource -FallbackLogPath $FallbackLogPath
    $logTarget = @{ LogSource = $LogSource; FallbackLogPath = $FallbackLogPath }
    $account = Get-ODAccount -AccountKeyPath $AccountKeyPath -ExpectedTenantId $ExpectedTenantId @logTarget
    $userEmail = $account.Email
    $context = @{ upn = $userEmail; clientRunning = $clientRunning }
    $promptArgs = @{
        XamlPath         = $xamlPath
        UserEmail        = $userEmail
        AccountKeyPath   = $AccountKeyPath
        SyncUtilPath     = $syncUtilPath
        ExpectedTenantId = $ExpectedTenantId
        TimeoutMinutes   = $PromptTimeoutMinutes
    }

    # Read the health state only when it can matter: an account is configured and the client is running
    $healthState = 'Unknown'
    if ($account.Configured -and $clientRunning) {
        $health = Get-ODHealthState -ExePath $syncUtilPath
        $healthState = $health.State
        $context['syncState'] = $health.State
        $context['syncDetail'] = $health.Detail
    }
    elseif ($account.Configured) {
        $context['syncState'] = 'Unknown'
        $context['syncDetail'] = 'OneDrive.exe not running in this session'
    }

    $markerPresent = Test-Path -Path $healthMarker
    $decision = Get-ODNagDecision -AccountConfigured ([bool]$account.Configured) -ClientRunning ([bool]$clientRunning) `
        -HealthState $healthState -MarkerPresent $markerPresent

    foreach ($e in $decision.Events) {
        Write-ODNagEvent -EventId $e.EventId -Stage $e.Stage -EntryType $e.EntryType -Data $context @logTarget
    }

    switch ($decision.Marker) {
        'Set'   { $null = New-Item -ItemType File -Path $healthMarker -Force }
        'Clear' { if ($markerPresent) { Remove-Item -Path $healthMarker -Force } }
    }

    if ($decision.Prompt) {
        Invoke-NagPrompt -Kind $decision.Prompt -Context $context @promptArgs @logTarget
    }}
finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
