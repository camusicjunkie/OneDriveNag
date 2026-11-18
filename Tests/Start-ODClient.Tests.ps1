BeforeAll {
    $source = Join-Path $PSScriptRoot '..\Source'
    . (Join-Path $source 'Private\Get-ODClientPath.ps1')
    . (Join-Path $source 'Private\Test-ODClientRunning.ps1')
    . (Join-Path $source 'Public\Write-ODNagEvent.ps1')
    . (Join-Path $source 'Public\Start-ODClient.ps1')

    $script:log = @{ LogSource = 'T'; FallbackLogPath = 'x.log' }
}

Describe 'Start-ODClient' {
    BeforeEach {
        Mock Get-ODClientPath { 'C:\OneDrive.exe' }
        Mock Start-Process {}
        Mock Start-Sleep {}
        Mock Write-ODNagEvent {}
    }

    It '-Background on a running client returns true without starting or sleeping' {
        Mock Test-ODClientRunning { $true }
        Start-ODClient -Background @log | Should -BeTrue
        Should -Invoke Start-Process -Times 0 -Exactly
        Should -Invoke Start-Sleep -Times 0 -Exactly
    }

    It '-Background on a stopped client starts it hidden and settles once it appears' {
        $script:calls = 0
        Mock Test-ODClientRunning { $script:calls++; $script:calls -ge 3 }
        Start-ODClient -Background -SettleSeconds 30 @log | Should -BeTrue
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $ArgumentList -eq '/background' }
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 30 }
    }

    It '-Background returns false when the process never appears' {
        Mock Test-ODClientRunning { $false }
        Start-ODClient -Background -TimeoutSeconds 20 @log | Should -BeFalse
        Should -Invoke Start-Sleep -Times 0 -Exactly -ParameterFilter { $Seconds -eq 30 }
    }

    It '-Restart starts the new instance only after the old process has exited' {
        $script:calls = 0
        $script:order = [System.Collections.Generic.List[string]]::new()
        Mock Test-ODClientRunning { $script:calls++; $script:calls -le 3 }
        Mock Start-Process {
            $script:order.Add($(if ($ArgumentList -eq '/shutdown') { 'shutdown' } else { 'start' }))
        }
        Start-ODClient -Restart @log | Should -BeTrue
        $script:order -join ',' | Should -Be 'shutdown,start'
        $script:calls | Should -BeGreaterThan 3
    }

    It '-Restart starts anyway after 30 seconds if the old process never exits' {
        Mock Test-ODClientRunning { $true }
        Start-ODClient -Restart @log | Should -BeTrue
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { -not $ArgumentList }
    }

    It 'logs 1013 and starts nothing when OneDrive.exe is missing' {
        Mock Get-ODClientPath { $null }
        Mock Test-ODClientRunning { $false }
        Start-ODClient -Background @log | Should -BeFalse
        Start-ODClient -Restart @log | Should -BeFalse
        Should -Invoke Write-ODNagEvent -Times 2 -Exactly -ParameterFilter { $EventId -eq 1013 }
        Should -Invoke Start-Process -Times 0 -Exactly
    }
}
