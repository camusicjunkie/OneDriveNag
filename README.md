# OneDriveNag

Prompts users to sign in to OneDrive, or to sign back in when their token expires, and logs each step to the Application event log for Splunk.

It runs in each user's own session from a scheduled task. It works the same on physical machines and Citrix VDI, and needs no image change.

## Build

The source lives under `Source/` and is assembled with [ModuleBuilder](https://github.com/PoshCode/ModuleBuilder). `Source/build.psd1` is the build configuration.

```powershell
Build-Module -SourcePath ./Source/build.psd1
```

The output lands in `build/OneDriveNag/<version>/` (gitignored). That folder is what you deploy.

| Path | Purpose |
|---|---|
| `Source/Public/` | One file per module function. The build joins them into `OneDriveNag.psm1` and exports them all. |
| `Source/OneDriveNag.psd1` | Module manifest. The build stamps the exported function list into the output copy. |
| `Source/Invoke-OneDriveNag.ps1` | Entry point the scheduled task runs. Checks OneDrive state, shows the prompt, and logs events. |
| `Source/OneDrivePrompt.xaml` | WPF layout for the prompt window. |
| `Source/Register-OneDriveNagSource.ps1` | Optional. Registers the event log source on one machine. The GPO below does the same job. |

The build copies the script, XAML and registration script next to the module, so the output folder holds everything except `ODSyncUtil.exe`. That binary reads per-user sync status; build it and add it to the deployed folder yourself (see [Things to check in a DoD build](#things-to-check-in-a-dod-build)).

## How it works

1. Each run holds a per-session mutex, so repeat triggers can't stack dialogs.
2. It waits up to 2 minutes for `OneDrive.exe` to start. A client that hasn't started yet would otherwise look signed out.
3. If no OneDrive Business account is configured, it shows the **first-login** prompt.
4. If an account is configured, it runs `ODSyncUtil.exe` and classifies the result:
   - **Healthy:** logged once each time the account recovers; no prompt.
   - **NeedsReauth** or **NotSignedIn:** shows the **re-auth** prompt.
   - **Degraded** (paused, blocked, full, error): logged; no prompt, because signing in won't fix it.
   - **Unknown** (client not running, or ODSyncUtil unavailable): logged; no prompt.
5. When the prompt closes, the state is checked again. If the user signed in through OneDrive's own window while the prompt was open, the button they clicked is ignored and event 1014 is logged.
6. Otherwise, if the user clicked **Sign in**, OneDrive is started. For re-auth it is restarted first, so it re-checks its token.
7. An unanswered prompt closes itself after 30 minutes and is logged as timed out.

The prompt opens in front of other windows but doesn't stay on top. If OneDrive's own sign-in window is open too, the user can bring it forward.

The script never writes to the console. If the event source isn't registered, events go to `%LOCALAPPDATA%\OneDriveAdoption\nag.log` instead.

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `-ModuleRoot` | Script folder | Folder holding the module, XAML, and `ODSyncUtil.exe`. |
| `-ClientWaitSeconds` | `120` | How long to wait for `OneDrive.exe` before checking state. |
| `-PromptTimeoutMinutes` | `30` | How long an unanswered prompt stays open. |
| `-ExpectedTenantId` | Empty | Entra tenant GUID the account must match. Empty skips the check. |
| `-AccountKeyPath` | `HKCU:\Software\Microsoft\OneDrive\Accounts\Business1` | Registry key for the OneDrive Business account. |
| `-LogSource` | `OneDriveAdoption` | Application log source. Must match the registered source. |
| `-FallbackLogPath` | `%LOCALAPPDATA%\OneDriveAdoption\nag.log` | File used when the event source isn't registered. |

## Deployment

Deploy everything through one GPO under **Computer Configuration**, using Group Policy Preferences. Don't use a user logon script: it runs only once per logon, and users would need write access to wherever the files go.

### 1. Files (Preferences → Windows Settings → Files)

- **Action:** Update
- **Source:** `\\<domain>\NETLOGON\OneDriveNag\*`, or a DFS share Domain Computers can read. Put the contents of `build/OneDriveNag/<version>/` there, plus `ODSyncUtil.exe`.
- **Destination:** `C:\Program Files\OneDriveNag`

The item runs as SYSTEM, so users can read the files but not change them.

### 2. Event source (Preferences → Windows Settings → Registry)

- **Key:** `HKLM\SYSTEM\CurrentControlSet\Services\EventLog\Application\OneDriveAdoption`
- **Value:** `EventMessageFile` (REG_EXPAND_SZ) = `%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\EventLogMessages.dll`

This is the same value `New-EventLog` writes, so it replaces `Register-OneDriveNagSource.ps1`.

### 3. Scheduled task (Preferences → Control Panel Settings → Scheduled Tasks → Scheduled Task (At least Windows 7))

- **Run as:** `BUILTIN\Users`, with **Run only when user is logged on**. The task then runs in each user's own session, which ODSyncUtil requires.
- **Triggers:**
  - At log on, any user, 2-minute delay, repeat every 2 hours indefinitely. The repeat catches the roughly weekly DISA token expiry mid-session.
  - On connection to user session (Citrix reconnects).
  - On workstation unlock (physical machines).
- **Settings:** Do not start a new instance; stop if it runs longer than 1 hour.
- **Action:**

  ```
  powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Program Files\OneDriveNag\Invoke-OneDriveNag.ps1"
  ```

### 4. Item-level targeting

Target the Files and Scheduled Task items at Windows 11. Start with a pilot security group.

## Things to check in a DoD build

- **Execution policy:** An AllSigned policy set by GPO overrides `-ExecutionPolicy Bypass`. Sign `Invoke-OneDriveNag.ps1`, `OneDriveNag.psm1`, and `OneDriveNag.psd1` in the build output with your code-signing certificate. Sign after building: the build rewrites the `.psm1` and `.psd1`, which breaks any signature on the source copies.
- **WDAC/AppLocker:** These run unsigned scripts in Constrained Language Mode. CLM blocks `Add-Type` and `XamlReader`, so the dialog silently fails to render.
- **ODSyncUtil.exe:** It's an unsigned binary from GitHub. Build it from source in GitLab, sign it, and allow it in WDAC.
- **First boot:** Startup policy processing is asynchronous, so the files may arrive after the first logon. The task's delay and repeat triggers handle this; an early run fails and the next one retries.
- **Console flash:** `-WindowStyle Hidden` still flashes a console briefly. On Windows 11, running the command as `conhost.exe --headless powershell.exe …` usually hides it. Test before you rely on it.

## Event IDs

All events use source `OneDriveAdoption` in the Application log. The message is JSON.

| ID | Meaning |
|---|---|
| 1000 / 1001 / 1002 / 1004 | First-login prompt shown / acted / deferred / timed out or dismissed |
| 1005 / 1006 / 1007 / 1008 | Re-auth prompt shown / acted / deferred / timed out or dismissed |
| 1003 | Healthy (logged once each time the account recovers) |
| 1010 | Unknown: client not running, or ODSyncUtil unavailable; no prompt |
| 1011 | Degraded: a problem signing in won't fix; no prompt |
| 1012 | AD email lookup failed; the logon name was used instead (warning) |
| 1013 | `OneDrive.exe` not found when the user clicked Sign in (error) |
| 1014 | Signed in through OneDrive's own window while the prompt was open; no action taken. `stage` says which prompt, `action` says how it closed |

Every event includes `stage`, `user`, `computer`, `sid`, and `session`. Status events also include `upn`, `clientRunning`, `syncState`, and `syncDetail`, where `syncDetail` is the raw ODSyncUtil state text.

### Splunk

Current state per user:

```
index=wineventlog SourceName=OneDriveAdoption
| spath input=Message
| stats latest(stage) as stage latest(syncState) as syncState latest(_time) as lastSeen by upn
```

## Pilot checklist

- [ ] **Tune `AuthPattern`.** Run the pilot for a week, then check what `syncDetail` actually says when a token has expired. Don't trust the NeedsReauth match until then. Degraded and Unknown events show where the classifier is guessing.
- [ ] **Check the re-check after re-auth.** Right after a sign-in, ODSyncUtil may still report the old auth state, so the check after the prompt misses it and "Sign in now" restarts OneDrive anyway. If 1006 events are often followed shortly by 1003 for the same user, add a short delay before the check.
- [ ] **Confirm `Start-ODClient -Restart`.** Check that it brings up the sign-in window for an expired token on your OneDrive build.
- [ ] **Confirm FullLanguage mode.** Check that your WDAC/AppLocker policy runs the signed scripts in FullLanguage mode. If they drop to Constrained Language, you'll see Shown events with no Acted or Deferred event after them.
