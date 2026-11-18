BeforeAll {
    $source = Join-Path $PSScriptRoot '..\Source'
    . (Join-Path $source 'Private\Invoke-ODSyncUtil.ps1')
    . (Join-Path $source 'Public\Get-ODHealthState.ps1')

    function New-Root($Name, $Num, $Text, $Label) {
        [pscustomobject]@{ ServiceName = $Name; CurrentState = $Num; CurrentStateString = $Text; Label = $Label }
    }
    function ConvertTo-RootJson($Roots) {
        if ($null -eq $Roots) { return '' }
        ConvertTo-Json -InputObject @($Roots) -Depth 3 -Compress
    }
}

Describe 'Get-ODHealthState' {
    It 'returns Unknown for the closed-client fixture' {
        $json = ConvertTo-RootJson (New-Root 'Personal' 5 'Unknown (5)' 'Start OneDrive')
        Mock Invoke-ODSyncUtil { [pscustomobject]@{ Output = $json; ExitCode = 0 } }
        (Get-ODHealthState -ExePath 'x.exe').State | Should -Be 'Unknown'
    }
    It 'returns Unknown with the exit code on a non-zero exit with empty output' {
        Mock Invoke-ODSyncUtil { [pscustomobject]@{ Output = ''; ExitCode = 3 } }
        $r = Get-ODHealthState -ExePath 'x.exe'
        $r.State | Should -Be 'Unknown'
        $r.Detail | Should -Match '3'
    }
    It 'returns NotSignedIn for exit 0 with no roots' {
        Mock Invoke-ODSyncUtil { [pscustomobject]@{ Output = ''; ExitCode = 0 } }
        (Get-ODHealthState -ExePath 'x.exe').State | Should -Be 'NotSignedIn'
    }
    It 'returns Healthy for a root labelled Signed in' {
        $json = ConvertTo-RootJson (New-Root 'Business1' 0 'Up to date' 'Signed in')
        Mock Invoke-ODSyncUtil { [pscustomobject]@{ Output = $json; ExitCode = 0 } }
        (Get-ODHealthState -ExePath 'x.exe').State | Should -Be 'Healthy'
    }
    It 'returns NeedsReauth when sign-in is required' {
        $json = ConvertTo-RootJson (New-Root 'Business1' 9 'Sign in required' 'Sign in')
        Mock Invoke-ODSyncUtil { [pscustomobject]@{ Output = $json; ExitCode = 0 } }
        (Get-ODHealthState -ExePath 'x.exe').State | Should -Be 'NeedsReauth'
    }
    It 'returns Degraded when one of two roots errors' {
        $json = ConvertTo-RootJson @(
            (New-Root 'Personal' 0 'Up to date' 'Signed in'),
            (New-Root 'Business1' 7 'Error' 'Signed in'))
        Mock Invoke-ODSyncUtil { [pscustomobject]@{ Output = $json; ExitCode = 0 } }
        (Get-ODHealthState -ExePath 'x.exe').State | Should -Be 'Degraded'
    }
    It 'lets NeedsReauth win over Degraded across roots' {
        $json = ConvertTo-RootJson @(
            (New-Root 'Personal' 7 'Error' 'x'),
            (New-Root 'Business1' 9 'Signed out' 'x'))
        Mock Invoke-ODSyncUtil { [pscustomobject]@{ Output = $json; ExitCode = 0 } }
        (Get-ODHealthState -ExePath 'x.exe').State | Should -Be 'NeedsReauth'
    }
    It 'treats a single-object JSON result as one root' {
        Mock Invoke-ODSyncUtil {
            [pscustomobject]@{ ExitCode = 0; Output = '{"ServiceName":"Personal","CurrentState":0,"CurrentStateString":"Up to date","Label":"Signed in"}' }
        }
        (Get-ODHealthState -ExePath 'x.exe').State | Should -Be 'Healthy'
    }
    It 'includes service name and numeric state in Detail' {
        $json = ConvertTo-RootJson (New-Root 'Personal' 5 'Unknown (5)' 'Start OneDrive')
        Mock Invoke-ODSyncUtil { [pscustomobject]@{ Output = $json; ExitCode = 0 } }
        $d = (Get-ODHealthState -ExePath 'x.exe').Detail
        $d | Should -Match 'Personal'
        $d | Should -Match '5'
    }
    It 'caps Detail at 500 characters' {
        $json = ConvertTo-RootJson @(1..40 | ForEach-Object { New-Root "Service$_" 0 ('ok' * 20) 'Signed in' })
        Mock Invoke-ODSyncUtil { [pscustomobject]@{ Output = $json; ExitCode = 0 } }
        (Get-ODHealthState -ExePath 'x.exe').Detail.Length | Should -BeLessOrEqual 500
    }
    It 'does not match patterns against ServiceName' {
        $json = ConvertTo-RootJson (New-Root 'AuthService' 0 'Up to date' 'Signed in')
        Mock Invoke-ODSyncUtil { [pscustomobject]@{ Output = $json; ExitCode = 0 } }
        (Get-ODHealthState -ExePath 'x.exe').State | Should -Be 'Healthy'
    }
}
