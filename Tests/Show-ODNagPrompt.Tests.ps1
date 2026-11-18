BeforeAll {
    . (Join-Path $PSScriptRoot '..\Source\Private\Get-ODPromptProfile.ps1')
    . (Join-Path $PSScriptRoot '..\Source\Public\Show-ODNagDialog.ps1')
    . (Join-Path $PSScriptRoot '..\Source\Public\Show-ODNagPrompt.ps1')
}

Describe 'Show-ODNagPrompt' {
    BeforeEach {
        $script:seen = $null
        Mock Show-ODNagDialog {
            $script:seen = @{ Title = $Title; Message = $Message; UserEmail = $UserEmail; TimeoutMinutes = $TimeoutMinutes; XamlPath = $XamlPath }
            'Later'
        }
    }

    It 'passes the <Kind> profile text to the dialog and returns its action' -ForEach @(
        @{ Kind = 'FirstLogin'; WantTitle = 'Sign in to OneDrive'; WantMessage = 'Your files are moving to OneDrive. Please sign in now so your Desktop and Documents back up automatically. It takes about 20 seconds with your CAC.' }
        @{ Kind = 'Reauth'; WantTitle = 'Sign back in to OneDrive'; WantMessage = 'Your OneDrive session has expired and your files have stopped backing up. Please sign in again with your CAC to resume syncing.' }
    ) {
        $action = Show-ODNagPrompt -Kind $Kind -XamlPath 'x.xaml' -UserEmail 'a@b.mil' -TimeoutMinutes 5
        $action | Should -Be 'Later'
        Should -Invoke Show-ODNagDialog -Times 1 -Exactly
        $script:seen.Title | Should -Be $WantTitle
        $script:seen.Message | Should -Be $WantMessage
        $script:seen.UserEmail | Should -Be 'a@b.mil'
        $script:seen.TimeoutMinutes | Should -Be 5
        $script:seen.XamlPath | Should -Be 'x.xaml'
    }
}
