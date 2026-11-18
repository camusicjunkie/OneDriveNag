function Get-ODPromptProfile {
    <#
    .SYNOPSIS
        Returns the title and message shown for a prompt kind.
    .DESCRIPTION
        The one place the prompt text is defined. The XAML holds layout only.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        # Which prompt to show
        [Parameter(Mandatory)]
        [ValidateSet('FirstLogin', 'Reauth')]
        [string] $Kind
    )

    $profiles = @{
        FirstLogin = @{
            Title   = 'Sign in to OneDrive'
            Message = 'Your files are moving to OneDrive. Please sign in now so your Desktop and Documents back up automatically. It takes about 20 seconds with your CAC.'
        }
        Reauth     = @{
            Title   = 'Sign back in to OneDrive'
            Message = 'Your OneDrive session has expired and your files have stopped backing up. Please sign in again with your CAC to resume syncing.'
        }
    }
    $profiles[$Kind]
}
