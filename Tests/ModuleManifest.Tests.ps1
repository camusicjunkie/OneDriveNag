Describe 'Module manifest' {
    BeforeAll {
        $source = Join-Path $PSScriptRoot '..\Source'
        $manifest = Import-PowerShellDataFile (Join-Path $source 'OneDriveNag.psd1')
        $script:exported = $manifest.FunctionsToExport
        $script:public = (Get-ChildItem (Join-Path $source 'Public') -Filter *.ps1).BaseName
    }

    It 'exports every function in Source/Public' {
        $missing = $script:public | Where-Object { $_ -notin $script:exported }
        $missing | Should -BeNullOrEmpty
    }

    It 'exports nothing that has no file in Source/Public' {
        $stale = $script:exported | Where-Object { $_ -notin $script:public }
        $stale | Should -BeNullOrEmpty
    }
}
