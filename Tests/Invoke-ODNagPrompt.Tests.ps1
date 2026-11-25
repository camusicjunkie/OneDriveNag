BeforeAll {
    $source = Join-Path $PSScriptRoot '..\Source'
    . (Join-Path $source 'Private\Get-ODPromptProfile.ps1')
    . (Join-Path $source 'Private\Get-ODClientPath.ps1')
    . (Join-Path $source 'Private\Test-ODClientRunning.ps1')
    . (Join-Path $source 'Private\Show-ODNagDialog.ps1')
    . (Join-Path $source 'Private\Get-ODAccount.ps1')
    . (Join-Path $source 'Private\Get-ODHealthState.ps1')
    . (Join-Path $source 'Private\Get-ODPromptResult.ps1')
    . (Join-Path $source 'Private\Start-ODClient.ps1')
    . (Join-Path $source 'Private\Write-ODNagEvent.ps1')
    . (Join-Path $source 'Public\New-ODNagLogger.ps1')
    . (Join-Path $source 'Private\Invoke-ODNagPrompt.ps1')

    $script:common = @{
        XamlPath       = 'x.xaml'
        UserEmail      = 'a@b.mil'
        Logger         = (New-ODNagLogger -LogSource 'T' -FallbackLogPath 'x.log')
        AccountKeyPath = 'HKCU:\x'
        SyncUtilPath   = 'C:\ODSyncUtil.exe'
        TimeoutMinutes = 5
    }
}

Describe 'Invoke-ODNagPrompt' {
    BeforeEach {
        $script:seen = $null
        $script:events = [System.Collections.Generic.List[string]]::new()
        $script:action = 'Later'
        Mock Show-ODNagDialog {
            $script:seen = @{ Title = $Title; Message = $Message; UserEmail = $UserEmail; TimeoutMinutes = $TimeoutMinutes; XamlPath = $XamlPath }
            $script:action
        }
        Mock Write-ODNagEvent { $script:events.Add($Event) }
        Mock Get-ODAccount { [pscustomobject]@{ Configured = $false } }
        Mock Get-ODHealthState { [pscustomobject]@{ State = 'NeedsReauth' } }
        Mock Get-ODClientPath { 'C:\OneDrive.exe' }
        Mock Test-ODClientRunning { $true }
        Mock Start-Process {}
        Mock Start-Sleep {}
    }

    It 'shows the <Kind> text and logs Shown first' -ForEach @(
        @{ Kind = 'FirstLogin'; WantTitle = 'Sign in to OneDrive'; WantMessage = 'Your files are moving to OneDrive. Please sign in now so your Desktop and Documents back up automatically. It takes about 20 seconds with your CAC.' }
        @{ Kind = 'Reauth'; WantTitle = 'Sign back in to OneDrive'; WantMessage = 'Your OneDrive session has expired and your files have stopped backing up. Please sign in again with your CAC to resume syncing.' }
    ) {
        Invoke-ODNagPrompt -Kind $Kind @common
        Should -Invoke Show-ODNagDialog -Times 1 -Exactly
        $seen.Title | Should -Be $WantTitle
        $seen.Message | Should -Be $WantMessage
        $seen.UserEmail | Should -Be 'a@b.mil'
        $seen.TimeoutMinutes | Should -Be 5
        $seen.XamlPath | Should -Be 'x.xaml'
        $events[0] | Should -Be "${Kind}Shown"
    }

    It '<Kind> <Action> logs <Want> and launches nothing' -ForEach @(
        @{ Kind = 'FirstLogin'; Action = 'Later'; Want = 'FirstLoginDeferred' }
        @{ Kind = 'FirstLogin'; Action = 'TimedOut'; Want = 'FirstLoginTimedOut' }
        @{ Kind = 'FirstLogin'; Action = 'Dismissed'; Want = 'FirstLoginDismissed' }
        @{ Kind = 'Reauth'; Action = 'Later'; Want = 'ReauthDeferred' }
        @{ Kind = 'Reauth'; Action = 'TimedOut'; Want = 'ReauthTimedOut' }
        @{ Kind = 'Reauth'; Action = 'Dismissed'; Want = 'ReauthDismissed' }
    ) {
        $script:action = $Action
        Invoke-ODNagPrompt -Kind $Kind @common
        $events | Should -Be @("${Kind}Shown", $Want)
        Should -Invoke Start-Process -Times 0 -Exactly
    }

    It 'FirstLogin Sign in logs Acted and starts the client without a shutdown' {
        $script:action = 'SignIn'
        Invoke-ODNagPrompt -Kind FirstLogin @common
        $events | Should -Be @('FirstLoginShown', 'FirstLoginActed')
        Should -Invoke Start-Process -Times 1 -Exactly
        Should -Invoke Start-Process -Times 0 -Exactly -ParameterFilter { $ArgumentList -eq '/shutdown' }
    }

    It 'Reauth Sign in logs Acted and restarts the client' {
        $script:action = 'SignIn'
        Invoke-ODNagPrompt -Kind Reauth @common
        $events | Should -Be @('ReauthShown', 'ReauthActed')
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $ArgumentList -eq '/shutdown' }
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { -not $ArgumentList }
    }

    It '<Kind> Sign in with OneDrive.exe missing logs ClientNotFound' -ForEach @(
        @{ Kind = 'FirstLogin' }
        @{ Kind = 'Reauth' }
    ) {
        $script:action = 'SignIn'
        Mock Get-ODClientPath { $null }
        Invoke-ODNagPrompt -Kind $Kind @common
        $events | Should -Be @("${Kind}Shown", "${Kind}Acted", 'ClientNotFound')
        Should -Invoke Start-Process -Times 0 -Exactly
    }

    It 'FirstLogin closed after an account appeared logs SignedInElsewhere and launches nothing' {
        $script:action = 'SignIn'
        Mock Get-ODAccount { [pscustomobject]@{ Configured = $true } }
        Invoke-ODNagPrompt -Kind FirstLogin @common
        $events | Should -Be @('FirstLoginShown', 'FirstLoginSignedInElsewhere')
        Should -Invoke Get-ODHealthState -Times 0 -Exactly
        Should -Invoke Start-Process -Times 0 -Exactly
    }

    It 'Reauth closed after the state turned Healthy logs SignedInElsewhere and launches nothing' {
        $script:action = 'SignIn'
        Mock Get-ODHealthState { [pscustomobject]@{ State = 'Healthy' } }
        Invoke-ODNagPrompt -Kind Reauth @common
        $events | Should -Be @('ReauthShown', 'ReauthSignedInElsewhere')
        Should -Invoke Get-ODAccount -Times 0 -Exactly
        Should -Invoke Start-Process -Times 0 -Exactly
    }
}
