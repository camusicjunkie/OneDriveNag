BeforeAll {
    $source = Join-Path $PSScriptRoot '..\Source'
    . (Join-Path $source 'Private\Get-ODNagEventTable.ps1')
    . (Join-Path $source 'Public\New-ODNagLogger.ps1')
    . (Join-Path $source 'Public\Write-ODNagEvent.ps1')
    $script:root = Split-Path $PSScriptRoot -Parent
}

Describe 'Write-ODNagEvent' {
    BeforeEach {
        $script:path = Join-Path $TestDrive ('sub{0}\nag.log' -f [guid]::NewGuid())
        $script:logger = New-ODNagLogger -LogSource 'T' -FallbackLogPath $script:path
    }

    It 'writes the table ID, entry type and JSON message to the event log' {
        Mock Write-EventLog {}
        Write-ODNagEvent -Logger $logger -Event 'Degraded' -Data @{ upn = 'a@b.c' }
        Should -Invoke Write-EventLog -Times 1 -Exactly -ParameterFilter {
            $Source -eq 'T' -and $EventId -eq 1011 -and $EntryType -eq 'Warning' -and
            ($Message | ConvertFrom-Json).stage -eq 'Degraded' -and ($Message | ConvertFrom-Json).upn -eq 'a@b.c'
        }
    }

    It 'falls back to the file with the schema version when Write-EventLog fails' {
        Mock Write-EventLog { throw 'no source' }
        Write-ODNagEvent -Logger $logger -Event 'Healthy'
        $line = Get-Content -Path $path | ConvertFrom-Json
        $line.schema | Should -Be 2
        $line.stage | Should -Be 'Healthy'
    }

    It 'includes the logger base context' {
        Mock Write-EventLog { throw 'no source' }
        $logger.Context['upn'] = 'x@y.z'
        Write-ODNagEvent -Logger $logger -Event 'Healthy'
        (Get-Content -Path $path | ConvertFrom-Json).upn | Should -Be 'x@y.z'
    }

    It 'lets schema fields win over caller data' {
        Mock Write-EventLog { throw 'no source' }
        Write-ODNagEvent -Logger $logger -Event 'Healthy' -Data @{ stage = 'Evil'; user = 'mallory'; schema = 99; extra = 1 }
        $line = Get-Content -Path $path | ConvertFrom-Json
        $line.stage | Should -Be 'Healthy'
        $line.user | Should -Be $env:USERNAME
        $line.schema | Should -Be 2
        $line.extra | Should -Be 1
    }

    It 'drops the event without throwing or console output when every target fails' {
        Mock Write-EventLog { throw 'no source' }
        $bad = New-ODNagLogger -LogSource 'T' -FallbackLogPath 'Z:\nonexistent\\:::\x.log'
        { Write-ODNagEvent -Logger $bad -Event 'Healthy' 6>&1 5>&1 4>&1 3>&1 } | Should -Not -Throw
        (Write-ODNagEvent -Logger $bad -Event 'Healthy' 6>&1 5>&1 4>&1 3>&1) | Should -BeNullOrEmpty
    }

    It 'does not throw for an unknown event name' {
        Mock Write-EventLog {}
        { Write-ODNagEvent -Logger $logger -Event 'Nope' } | Should -Not -Throw
        Should -Invoke Write-EventLog -Times 0 -Exactly
    }
}

Describe 'Event table' {
    BeforeAll { $script:table = Get-ODNagEventTable }

    It 'has distinct stages with 1004 and 1008 shared by TimedOut and Dismissed' {
        $table['FirstLoginTimedOut'].EventId | Should -Be 1004
        $table['FirstLoginDismissed'].EventId | Should -Be 1004
        $table['ReauthTimedOut'].EventId | Should -Be 1008
        $table['ReauthDismissed'].EventId | Should -Be 1008
    }

    It 'has no ID shared by unrelated events' {
        $shared = $table.GetEnumerator() | Group-Object { $_.Value.EventId } | Where-Object Count -gt 1
        foreach ($g in $shared) { ($g.Group.Key | Where-Object { $_ -notmatch '(TimedOut|Dismissed|SignedInElsewhere)$' }) | Should -BeNullOrEmpty }
    }

    It 'lists every event ID in the README' {
        $readme = Get-Content -Raw (Join-Path $root 'README.md')
        foreach ($id in ($table.Values.EventId | Sort-Object -Unique)) { $readme | Should -Match "\b$id\b" }
    }

    It 'contains every literal stage the Splunk dashboard names' {
        $xml = Get-Content -Raw (Join-Path $root 'Splunk\OneDriveNag.xml')
        $named = [regex]::Matches($xml, 'stage\s*(?:!=|=)\s*"(\w+)"|stage\s+IN\s*\(([^)]*)\)') | ForEach-Object {
            if ($_.Groups[1].Success) { $_.Groups[1].Value }
            else { [regex]::Matches($_.Groups[2].Value, '"(\w+)"') | ForEach-Object { $_.Groups[1].Value } }
        }
        $named | Should -Not -BeNullOrEmpty
        foreach ($n in $named) { $table.Keys | Should -Contain $n }
    }

    It 'ends prompt stages in Shown, Acted, Deferred, TimedOut, Dismissed or SignedInElsewhere' {
        foreach ($k in $table.Keys | Where-Object { $_ -match '^(FirstLogin|Reauth)' }) {
            $k | Should -Match '^(FirstLogin|Reauth)(Shown|Acted|Deferred|TimedOut|Dismissed|SignedInElsewhere)$'
        }
    }
}

Describe 'Logger parameters' {
    It 'no function other than New-ODNagLogger takes LogSource or FallbackLogPath' {
        foreach ($f in Get-ChildItem (Join-Path $root 'Source') -Recurse -Filter *.ps1 | Where-Object Name -NotIn 'New-ODNagLogger.ps1','Register-OneDriveNagSource.ps1','Invoke-OneDriveNag.ps1') {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$null)
            $names = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.ParameterAst] }, $true).Name.VariablePath.UserPath
            $names | Should -Not -Contain 'LogSource' -Because $f.Name
            $names | Should -Not -Contain 'FallbackLogPath' -Because $f.Name
        }
    }
}

