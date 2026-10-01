function Show-ODNagDialog {
    <#
    .SYNOPSIS
        Shows the WPF prompt and returns the action taken: SignIn, Later, TimedOut, or Dismissed.
    .DESCRIPTION
        The button handlers only record the choice and close the window. The caller
        acts on the choice after the window is gone, so a failed OneDrive launch isn't
        silently swallowed inside a WPF event handler. The timeout stops a prompt
        left open in a disconnected session from blocking every later run.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # Path to the WPF XAML file for the prompt window
        [Parameter(Mandatory)]
        [string] $XamlPath,

        # Email/UPN to display in the "Sign in as" field
        [Parameter(Mandatory)]
        [string] $UserEmail,

        # Header title text
        [string] $Title = 'Sign in to OneDrive',

        # Body message text
        [string] $Message = 'Please sign in to OneDrive with your CAC.',

        # Minutes before the prompt closes itself; 0 disables the timeout
        [int] $TimeoutMinutes = 30
    )

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    [xml]$xaml = Get-Content -Path $XamlPath -Raw
    $window = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($xaml))

    ($window.FindName('TitleText')).Text   = $Title
    ($window.FindName('MessageText')).Text = $Message
    ($window.FindName('EmailText')).Text   = $UserEmail

    # The handlers record the user's choice in Tag; Alt+F4 leaves it as Dismissed
    $window.Tag = 'Dismissed'

    $window.Add_MouseLeftButtonDown({ try { $window.DragMove() } catch { } })

    # Topmost in the XAML brings the prompt in front once; drop it after that so the prompt
    # doesn't stay pinned above OneDrive's own sign-in window
    $window.Add_ContentRendered({ $null = $window.Activate(); $window.Topmost = $false })
    ($window.FindName('SignInButton')).Add_Click({ $window.Tag = 'SignIn'; $window.Close() })
    ($window.FindName('LaterButton')).Add_Click({ $window.Tag = 'Later'; $window.Close() })

    $timer = $null
    if ($TimeoutMinutes -gt 0) {
        $timer = [System.Windows.Threading.DispatcherTimer]::new()
        $timer.Interval = [timespan]::FromMinutes($TimeoutMinutes)
        $timer.Add_Tick({ $timer.Stop(); $window.Tag = 'TimedOut'; $window.Close() })
        $timer.Start()
    }

    $null = $window.ShowDialog()
    if ($null -ne $timer) { $timer.Stop() }

    return [string]$window.Tag
}
