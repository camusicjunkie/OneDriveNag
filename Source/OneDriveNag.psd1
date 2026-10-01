@{
    RootModule        = 'OneDriveNag.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '13c5e313-9139-4b91-aad9-0705fbd196b9'
    Description       = 'Detection, prompting, and telemetry helpers for OneDrive sign-in state.'
    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        'Test-ODAccountConfigured'
        'Get-ODUserEmail'
        'Get-ODClientPath'
        'Test-ODClientRunning'
        'Wait-ODClient'
        'Start-ODClient'
        'Get-ODSyncStatus'
        'Get-ODHealthState'
        'Write-ODNagEvent'
        'Show-ODNagDialog'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
