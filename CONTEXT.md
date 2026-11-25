# OneDriveNag

Prompts a user to sign in to OneDrive, or back in when the token expires, and logs each step to the Application event log. This file fixes the words contributors and agents use. Event IDs are in `README.md`.

## Language

**Run**:
One invocation of the entry script in a session, from reading the account and client state to the last event logged. At most one run is active per session.

**Prompt kind**:
Which prompt the user sees: `FirstLogin` or `Reauth`. It selects the prompt text and the event IDs.
- `FirstLogin`: no OneDrive Business account is configured. Events 1000 (shown), 1001 (acted), 1002 (deferred), 1004 (timed out or dismissed).
- `Reauth`: an account is configured but its sign-in has expired or is missing. Events 1005, 1006, 1007, 1008, in the same order.

**Health state**:
The classification of a configured account's sync status. It decides whether to prompt. Health state applies only after an account is configured and the client is running; the first-login check comes before it.

| Health state | Meaning | Prompts | Logs |
|---|---|---|---|
| `Healthy` | Sync roots reported and no auth or problem text. | No | 1003, once per recovery (see **Marker**) |
| `NeedsReauth` | State text matches `AuthPattern`: the token expired. | Yes, `Reauth` | 1005 and its outcome events |
| `NotSignedIn` | ODSyncUtil reports no sync roots. | Yes, `Reauth` | 1005 and its outcome events |
| `Degraded` | State text matches `DegradedPattern` (error, paused, blocked, full). Signing in won't fix it. | No | 1011 (warning) |
| `Unknown` | No reliable status: the client is not running, ODSyncUtil is unavailable, or the client reports a closed state. | No | 1010 |

**Marker**:
The file `%LOCALAPPDATA%\OneDriveAdoption\healthy.flag`. It makes event 1003 log once per recovery rather than on every run. A `Healthy` run with no marker logs 1003 and creates it. A `NeedsReauth`, `NotSignedIn` or `Degraded` run deletes it, so the next `Healthy` run logs the recovery. `Unknown` leaves it alone.

**Nag decision**:
What one run logs, shows and launches, given the account, the client and the health state.

| Situation | Logs | Shows | Launches |
|---|---|---|---|
| No account configured | 1000, then 1001, 1002 or 1004 | `FirstLogin` prompt | OneDrive, if the user chose Sign in |
| Account configured, client not running | 1010 | Nothing | Nothing |
| `Healthy` | 1003 if no marker | Nothing | Nothing |
| `NeedsReauth` or `NotSignedIn` | 1005, then 1006, 1007 or 1008 | `Reauth` prompt | OneDrive restarted, if the user chose Sign in |
| `Degraded` | 1011 | Nothing | Nothing |
| `Unknown` | 1010 | Nothing | Nothing |

After any prompt closes, the state is checked again. If the user already signed in through OneDrive's own window, the run logs 1014 and launches nothing, whatever button was clicked. A missing `OneDrive.exe` when the user chose Sign in logs 1013.

## Findings

A closed OneDrive client reports one sync root whose state string has the form `Unknown (n)` and whose label is "Start OneDrive". It carries no auth or problem text, so it would pass for `Healthy` if only the patterns were checked. It is classified `Unknown`, not `Healthy`: the client is not syncing, so logging 1003 or setting the marker would be wrong.
