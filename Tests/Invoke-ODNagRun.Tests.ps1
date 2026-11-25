BeforeAll {
    $source = Join-Path $PSScriptRoot '..\Source'
    foreach ($file in 'Private\Get-ODPromptProfile', 'Private\Get-ODClientPath', 'Private\Test-ODClientRunning',
        'Private\Invoke-ODSyncUtil', 'Private\Find-ODDirectoryUser', 'Private\Invoke-ODNagPrompt',
        'Public\Show-ODNagDialog', 'Public\Get-ODAccount', 'Public\Resolve-ODAccountEmail',
        'Public\Get-ODHealthState', 'Public\Get-ODNagDecision', 'Public\Get-ODPromptResult',
        'Public\Start-ODClient', 'Public\Write-ODNagEvent', 'Public\New-ODNagLogger', 'Public\Invoke-ODNagRun') {
        . (Join-Path $source "$file.ps1")
    }

    # One sync root per state, as ODSyncUtil would report it
    $script:syncOutput = @{
        Healthy     = @{ ExitCode = 0; Output = '[{"ServiceName":"s","CurrentState":1,"CurrentStateString":"Up to date","Label":"OneDrive"}]' }
        NeedsReauth = @{ ExitCode = 0; Output = '[{"ServiceName":"s","CurrentState":9,"CurrentStateString":"Signed out","Label":"OneDrive"}]' }
        NotSignedIn = @{ ExitCode = 0; Output = '[]' }
        Degraded    = @{ ExitCode = 0; Output = '[{"ServiceName":"s","CurrentState":4,"CurrentStateString":"Error","Label":"OneDrive"}]' }
        Unknown     = @{ ExitCode = 1; Output = '' }
    }
}

