BeforeAll {
    $source = Join-Path $PSScriptRoot '..\Source'
    . (Join-Path $source 'Private\Find-ODDirectoryUser.ps1')
    . (Join-Path $source 'Private\Write-ODNagEvent.ps1')
    . (Join-Path $source 'Private\Get-ODAccount.ps1')

    $script:common = @{ AccountKeyPath = 'HKCU:\fake' }
}

Describe 'Get-ODAccount' {
    BeforeEach {
        Mock Write-ODNagEvent {}
        Mock Find-ODDirectoryUser { throw 'must not be called' }
    }

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
    It 'is not configured with an empty email and returns no email' {
        Mock Get-ItemProperty { [pscustomobject]@{ UserEmail = ''; ConfiguredTenantId = 't1' } }
        $r = Get-ODAccount @common
        $r.Configured | Should -BeFalse
        $r.Email | Should -BeNullOrEmpty
    }
    It 'is not configured when the key is missing' {
        Mock Get-ItemProperty { $null }
        (Get-ODAccount @common).Configured | Should -BeFalse
    }
    It 'never queries AD and never logs' {
        Mock Get-ItemProperty { [pscustomobject]@{ UserEmail = ''; ConfiguredTenantId = '' } }
        $null = Get-ODAccount @common
        Should -Invoke Find-ODDirectoryUser -Times 0 -Exactly
        Should -Invoke Write-ODNagEvent -Times 0 -Exactly
    }
    It 'has no -SkipDirectoryLookup or -Logger parameter' {
        (Get-Command Get-ODAccount).Parameters.Keys | Should -Not -Contain 'SkipDirectoryLookup'
        (Get-Command Get-ODAccount).Parameters.Keys | Should -Not -Contain 'Logger'
    }
}
