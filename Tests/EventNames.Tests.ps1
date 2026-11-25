BeforeDiscovery {
    $states = 'Healthy', 'NeedsReauth', 'NotSignedIn', 'Degraded', 'Unknown'
    $script:DecisionCases = foreach ($configured in $true, $false) {
        foreach ($running in $true, $false) {
            foreach ($state in $states) {
                foreach ($marker in $true, $false) {
                    @{ Configured = $configured; Running = $running; State = $state; Marker = $marker }
                }
            }
        }
    }
    $script:PromptCases = foreach ($kind in 'FirstLogin', 'Reauth') {
        foreach ($action in 'SignIn', 'Later', 'TimedOut', 'Dismissed') {
            foreach ($configured in $true, $false) {
                foreach ($state in $states) {
                    @{ Kind = $kind; Action = $action; Configured = $configured; State = $state }
                }
            }
        }
    }
}

BeforeAll {
    . (Join-Path $PSScriptRoot '..\Source\Private\Get-ODNagDecision.ps1')
    . (Join-Path $PSScriptRoot '..\Source\Private\Get-ODPromptResult.ps1')
    . (Join-Path $PSScriptRoot '..\Source\Private\Get-ODNagEventTable.ps1')
    $script:Table = Get-ODNagEventTable
}

Describe 'Event names produced by the decision functions' {
    It 'Get-ODNagDecision only names events in the event table (account=<Configured> running=<Running> state=<State> marker=<Marker>)' -ForEach $script:DecisionCases {
        $d = Get-ODNagDecision -AccountConfigured $Configured -ClientRunning $Running -HealthState $State -MarkerPresent $Marker
        foreach ($name in $d.Events) {
            $script:Table.ContainsKey($name) | Should -BeTrue -Because "'$name' must be defined in Get-ODNagEventTable"
        }
    }

    It 'Get-ODPromptResult only names events in the event table (<Kind> <Action> account=<Configured> state=<State>)' -ForEach $script:PromptCases {
        $r = Get-ODPromptResult -Action $Action -Kind $Kind -AccountConfigured $Configured -HealthState $State
        @($r.Events).Count | Should -BeGreaterThan 0
        foreach ($e in $r.Events) {
            $script:Table.ContainsKey($e.Event) | Should -BeTrue -Because "'$($e.Event)' must be defined in Get-ODNagEventTable"
        }
    }
}