Describe 'Invoke-ODNagRun' {
    BeforeEach {
        $script:marker = Join-Path $TestDrive 'healthy.flag'
        Remove-Item $script:marker -ErrorAction SilentlyContinue
        $script:events = [System.Collections.Generic.List[object]]::new()
        $script:launches = [System.Collections.Generic.List[string]]::new()
        $script:clientRunning = $true
        $script:clientPath = 'C:\OneDrive.exe'
        $script:accounts = @($true)      # Configured, one entry per registry read; the last repeats
        $script:accountIndex = 0
        $script:states = @('Healthy')    # health state, one entry per ODSyncUtil call; the last repeats
        $script:stateIndex = 0
        $script:action = 'Later'

        Mock Write-ODNagEvent { $script:events.Add([pscustomobject]@{ Event = $Event; Data = $Data; Context = $Logger.Context.Clone() }) }
        Mock Test-ODClientRunning { $script:clientRunning }
        Mock Get-ODClientPath { $script:clientPath }
        Mock Start-Process { $script:launches.Add($(if ($ArgumentList) { "$ArgumentList" } else { 'start' })) }
        Mock Start-Sleep {}
        Mock Get-ItemProperty {
            $configured = $script:accounts[[Math]::Min($script:accountIndex, $script:accounts.Count - 1)]
            $script:accountIndex++
            if ($configured) { [pscustomobject]@{ UserEmail = 'a@b.mil'; ConfiguredTenantId = 't' } } else { $null }
        }
        Mock Find-ODDirectoryUser { [pscustomobject]@{ Mail = 'ad@b.mil'; UserPrincipalName = 'ad@b.upn' } }
        Mock Invoke-ODSyncUtil {
            $state = $script:states[[Math]::Min($script:stateIndex, $script:states.Count - 1)]
            $script:stateIndex++
            [pscustomobject]$script:syncOutput[$state]
        }
        Mock Show-ODNagDialog { $script:action }

        $script:run = {
            Invoke-ODNagRun -Logger (New-ODNagLogger -LogSource 'T' -FallbackLogPath 'x.log') -ModuleRoot 'C:\mod' `
                -AccountKeyPath 'HKCU:\x' -ExpectedTenantId '' -HealthMarkerPath $script:marker `
                -ClientWaitSeconds 10 -PromptTimeoutMinutes 5
        }
    }

    It '<Name> logs <Want> and leaves the marker <MarkerAfter>' -ForEach @(
        @{ Name = 'client not running'; Running = $false; State = 'Healthy'; Marker = $false; Want = @('StatusUnknown'); MarkerAfter = 'absent' }
        @{ Name = 'client not running, marker present'; Running = $false; State = 'Healthy'; Marker = $true; Want = @('StatusUnknown'); MarkerAfter = 'present' }
        @{ Name = 'Healthy, no marker'; Running = $true; State = 'Healthy'; Marker = $false; Want = @('Healthy'); MarkerAfter = 'present' }
        @{ Name = 'Healthy, marker present'; Running = $true; State = 'Healthy'; Marker = $true; Want = @(); MarkerAfter = 'present' }
        @{ Name = 'Degraded, marker present'; Running = $true; State = 'Degraded'; Marker = $true; Want = @('Degraded'); MarkerAfter = 'absent' }
        @{ Name = 'Unknown, marker present'; Running = $true; State = 'Unknown'; Marker = $true; Want = @('StatusUnknown'); MarkerAfter = 'present' }
    ) {
        $script:clientRunning = $Running
        $script:states = @($State)
        if ($Marker) { $null = New-Item -ItemType File -Path $script:marker }

        & $script:run

        @($events.Event) | Should -Be $Want
        (Test-Path $script:marker) | Should -Be ($MarkerAfter -eq 'present')
        # The hidden background start while waiting for the client is not a prompt launch
        @($launches | Where-Object { $_ -ne '/background' }) | Should -BeNullOrEmpty
        Should -Invoke Show-ODNagDialog -Times 0 -Exactly
    }

    It 'logs <Want> for <Kind> when the user chooses <Action>' -ForEach @(
        @{ Kind = 'FirstLogin'; Action = 'SignIn'; Want = @('FirstLoginShown', 'FirstLoginActed'); Launch = @('start') }
        @{ Kind = 'FirstLogin'; Action = 'Later'; Want = @('FirstLoginShown', 'FirstLoginDeferred'); Launch = @() }
        @{ Kind = 'FirstLogin'; Action = 'TimedOut'; Want = @('FirstLoginShown', 'FirstLoginTimedOut'); Launch = @() }
        @{ Kind = 'FirstLogin'; Action = 'Dismissed'; Want = @('FirstLoginShown', 'FirstLoginDismissed'); Launch = @() }
        @{ Kind = 'Reauth'; Action = 'SignIn'; Want = @('ReauthShown', 'ReauthActed'); Launch = @('/shutdown', 'start') }
        @{ Kind = 'Reauth'; Action = 'Later'; Want = @('ReauthShown', 'ReauthDeferred'); Launch = @() }
        @{ Kind = 'Reauth'; Action = 'TimedOut'; Want = @('ReauthShown', 'ReauthTimedOut'); Launch = @() }
        @{ Kind = 'Reauth'; Action = 'Dismissed'; Want = @('ReauthShown', 'ReauthDismissed'); Launch = @() }
    ) {
        if ($Kind -eq 'FirstLogin') { $script:accounts = @($false) } else { $script:states = @('NeedsReauth') }
        $script:action = $Action

        & $script:run

        @($events.Event) | Should -Be $Want
        @($launches | Where-Object { $_ -ne '/background' }) | Should -Be $Launch
        Should -Invoke Show-ODNagDialog -Times 1 -Exactly
    }

    It 'prompts for <State> and clears the marker' -ForEach @(
        @{ State = 'NeedsReauth' }
        @{ State = 'NotSignedIn' }
    ) {
        $script:states = @($State)
        $null = New-Item -ItemType File -Path $script:marker

        & $script:run

        @($events.Event) | Should -Be @('ReauthShown', 'ReauthDeferred')
        (Test-Path $script:marker) | Should -BeFalse
    }

    It 'logs SignedInElsewhere and launches nothing when the <Kind> re-check finds the user signed in' -ForEach @(
        @{ Kind = 'FirstLogin'; Want = @('FirstLoginShown', 'FirstLoginSignedInElsewhere') }
        @{ Kind = 'Reauth'; Want = @('ReauthShown', 'ReauthSignedInElsewhere') }
    ) {
        if ($Kind -eq 'FirstLogin') { $script:accounts = @($false, $true) } else { $script:states = @('NeedsReauth', 'Healthy') }
        $script:action = 'SignIn'

        & $script:run

        @($events.Event) | Should -Be $Want
        @($launches | Where-Object { $_ -ne '/background' }) | Should -BeNullOrEmpty
    }

    It 'logs ClientNotFound when OneDrive.exe is missing after Sign in' {
        $script:accounts = @($false)
        $script:action = 'SignIn'
        $script:clientPath = $null

        & $script:run

        @($events.Event) | Should -Be @('FirstLoginShown', 'FirstLoginActed', 'ClientNotFound')
        $launches | Should -BeNullOrEmpty
    }

    It 'carries upn, clientRunning, syncState and syncDetail in the logger context' {
        $script:states = @('Healthy')

        & $script:run

        $context = $events[0].Context
        $context['upn'] | Should -Be 'a@b.mil'
        $context['clientRunning'] | Should -BeTrue
        $context['syncState'] | Should -Be 'Healthy'
        $context['syncDetail'] | Should -Match 'Up to date'
    }

    It 'reports an unknown sync state when a configured account has no running client' {
        $script:clientRunning = $false

        & $script:run

        $context = $events[0].Context
        $context['clientRunning'] | Should -BeFalse
        $context['syncState'] | Should -Be 'Unknown'
        $context['syncDetail'] | Should -Be 'OneDrive.exe not running in this session'
    }

    It 'looks the email up in the directory when the registry has none' {
        $script:accounts = @($false)

        & $script:run

        $events[0].Context['upn'] | Should -Be 'ad@b.mil'
        $events[0].Context.ContainsKey('syncState') | Should -BeFalse
    }
}
