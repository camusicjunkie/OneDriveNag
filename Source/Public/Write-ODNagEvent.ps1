function Write-ODNagEvent {
    <#
    .SYNOPSIS
        Writes a structured (JSON) telemetry event to the Application log for Splunk to pick up.
    .DESCRIPTION
        The event ID, stage and entry type come from the event table. Fields from the logger's
        context and from -Data are added, but the schema fields (schema, timestamp, stage, user,
        computer, sid, session) always win. Falls back to a flat file when the event source is not
        registered. Never throws and never writes to the console; if both targets fail, or the event
        name is unknown, the event is dropped.
    #>
    [CmdletBinding()]
    param(
        # Logger from New-ODNagLogger
        [Parameter(Mandatory)]
        [pscustomobject] $Logger,

        # Event name from the event table, such as FirstLoginShown, ReauthActed or Healthy
        [Parameter(Mandatory)]
        [string] $Event,

        # Extra key/value fields to add to the JSON payload
        [hashtable] $Data = @{}
    )

    try {
        $definition = (Get-ODNagEventTable)[$Event]
        if ($null -eq $definition) { return }

        $payload = [ordered]@{}
        foreach ($source in $Logger.Context, $Data) {
            foreach ($key in $source.Keys) { $payload[$key] = $source[$key] }
        }
        $payload['schema'] = 2
        $payload['timestamp'] = (Get-Date).ToUniversalTime().ToString('o')
        $payload['stage'] = $definition.Stage
        $payload['user'] = $env:USERNAME
        $payload['computer'] = $env:COMPUTERNAME
        $payload['sid'] = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
        $payload['session'] = (Get-Process -Id $PID).SessionId

        $json = $payload | ConvertTo-Json -Compress

        try {
            Write-EventLog -LogName Application -Source $Logger.LogSource -EventId $definition.EventId `
                -EntryType $definition.EntryType -Message $json -ErrorAction Stop
        }
        catch {
            $directory = Split-Path -Path $Logger.FallbackLogPath -Parent
            if (-not (Test-Path -Path $directory)) {
                $null = New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop
            }
            Add-Content -Path $Logger.FallbackLogPath -Value $json -ErrorAction Stop
        }
    }
    catch {
        # Nowhere left to log; drop the event rather than throw or write to the console
    }
}
