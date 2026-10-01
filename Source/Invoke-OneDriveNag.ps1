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
        1013                        OneDrive.exe not found when the user chose Sign in (error)
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
    $signedIn = if ($Kind -eq 'FirstLogin') {
        Test-ODAccountConfigured -AccountKeyPath $AccountKeyPath -ExpectedTenantId $ExpectedTenantId
    }
    else {
        (Get-ODHealthState -SyncStatus (Get-ODSyncStatus -ExePath $SyncUtilPath)).State -eq 'Healthy'
    }

    if ($signedIn) {
        Write-ODNagEvent -EventId 1014 -Stage "${Kind}SignedInElsewhere" -LogSource $LogSource `
            -FallbackLogPath $FallbackLogPath -Data ($Context + @{ action = $action })
        return
    }

    switch ($action) {
        'SignIn' {
            Write-ODNagEvent -EventId $selected.Ids.SignIn -Stage "${Kind}Acted" @log
            $null = Start-ODClient -Restart:($Kind -eq 'Reauth') -Data $Context `
                -LogSource $LogSource -FallbackLogPath $FallbackLogPath
        }
        'Later' {
            Write-ODNagEvent -EventId $selected.Ids.Later -Stage "${Kind}Deferred" -EntryType 'Warning' @log
        }
        default {
            Write-ODNagEvent -EventId $selected.Ids.Other -Stage "${Kind}$action" -EntryType 'Warning' @log
        }
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
    $clientRunning = Wait-ODClient -TimeoutSeconds $ClientWaitSeconds
    $logTarget = @{ LogSource = $LogSource; FallbackLogPath = $FallbackLogPath }
    $userEmail = Get-ODUserEmail -AccountKeyPath $AccountKeyPath @logTarget
    $context = @{ upn = $userEmail; clientRunning = $clientRunning }
    $promptArgs = @{
        XamlPath         = $xamlPath
        UserEmail        = $userEmail
        AccountKeyPath   = $AccountKeyPath
        SyncUtilPath     = $syncUtilPath
        ExpectedTenantId = $ExpectedTenantId
        TimeoutMinutes   = $PromptTimeoutMinutes
    }

    # --- First login: no account configured yet (checked after the wait, so an auto sign-in counts) ---
    if (-not (Test-ODAccountConfigured -AccountKeyPath $AccountKeyPath -ExpectedTenantId $ExpectedTenantId)) {
        Invoke-NagPrompt -Kind 'FirstLogin' -Context $context @promptArgs @logTarget
        return
    }

    # --- Account configured, but the client never started: no reliable status, so don't prompt ---
    if (-not $clientRunning) {
        $context['syncState'] = 'Unknown'
        $context['syncDetail'] = 'OneDrive.exe not running in this session'
        Write-ODNagEvent -EventId 1010 -Stage 'StatusUnknown' -Data $context @logTarget
        return
    }

    # --- Account configured and client running: classify its health ---
    $health = Get-ODHealthState -SyncStatus (Get-ODSyncStatus -ExePath $syncUtilPath)
    $context['syncState'] = $health.State
    $context['syncDetail'] = $health.Detail

    switch ($health.State) {
        'Healthy' {
            if (-not (Test-Path -Path $healthMarker)) {
                Write-ODNagEvent -EventId 1003 -Stage 'Healthy' -Data $context @logTarget
                $null = New-Item -ItemType File -Path $healthMarker -Force
            }
        }
        { $_ -in 'NeedsReauth', 'NotSignedIn' } {
            # Delete the marker so the next healthy run logs the recovery
            if (Test-Path -Path $healthMarker) { Remove-Item -Path $healthMarker -Force }
            Invoke-NagPrompt -Kind 'Reauth' -Context $context @promptArgs @logTarget
        }
        'Degraded' {
            Write-ODNagEvent -EventId 1011 -Stage 'Degraded' -EntryType 'Warning' -Data $context @logTarget
        }
        default {
            Write-ODNagEvent -EventId 1010 -Stage 'StatusUnknown' -Data $context @logTarget
        }
    }
}
finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
