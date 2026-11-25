function Invoke-ODNagPrompt {
    <#
    .SYNOPSIS
        Shows the prompt for a kind, acts on the user's choice and logs each step.
    .DESCRIPTION
        Handles FirstLogin and Reauth end to end: logs the Shown event, shows the dialog with the
        kind's text, re-checks the state (the account for FirstLogin, the health state for Reauth),
        applies Get-ODPromptResult, logs its events and starts or restarts the client. Only this
        function knows which re-check goes with which kind.
    #>
    [CmdletBinding()]
    param(
        # Which prompt to show; selects the text, the re-check and the event names
        [Parameter(Mandatory)]
        [ValidateSet('FirstLogin', 'Reauth')]
        [string] $Kind,

        # Path to the prompt XAML
        [Parameter(Mandatory)]
        [string] $XamlPath,

        # Address shown in the prompt
        [Parameter(Mandatory)]
        [string] $UserEmail,

        # Logger from New-ODNagLogger; its context is added to every event
        [Parameter(Mandatory)]
        [pscustomobject] $Logger,

        # Registry key for the OneDrive Business sync account, for the FirstLogin re-check
        [Parameter(Mandatory)]
        [string] $AccountKeyPath,

        # Full path to ODSyncUtil.exe, for the Reauth re-check
        [Parameter(Mandatory)]
        [string] $SyncUtilPath,

        # Optional Entra tenant GUID for a strict account match
        [string] $ExpectedTenantId = '',

        # Minutes before the prompt closes itself; 0 disables the timeout
        [int] $TimeoutMinutes = 30
    )

    Write-ODNagEvent -Logger $Logger -Event "${Kind}Shown"

    $promptProfile = Get-ODPromptProfile -Kind $Kind
    $action = Show-ODNagDialog -XamlPath $XamlPath -UserEmail $UserEmail `
        -Title $promptProfile.Title -Message $promptProfile.Message -TimeoutMinutes $TimeoutMinutes

    # Re-check before acting: the user may have signed in through OneDrive's own window while ours was open
    $recheck = if ($Kind -eq 'FirstLogin') {
        @{ AccountConfigured = [bool](Get-ODAccount -AccountKeyPath $AccountKeyPath -ExpectedTenantId $ExpectedTenantId).Configured }
    }
    else {
        @{ HealthState = (Get-ODHealthState -ExePath $SyncUtilPath).State }
    }

    $result = Get-ODPromptResult -Action $action -Kind $Kind @recheck
    foreach ($e in $result.Events) {
        Write-ODNagEvent -Logger $Logger -Event $e.Event -Data $e.Data
    }
    if ($result.Launch -ne 'None') {
        $null = Start-ODClient -Restart:($result.Launch -eq 'Restart') -Logger $Logger
    }
}
