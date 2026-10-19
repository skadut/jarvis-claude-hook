# Troubleshooting

## No notification at all

**Restart Claude Code.** `settings.json` is read at startup.

**Check the hooks are registered:**

```powershell
(Get-Content "$env:USERPROFILE\.claude\settings.json" -Raw | ConvertFrom-Json).hooks |
  ConvertTo-Json -Depth 10
```

You should see `Stop`, `Notification`, and `PreToolUse` entries pointing at
`cc-notif.ps1`. If not, re-run `.\install.ps1`. `.\verify.ps1 -Expect Installed`
checks the same thing and also validates your config.

**Hook runs but no toast appears:** Windows 11 silently drops toasts from an
app ID that is not registered. Older installs used the unregistered ID
`Claude Code`. Re-run `.\install.ps1`; it registers `ClaudeCode.Notify` under
`HKCU:\Software\Classes\AppUserModelId`. Also check Do Not Disturb and
Settings > System > Notifications.

**Test the script directly:**

```powershell
'{"session_id":"test1234"}' | powershell -NoProfile -File "$env:USERPROFILE\.claude\hooks\cc-notif.ps1" -HookEvent Stop
```

A toast should appear. If this works but the hook does not, the problem is in
`settings.json`, not the script.

## Toast never appears, but no error

Windows may be suppressing it:

- **Focus assist / Do Not Disturb** — turn it off
- Settings → System → Notifications — make sure notifications are on
- Some Windows builds hide toasts from unregistered app IDs; the script falls
  back to a balloon tip automatically when the toast API is unavailable, but
  not when Windows silently drops a successful toast

## No sound

Check, in order:

1. `sound` in your config points at a file that exists
2. The extension is `.mp3`, `.wav`, or `.wma` — others are ignored
3. `soundDuration` is greater than `0`
4. The path uses doubled backslashes if you edited the JSON by hand

Run `.\config.ps1` and use `b` to browse — it validates the file before saving.

For the "needs input" notification specifically: if `askSound` is empty, `sound`
is used. If both are empty, it is silent by design.

## Sound is cut off

`soundDuration` is a hard stop. Raise it to at least the length of your file.

## "Running scripts is disabled on this system"

The full error looks like this:

```text
.\install.ps1 : File ...\install.ps1 cannot be loaded because running scripts is
disabled on this system.
    + FullyQualifiedErrorId : UnauthorizedAccess
```

Windows blocks unsigned `.ps1` scripts by default (execution policy
`Restricted`). The scripts are not broken. Pick one fix:

**Run once with a bypass.** Changes no setting; it applies to that one command:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
powershell -ExecutionPolicy Bypass -File .\config.ps1
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
powershell -ExecutionPolicy Bypass -File .\verify.ps1 -Expect Installed
```

**Allow local scripts for your account.** After this, `.\install.ps1` works:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

`RemoteSigned` runs scripts made on your computer and still blocks unsigned
scripts downloaded from the internet. Files from a downloaded ZIP or a browser
can carry a "downloaded" mark that keeps them blocked. Clear it once in this
folder:

```powershell
Unblock-File .\*.ps1
Unblock-File .\tests\*.ps1
```

Check your current policy with `Get-ExecutionPolicy -List`. If `MachinePolicy` or
`UserPolicy` is set, your organization controls it through Group Policy and the
commands above cannot override it. Use the bypass form or ask your administrator.

**The installed hook is not affected.** `install.ps1` registers the hook as
`powershell.exe -NoProfile -ExecutionPolicy Bypass -File ...`, so notifications
work even under `Restricted`. The bypass covers only that hook process, not your
system setting.

### Notifications stopped after an older install

Installs from before this fix registered the hook as `& "...\cc-notif.ps1"`,
which a blocked execution policy stops silently: no toast, no error. Re-run the
installer to upgrade the command in place:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

## The file picker does not appear

It may have opened behind your terminal window — check the taskbar. The script
sets the dialog topmost, but some terminal setups still steal focus.

If it never opens, type the full path instead.

## Session name is wrong or shows 8 random characters

The script reads the session name from the transcript in
`%USERPROFILE%\.claude\projects\`. It falls back to the session ID prefix when:

- The transcript has not been written yet — common on a very short first session
- The session has no `/rename` title and no recorded `cwd`

Give the session a name with `/rename`, and it will show up next time.

## "Needs input" fires more often than expected

The `Notification` hook fires whenever Claude Code asks for input or permission
— including permission prompts, not just questions. To keep only the "done"
notification, remove the `Notification` entry from `settings.json` and restart.

## No speech

Check that `speakRecap` is `true` and that the reply was not empty. Only the
`Stop` event speaks. If a voice name in `speechVoice` is not installed, the
Windows default voice is used. Run `.\config.ps1` to pick from installed voices.

## Second recap is not spoken

Recaps speak one at a time. If a recap is still speaking after 30 seconds, the
next one is skipped. Its toast still appears.

## Agent-start toasts are too frequent

Each subagent the main agent launches sends one toast. To stop them, remove the
`PreToolUse` entry from `settings.json` and restart Claude Code.

## No "done" toast after a turn

A turn with no reply text shows no toast, on purpose. Set `"stopRecap": false`
to always get the `message` toast instead.

## Upgraded, but the new notification never fires

Your existing config predates `askMessage` / `askSound`. That is fine —
defaults apply. But if the `Notification` hook is missing from `settings.json`,
re-run `.\install.ps1`; it appends what is missing without disturbing the rest.
