# OneDriveNag

## Build

The module is laid out as source under `Source/` and assembled with
[ModuleBuilder](https://github.com/PoshCode/ModuleBuilder); `Source/build.psd1` is the build
configuration and the output lands in `build/` (gitignored).

```powershell
Build-Module -SourcePath ./Source/build.psd1
```

Each function lives in its own file under `Source/Public/`, named after the function. The build
joins them into `OneDriveNag.psm1`. A new public function also goes in `FunctionsToExport` in
`Source/OneDriveNag.psd1`; `Tests/ModuleManifest.Tests.ps1` fails when the two disagree. Helpers that should
not be exported go in `Source/Private/`. `Invoke-OneDriveNag.ps1`, `OneDrivePrompt.xaml` and
`Register-OneDriveNagSource.ps1` are copied into the output as they are (`CopyPaths`).

## Test

See the Test section of `README.md`. CI runs the tests, PSScriptAnalyzer and the build on every PR.

## Conventions

- Every module function takes its input only through its parameters. No `$script:` variables;
  the module keeps no state. The entry script holds the defaults and passes them in.
- Nothing writes to the console. The task runs hidden and non-interactively, so log to the event
  log with `Write-ODNagEvent` instead of `Write-Host`, `Write-Warning` or `Write-Verbose`. Events are
  defined once, in the table returned by `Source/Private/Get-ODNagEventTable.ps1`. A new event goes
  in that table and in the event table in `README.md`. Functions log through the logger from
  `New-ODNagLogger`, never through a log source or path parameter.
- Everything runs in the logged-on user's session: the StorageProviderStatusUI API that
  ODSyncUtil uses is per-user and session-bound, and the WPF prompt needs an interactive desktop.

## Agent skills

### Issue tracker

Issues live in this repo's GitHub Issues, managed with the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Uses the five default labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
