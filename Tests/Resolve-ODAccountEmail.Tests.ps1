BeforeAll {
    $source = Join-Path $PSScriptRoot '..\Source'
    . (Join-Path $source 'Private\Find-ODDirectoryUser.ps1')
    . (Join-Path $source 'Public\Write-ODNagEvent.ps1')
    . (Join-Path $source 'Public\New-ODNagLogger.ps1')
    . (Join-Path $source 'Public\Resolve-ODAccountEmail.ps1')

    $script:origUser = $env:USERNAME
    $script:logger = New-ODNagLogger -LogSource 'src' -FallbackLogPath 'x.log'
}

Describe 'Resolve-ODAccountEmail' {
    BeforeEach { Mock Write-ODNagEvent {} }
    AfterEach { $env:USERNAME = $script:origUser }

    It 'returns the registry email without a lookup or event' {
        Mock Find-ODDirectoryUser { throw 'must not be called' }
        Resolve-ODAccountEmail -RegistryEmail 'a@b.com' -Logger $logger | Should -Be 'a@b.com'
        Should -Invoke Find-ODDirectoryUser -Times 0 -Exactly
        Should -Invoke Write-ODNagEvent -Times 0 -Exactly
    }
    It 'logs 1012 and falls back to the logon name when the lookup finds nothing' {
        Mock Find-ODDirectoryUser { $null }
        Resolve-ODAccountEmail -Logger $logger | Should -Be $env:USERNAME
        Should -Invoke Write-ODNagEvent -ParameterFilter { $Event -eq 'EmailLookupFailed' } -Times 1 -Exactly
    }
    It 'logs 1012 and falls back to the logon name when the lookup throws' {
        Mock Find-ODDirectoryUser { throw 'unreachable' }
        Resolve-ODAccountEmail -RegistryEmail '' -Logger $logger | Should -Be $env:USERNAME
        Should -Invoke Write-ODNagEvent -ParameterFilter { $Event -eq 'EmailLookupFailed' } -Times 1 -Exactly
    }
    It 'uses the directory mail when the registry has no email' {
        Mock Find-ODDirectoryUser { [pscustomobject]@{ Mail = 'dir@b.com'; UserPrincipalName = 'upn@b.com' } }
        Resolve-ODAccountEmail -Logger $logger | Should -Be 'dir@b.com'
        Should -Invoke Write-ODNagEvent -Times 0 -Exactly
    }
    It 'uses the directory UPN when there is no mail' {
        Mock Find-ODDirectoryUser { [pscustomobject]@{ Mail = ''; UserPrincipalName = 'upn@b.com' } }
        Resolve-ODAccountEmail -Logger $logger | Should -Be 'upn@b.com'
        Should -Invoke Write-ODNagEvent -Times 0 -Exactly
    }
    It 'escapes LDAP special characters in the filter' {
        Mock Find-ODDirectoryUser { $null }
        $env:USERNAME = 'a*(b)\c'
        $null = Resolve-ODAccountEmail -Logger $logger
        Should -Invoke Find-ODDirectoryUser -ParameterFilter {
            $Filter -eq '(&(objectCategory=user)(sAMAccountName=a\2a\28b\29\5cc))'
        } -Times 1 -Exactly
    }
}
