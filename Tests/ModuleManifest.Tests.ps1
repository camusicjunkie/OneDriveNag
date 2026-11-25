Describe 'Module manifest' {
    BeforeAll {
        $source = Join-Path $PSScriptRoot '..\Source'
        $manifest = Import-PowerShellDataFile (Join-Path $source 'OneDriveNag.psd1')
        $script:exported = $manifest.FunctionsToExport
        $script:public = (Get-ChildItem (Join-Path $source 'Public') -Filter *.ps1).BaseName
        $script:expected = 'Invoke-ODNagRun', 'New-ODNagLogger'
    }

    It 'exports every function in Source/Public' {
        $missing = $script:public | Where-Object { $_ -notin $script:exported }
        $missing | Should -BeNullOrEmpty
    }

    It 'exports nothing that has no file in Source/Public' {
        $stale = $script:exported | Where-Object { $_ -notin $script:public }
        $stale | Should -BeNullOrEmpty
    }

    It 'exports exactly Invoke-ODNagRun and New-ODNagLogger' {
        $script:exported | Sort-Object | Should -Be ($script:expected | Sort-Object)
    }

    It 'holds only those two functions in Source/Public' {
        $script:public | Sort-Object | Should -Be ($script:expected | Sort-Object)
    }

    It 'is version 0.2.0' {
        $manifest = Import-PowerShellDataFile (Join-Path $PSScriptRoot '..\Source\OneDriveNag.psd1')
        $manifest.ModuleVersion | Should -Be '0.2.0'
    }
}
