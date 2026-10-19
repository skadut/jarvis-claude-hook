# Install

## Requirements

- Windows 10 or 11
- PowerShell 5.1 (ships with Windows) or newer
- Claude Code

macOS and Linux are **not supported**. The scripts use Windows-only APIs
(WinRT toasts, `winmm.dll`, `System.Windows.Forms`).

## Per terminal

### PowerShell

```powershell
git clone https://github.com/skadut/claude-code-notification
cd claude-code-notification
.\install.ps1
.\config.ps1
```

If PowerShell says *running scripts is disabled on this system*, Windows is
blocking unsigned scripts. Run each one with a bypass instead:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
powershell -ExecutionPolicy Bypass -File .\config.ps1
```

See [Troubleshooting](troubleshooting.md#running-scripts-is-disabled-on-this-system)
for other fixes. The installed hook runs with a bypass of its own, so it works
whatever your policy is.

### Git Bash

```bash
git clone https://github.com/skadut/claude-code-notification
cd claude-code-notification
powershell -ExecutionPolicy Bypass -File ./install.ps1
powershell -ExecutionPolicy Bypass -File ./config.ps1
```

### Windows CMD

```cmd
git clone https://github.com/skadut/claude-code-notification
cd claude-code-notification
powershell -ExecutionPolicy Bypass -File install.ps1
powershell -ExecutionPolicy Bypass -File config.ps1
```

Restart Claude Code so it reloads `settings.json`.

## What gets written

| Path | Purpose |
|---|---|
| `%USERPROFILE%\.claude\hooks\cc-notif.ps1` | The hook script |
| `%USERPROFILE%\.claude\hooks\cc-notif-common.ps1` | Shared helpers used by the hook |
| `%USERPROFILE%\.claude\hooks\cc-notif-config.json` | Your settings |
| `%USERPROFILE%\.claude\settings.json` | Three hook entries: `Stop`, `Notification`, `PreToolUse` (matcher `Agent|Task`) |
| `HKCU:\Software\Classes\AppUserModelId\ClaudeCode.Notify` | Toast app ID; Windows 11 hides toasts from unregistered IDs |

Installing is safe to repeat. Existing hooks from other tools are **appended
to, never replaced**, and an existing config file is left untouched.

## Upgrading from an older version

Just run `.\install.ps1` again. It:

- Overwrites `cc-notif.ps1` with the current version
- Keeps your existing config, so your message and sound survive
- Adds the `Notification` and `PreToolUse` hooks without touching your other hooks
- Removes the old per-subagent `SubagentStop` hook from earlier versions
- Migrates a legacy `cc-notif-config.ps1` to JSON, renaming the old file `.bak`

Your config will lack the newer fields until you run `.\config.ps1`. Until
then, defaults apply, and `askSound` and `subagentSound` fall back to `sound`.

## Manual setup

If you prefer not to run `install.ps1`:

1. Copy `notify.ps1` to `%USERPROFILE%\.claude\hooks\cc-notif.ps1`
2. Copy `hook-common.ps1` to `%USERPROFILE%\.claude\hooks\cc-notif-common.ps1`
3. Copy `config.example.json` to `%USERPROFILE%\.claude\hooks\cc-notif-config.json`
4. Add to `%USERPROFILE%\.claude\settings.json` (add a `PreToolUse`
   entry with `"matcher": "Agent|Task"` and `-HookEvent AgentStart` for agent-start toasts):

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"$env:USERPROFILE\\.claude\\hooks\\cc-notif.ps1\" -HookEvent Stop",
            "shell": "powershell",
            "async": true
          }
        ]
      }
    ],
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"$env:USERPROFILE\\.claude\\hooks\\cc-notif.ps1\" -HookEvent Notification",
            "shell": "powershell",
            "async": true
          }
        ]
      }
    ]
  }
}
```

## Uninstall

```powershell
.\uninstall.ps1
```

The script asks which mode to run:

| Mode | Result |
|---|---|
| `1` Reset | Removes every hook in your user `settings.json` after you type `RESET`. Script files, plugin hooks, and managed hooks are kept. |
| `2` This project | Removes only this project's hook entries and files. Other hooks are kept, even in the same group. |

Skip the menu with `-Mode 1` or `-Mode 2`. Both modes back up `settings.json`
before saving. Mode 2 also backs up your config as
`cc-notif-config.json.bak-<id>` before deleting it.

Mode 2 still cleans the installed files when `settings.json` does not exist.
If `settings.json` is not valid JSON, the script stops and changes nothing.

## Verify

```powershell
.\verify.ps1
.\verify.ps1 -Expect Installed
.\verify.ps1 -Expect ProjectRemoved
.\verify.ps1 -Expect GlobalHooksReset
```

`verify.ps1` only reads. It reports which project events are registered, which
files are installed, and whether the config is valid. With `-Expect`, it exits
with code `1` when the state does not match. `GlobalHooksReset` allows script
files to remain; `ProjectRemoved` allows other hooks to remain.

Both scripts only cover your own user settings, not project settings, plugin
hooks, managed policy, or other Windows accounts.

## Tests

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\run-tests.ps1
powershell -ExecutionPolicy Bypass -File .\tests\functional-test.ps1
powershell -ExecutionPolicy Bypass -File .\tests\functional-test.ps1 -Speak
```

`run-tests.ps1` checks every install, uninstall, verify, formatting, and speech
lock case. `functional-test.ps1` installs into a temporary profile, fires each
event through the installed hook, and uninstalls. It shows real toasts on screen.
Add `-Speak` to also play two overlapping spoken recaps. Neither script reads or
changes your real `settings.json`.
