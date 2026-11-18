BeforeDiscovery {
    $cases = foreach ($configured in $true, $false) {
        foreach ($running in $true, $false) {
            foreach ($state in 'Healthy', 'NeedsReauth', 'NotSignedIn', 'Degraded', 'Unknown') {
                foreach ($marker in $true, $false) {
                    # Expected values come from the spec table, not recomputed by the code
                    if (-not $configured) {
                        $prompt = 'FirstLogin'; $ids = @(); $m = 'Keep'
                    }
                    elseif (-not $running) {
                        $prompt = $null; $ids = @(1010); $m = 'Keep'
                    }
                    else {
                        switch ($state) {
                            'Healthy'     { $prompt = $null; if ($marker) { $ids = @(); $m = 'Keep' } else { $ids = @(1003); $m = 'Set' } }
                            'NeedsReauth' { $prompt = 'Reauth'; $ids = @(); $m = 'Clear' }
                            'NotSignedIn' { $prompt = 'Reauth'; $ids = @(); $m = 'Clear' }
                            'Degraded'    { $prompt = $null; $ids = @(1011); $m = 'Clear' }
                            'Unknown'     { $prompt = $null; $ids = @(1010); $m = 'Keep' }
                        }
                    }
                    @{ Configured = $configured; Running = $running; State = $state; Marker = $marker; Prompt = $prompt; Ids = $ids; MarkerAction = $m }
                }
            }
        }
    }
}

BeforeAll {
    . (Join-Path $PSScriptRoot '..\Source\Public\Get-ODNagDecision.ps1')
}

Describe 'Get-ODNagDecision' {
    It 'configured=<Configured> running=<Running> state=<State> marker=<Marker>' -ForEach $cases {
        $d = Get-ODNagDecision -AccountConfigured $Configured -ClientRunning $Running -HealthState $State -MarkerPresent $Marker
        $d.Prompt | Should -Be $Prompt
        $d.Marker | Should -Be $MarkerAction
        @($d.Events | ForEach-Object { $_.EventId }) | Should -Be $Ids
    }

    It 'logs 1003 twice across Healthy, Degraded, Healthy runs' {
        $marker = $false
        $logged = 0
        foreach ($state in 'Healthy', 'Degraded', 'Healthy') {
            $d = Get-ODNagDecision -AccountConfigured $true -ClientRunning $true -HealthState $state -MarkerPresent $marker
            $logged += @($d.Events | Where-Object EventId -eq 1003).Count
            if ($d.Marker -eq 'Set') { $marker = $true } elseif ($d.Marker -eq 'Clear') { $marker = $false }
        }
        $logged | Should -Be 2
    }

    It 'leaves the marker unchanged on Unknown' {
        foreach ($m in $true, $false) {
            (Get-ODNagDecision -AccountConfigured $true -ClientRunning $true -HealthState Unknown -MarkerPresent $m).Marker | Should -Be 'Keep'
        }
    }

    It 'gives events the stage and entry type used today' {
        $d = Get-ODNagDecision -AccountConfigured $true -ClientRunning $true -HealthState Degraded -MarkerPresent $false
        $d.Events[0].Stage | Should -Be 'Degraded'
        $d.Events[0].EntryType | Should -Be 'Warning'
        $d = Get-ODNagDecision -AccountConfigured $true -ClientRunning $true -HealthState Healthy -MarkerPresent $false
        $d.Events[0].Stage | Should -Be 'Healthy'
        $d.Events[0].EntryType | Should -Be 'Information'
    }
}
