BeforeAll {
    $source = Join-Path $PSScriptRoot '..\Source'
    . (Join-Path $source 'Private\Find-ODDirectoryUser.ps1')
    . (Join-Path $source 'Public\Write-ODNagEvent.ps1')
    . (Join-Path $source 'Public\New-ODNagLogger.ps1')
    . (Join-Path $source 'Public\Get-ODAccount.ps1')

    $script:origUser = $env:USERNAME
    $script:common = @{ AccountKeyPath = 'HKCU:\fake'; Logger = (New-ODNagLogger -LogSource 'src' -FallbackLogPath 'x.log') }
}

Describe 'Get-ODAccount' {
    BeforeEach { Mock Write-ODNagEvent {} }
    AfterEach { $env:USERNAME = $script:origUser }

    It 'is configured with an email and no expected tenant' {
        Mock Get-ItemProperty { [pscustomobject]@{ UserEmail = 'a@b.com'; ConfiguredTenantId = 't1' } }
        $r = Get-ODAccount @common
        $r.Configured | Should -BeTrue
        $r.Email | Should -Be 'a@b.com'
        $r.TenantMatch | Should -BeTrue
    }
    It 'is not configured on a tenant mismatch but still returns the email' {
        Mock Get-ItemProperty { [pscustomobject]@{ UserEmail = 'a@b.com'; ConfiguredTenantId = 't1' } }
        $r = Get-ODAccount @common -ExpectedTenantId 't2'
        $r.Configured | Should -BeFalse
        $r.TenantMatch | Should -BeFalse
        $r.Email | Should -Be 'a@b.com'
    }
    It 'is configured when the tenant matches' {
        Mock Get-ItemProperty { [pscustomobject]@{ UserEmail = 'a@b.com'; ConfiguredTenantId = 't1' } }
        (Get-ODAccount @common -ExpectedTenantId 't1').Configured | Should -BeTrue
    }
    It 'is not configured with an empty email' {
        Mock Get-ItemProperty { [pscustomobject]@{ UserEmail = ''; ConfiguredTenantId = 't1' } }
        Mock Find-ODDirectoryUser { $null }
        (Get-ODAccount @common).Configured | Should -BeFalse
    }
    It 'logs 1012 and falls back to the logon name when the lookup finds nothing' {
        Mock Get-ItemProperty { [pscustomobject]@{ UserEmail = ''; ConfiguredTenantId = '' } }
        Mock Find-ODDirectoryUser { $null }
        (Get-ODAccount @common).Email | Should -Be $env:USERNAME
        Should -Invoke Write-ODNagEvent -ParameterFilter { $Event -eq 'EmailLookupFailed' } -Times 1 -Exactly
    }
    It 'logs 1012 and falls back to the logon name when the lookup throws' {
        Mock Get-ItemProperty { [pscustomobject]@{ UserEmail = ''; ConfiguredTenantId = '' } }
        Mock Find-ODDirectoryUser { throw 'unreachable' }
        (Get-ODAccount @common).Email | Should -Be $env:USERNAME
        Should -Invoke Write-ODNagEvent -ParameterFilter { $Event -eq 'EmailLookupFailed' } -Times 1 -Exactly
    }
    It 'uses the directory mail when the key has no email' {
        Mock Get-ItemProperty { [pscustomobject]@{ UserEmail = ''; ConfiguredTenantId = '' } }
        Mock Find-ODDirectoryUser { [pscustomobject]@{ Mail = 'dir@b.com'; UserPrincipalName = 'upn@b.com' } }
        (Get-ODAccount @common).Email | Should -Be 'dir@b.com'
        Should -Invoke Write-ODNagEvent -Times 0 -Exactly
    }
    It 'escapes LDAP special characters in the filter' {
        Mock Get-ItemProperty { [pscustomobject]@{ UserEmail = ''; ConfiguredTenantId = '' } }
        Mock Find-ODDirectoryUser { $null }
        $env:USERNAME = 'a*(b)\c'
        $null = Get-ODAccount @common
        Should -Invoke Find-ODDirectoryUser -ParameterFilter {
            $Filter -eq '(&(objectCategory=user)(sAMAccountName=a\2a\28b\29\5cc))'
        } -Times 1 -Exactly
    }
    It 'with -SkipDirectoryLookup does no lookup and logs no 1012 but still reports Configured' {
        Mock Get-ItemProperty { [pscustomobject]@{ UserEmail = ''; ConfiguredTenantId = '' } }
        Mock Find-ODDirectoryUser { throw 'must not be called' }
        $r = Get-ODAccount @common -SkipDirectoryLookup
        $r.Configured | Should -BeFalse
        Should -Invoke Find-ODDirectoryUser -Times 0 -Exactly
        Should -Invoke Write-ODNagEvent -Times 0 -Exactly
    }
    It 'with -SkipDirectoryLookup is configured when the key has an email' {
        Mock Get-ItemProperty { [pscustomobject]@{ UserEmail = 'a@b.com'; ConfiguredTenantId = '' } }
        (Get-ODAccount @common -SkipDirectoryLookup).Configured | Should -BeTrue
    }}
