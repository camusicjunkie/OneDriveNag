Describe 'Built module' {
    BeforeAll {
        $script:builder = Get-Module -ListAvailable -Name ModuleBuilder | Select-Object -First 1
        if ($script:builder) {
            $repo = Split-Path $PSScriptRoot -Parent
            $script:out = Join-Path ([IO.Path]::GetTempPath()) "ODNagBuild-$([guid]::NewGuid())"
            Push-Location $repo
            try {
                Build-Module -SourcePath ./Source/build.psd1 -OutputDirectory $script:out
            }
            finally { Pop-Location }
            $script:manifest = Get-ChildItem $script:out -Recurse -Filter OneDriveNag.psd1 | Select-Object -First 1
            Import-Module $script:manifest.FullName -Force
        }
    }

    AfterAll {
        Remove-Module OneDriveNag -Force -ErrorAction SilentlyContinue
        if ($script:out) { Remove-Item $script:out -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'exports exactly Invoke-ODNagRun and New-ODNagLogger' -Skip:(-not (Get-Module -ListAvailable -Name ModuleBuilder)) {
        @((Get-Command -Module OneDriveNag).Name) | Sort-Object | Should -Be @('Invoke-ODNagRun', 'New-ODNagLogger')
    }

    It 'is version 0.2.0' -Skip:(-not (Get-Module -ListAvailable -Name ModuleBuilder)) {
        (Get-Module OneDriveNag).Version | Should -Be ([version]'0.2.0')
    }
}
