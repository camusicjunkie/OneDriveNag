function Write-ODNagEvent {
    <#
    .SYNOPSIS
        Writes a structured (JSON) telemetry event to the Application log for Splunk to pick up.
    .DESCRIPTION
        Falls back to a flat file when the event source is not registered. Never writes
        to the console; if both targets fail, the event is dropped.
    #>
    [CmdletBinding()]
    param(
        # Application log source; registered machine-side by GPP Registry (or Register-OneDriveNagSource.ps1)
        [Parameter(Mandatory)]
        [string] $LogSource,

        # Flat file used only when the event source is not registered
        [Parameter(Mandatory)]
        [string] $FallbackLogPath,

        # Numeric event ID for the funnel stage
        [Parameter(Mandatory)]
        [int] $EventId,

        # Short stage name, such as FirstLoginShown, ReauthActed, or Healthy
        [Parameter(Mandatory)]
        [string] $Stage,

        # Extra key/value fields to add to the JSON payload
        [hashtable] $Data = @{},

        # Event log entry type
        [ValidateSet('Information', 'Warning', 'Error')]
        [string] $EntryType = 'Information'
    )

    $payload = [ordered]@{
        schema    = 2
        timestamp = (Get-Date).ToUniversalTime().ToString('o')
        stage     = $Stage
        user      = $env:USERNAME
        computer  = $env:COMPUTERNAME
        sid       = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
        session   = (Get-Process -Id $PID).SessionId
    }
    foreach ($key in $Data.Keys) { $payload[$key] = $Data[$key] }

    $json = $payload | ConvertTo-Json -Compress

    try {
        Write-EventLog -LogName Application -Source $LogSource -EventId $EventId `
            -EntryType $EntryType -Message $json -ErrorAction Stop
    }
    catch {
        try {
            $directory = Split-Path -Path $FallbackLogPath -Parent
            if (-not (Test-Path -Path $directory)) {
                $null = New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop
            }
            Add-Content -Path $FallbackLogPath -Value $json -ErrorAction Stop
        }
        catch {
            # Nowhere left to log; drop the event rather than write to the console
        }
    }
}
