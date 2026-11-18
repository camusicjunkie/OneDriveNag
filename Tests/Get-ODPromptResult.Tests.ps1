BeforeAll {
    . (Join-Path $PSScriptRoot '..\Source\Public\Get-ODPromptResult.ps1')
}

Describe 'Get-ODPromptResult' {
    Context 'Reauth prompt' {
        It 'restarts the client on SignIn while still <State>' -ForEach @(
            @{ State = 'NeedsReauth' }, @{ State = 'NotSignedIn' }
        ) {
            $r = Get-ODPromptResult -Action SignIn -Kind Reauth -HealthState $State
            $r.Launch | Should -Be 'Restart'
            $r.Events[0].Event | Should -Be 'ReauthActed'
        }

        It 'logs 1014 with action and sync state and launches nothing when re-check says <State>' -ForEach @(
            @{ State = 'Healthy' }, @{ State = 'Degraded' }, @{ State = 'Unknown' }
        ) {
            $r = Get-ODPromptResult -Action SignIn -Kind Reauth -HealthState $State
            $r.Launch | Should -Be 'None'
            @($r.Events).Count | Should -Be 1
            $r.Events[0].Event | Should -Be 'ReauthSignedInElsewhere'
            $r.Events[0].Data.action | Should -Be 'SignIn'
            $r.Events[0].Data.syncState | Should -Be $State
        }

        It 'logs 1014 even for Later when the re-check says Healthy' {
            $r = Get-ODPromptResult -Action Later -Kind Reauth -HealthState Healthy
            $r.Launch | Should -Be 'None'
        }

        It 'launches nothing for <Action>' -ForEach @(
            @{ Action = 'Later'; Id = 1007; Stage = 'ReauthDeferred' }
            @{ Action = 'TimedOut'; Id = 1008; Stage = 'ReauthTimedOut' }
            @{ Action = 'Dismissed'; Id = 1008; Stage = 'ReauthDismissed' }
        ) {
            $r = Get-ODPromptResult -Action $Action -Kind Reauth -HealthState NeedsReauth
            $r.Launch | Should -Be 'None'
            $r.Events[0].Event | Should -Be $Stage
        }
    }

    Context 'FirstLogin prompt' {
        It 'starts the client without a restart on SignIn' {
            $r = Get-ODPromptResult -Action SignIn -Kind FirstLogin -AccountConfigured $false
            $r.Launch | Should -Be 'Start'
            $r.Events[0].Event | Should -Be 'FirstLoginActed'
        }

        It 'logs 1014 and launches nothing when the account is now configured' {
            $r = Get-ODPromptResult -Action SignIn -Kind FirstLogin -AccountConfigured $true
            $r.Launch | Should -Be 'None'
            $r.Events[0].Event | Should -Be 'FirstLoginSignedInElsewhere'
            $r.Events[0].Data.action | Should -Be 'SignIn'
        }

        It 'launches nothing for <Action>' -ForEach @(
            @{ Action = 'Later'; Id = 1002; Stage = 'FirstLoginDeferred' }
            @{ Action = 'TimedOut'; Id = 1004; Stage = 'FirstLoginTimedOut' }
            @{ Action = 'Dismissed'; Id = 1004; Stage = 'FirstLoginDismissed' }
        ) {
            $r = Get-ODPromptResult -Action $Action -Kind FirstLogin -AccountConfigured $false
            $r.Launch | Should -Be 'None'
            $r.Events[0].Event | Should -Be $Stage
        }
    }
}
