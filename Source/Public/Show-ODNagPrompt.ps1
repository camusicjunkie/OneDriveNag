function Show-ODNagPrompt {
    <#
    .SYNOPSIS
        Shows the prompt for a kind (FirstLogin or Reauth) and returns the action taken.
    .DESCRIPTION
        Looks up the kind's title and message and hands them to Show-ODNagDialog, which
        stays WPF-only. Returns SignIn, Later, TimedOut, or Dismissed.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # Which prompt to show
        [Parameter(Mandatory)]
        [ValidateSet('FirstLogin', 'Reauth')]
        [string] $Kind,

        # Path to the WPF XAML file for the prompt window
        [Parameter(Mandatory)]
        [string] $XamlPath,

        # Email/UPN to display in the "Sign in as" field
        [Parameter(Mandatory)]
        [string] $UserEmail,

        # Minutes before the prompt closes itself; 0 disables the timeout
        [int] $TimeoutMinutes = 30
    )

    $promptProfile = Get-ODPromptProfile -Kind $Kind
    Show-ODNagDialog -XamlPath $XamlPath -UserEmail $UserEmail `
        -Title $promptProfile.Title -Message $promptProfile.Message -TimeoutMinutes $TimeoutMinutes
}
