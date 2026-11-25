function Invoke-ODNagRun {
    <#
    .SYNOPSIS
        Performs one Run: reads the account and health state, logs, sets or clears the health marker and prompts.
    .DESCRIPTION
        Waits for the client, reads the account, reads the health state when it can matter, adds
        upn, clientRunning, syncState and syncDetail to the logger's context, applies the Nag
        decision, logs its events, sets or clears the health marker and runs the prompt. Returns nothing.
    #>
    [CmdletBinding()]
    param(
        # Logger from New-ODNagLogger; its context grows as the account and health state become known
        [Parameter(Mandatory)]
        [pscustomobject] $Logger,

        # Folder holding OneDrivePrompt.xaml and ODSyncUtil.exe
        [Parameter(Mandatory)]
        [string] $ModuleRoot,

        # Registry key for the OneDrive Business sync account
        [Parameter(Mandatory)]
        [string] $AccountKeyPath,

        # Optional Entra tenant GUID for a strict account match
        [string] $ExpectedTenantId = '',

        # File whose presence means the last Run found the account healthy
        [Parameter(Mandatory)]
        [string] $HealthMarkerPath,

        # Seconds to wait for OneDrive.exe to start before evaluating its state
        [int] $ClientWaitSeconds = 120,

        # Minutes before an unanswered prompt closes itself and is logged as timed out
        [int] $PromptTimeoutMinutes = 30
    )

    $xamlPath = Join-Path -Path $ModuleRoot -ChildPath 'OneDrivePrompt.xaml'
    $syncUtilPath = Join-Path -Path $ModuleRoot -ChildPath 'ODSyncUtil.exe'

    # Wait for the client before reading any state: a not-yet-started client looks "signed out"
    $clientRunning = Start-ODClient -Background -TimeoutSeconds $ClientWaitSeconds -Logger $Logger
    $account = Get-ODAccount -AccountKeyPath $AccountKeyPath -ExpectedTenantId $ExpectedTenantId
    $userEmail = Resolve-ODAccountEmail -RegistryEmail $account.Email -Logger $Logger
    $Logger.Context['upn'] = $userEmail
    $Logger.Context['clientRunning'] = $clientRunning

    # Read the health state only when it can matter: an account is configured and the client is running
    $healthState = 'Unknown'
    if ($account.Configured -and $clientRunning) {
        $health = Get-ODHealthState -ExePath $syncUtilPath
        $healthState = $health.State
        $Logger.Context['syncState'] = $health.State
        $Logger.Context['syncDetail'] = $health.Detail
    }
    elseif ($account.Configured) {
        $Logger.Context['syncState'] = 'Unknown'
        $Logger.Context['syncDetail'] = 'OneDrive.exe not running in this session'
    }

    $markerPresent = Test-Path -Path $HealthMarkerPath
    $decision = Get-ODNagDecision -AccountConfigured ([bool]$account.Configured) -ClientRunning ([bool]$clientRunning) `
        -HealthState $healthState -MarkerPresent $markerPresent

    foreach ($e in $decision.Events) {
        Write-ODNagEvent -Logger $Logger -Event $e
    }

    switch ($decision.Marker) {
        'Set'   { $null = New-Item -ItemType File -Path $HealthMarkerPath -Force }
        'Clear' { if ($markerPresent) { Remove-Item -Path $HealthMarkerPath -Force } }
    }

    if ($decision.Prompt) {
        Invoke-ODNagPrompt -Kind $decision.Prompt -Logger $Logger -XamlPath $xamlPath -UserEmail $userEmail `
            -AccountKeyPath $AccountKeyPath -SyncUtilPath $syncUtilPath -ExpectedTenantId $ExpectedTenantId `
            -TimeoutMinutes $PromptTimeoutMinutes
    }
}
