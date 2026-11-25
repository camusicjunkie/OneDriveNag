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
                        $prompt = $null; $ids = @('StatusUnknown'); $m = 'Keep'
                    }
                    else {
                        switch ($state) {
                            'Healthy'     { $prompt = $null; if ($marker) { $ids = @(); $m = 'Keep' } else { $ids = @('Healthy'); $m = 'Set' } }
                            'NeedsReauth' { $prompt = 'Reauth'; $ids = @(); $m = 'Clear' }
                            'NotSignedIn' { $prompt = 'Reauth'; $ids = @(); $m = 'Clear' }
                            'Degraded'    { $prompt = $null; $ids = @('Degraded'); $m = 'Clear' }
                            'Unknown'     { $prompt = $null; $ids = @('StatusUnknown'); $m = 'Keep' }
                        }
                    }
                    @{ Configured = $configured; Running = $running; State = $state; Marker = $marker; Prompt = $prompt; Ids = $ids; MarkerAction = $m }
                }
            }
        }
    }
}

BeforeAll {
    . (Join-Path $PSScriptRoot '..\Source\Private\Get-ODNagDecision.ps1')
}

Describe 'Get-ODNagDecision' {
    It 'configured=<Configured> running=<Running> state=<State> marker=<Marker>' -ForEach $cases {
        $d = Get-ODNagDecision -AccountConfigured $Configured -ClientRunning $Running -HealthState $State -MarkerPresent $Marker
        $d.Prompt | Should -Be $Prompt
        $d.Marker | Should -Be $MarkerAction
        @($d.Events) | Should -Be $Ids
    }

    It 'logs Healthy twice across Healthy, Degraded, Healthy runs' {
        $marker = $false
        $logged = 0
        foreach ($state in 'Healthy', 'Degraded', 'Healthy') {
            $d = Get-ODNagDecision -AccountConfigured $true -ClientRunning $true -HealthState $state -MarkerPresent $marker
            $logged += @($d.Events | Where-Object { $_ -eq 'Healthy' }).Count
            if ($d.Marker -eq 'Set') { $marker = $true } elseif ($d.Marker -eq 'Clear') { $marker = $false }
        }
        $logged | Should -Be 2
    }

    It 'leaves the marker unchanged on Unknown' {
        foreach ($m in $true, $false) {
            (Get-ODNagDecision -AccountConfigured $true -ClientRunning $true -HealthState Unknown -MarkerPresent $m).Marker | Should -Be 'Keep'
        }
    }
}
