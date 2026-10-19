# How it works

## Hook events

`install.ps1` registers one script, `cc-notif.ps1`, against three Claude Code
hook events in `%USERPROFILE%\.claude\settings.json`:

| Event | Fires when | Flag passed |
|---|---|---|
| `Stop` | Claude finishes responding to a turn | `-HookEvent Stop` |
| `Notification` | Claude asks for input or permission | `-HookEvent Notification` |
| `PreToolUse` (matcher `Agent|Task`) | Main agent launches a subagent | `-HookEvent AgentStart` |

All entries run with `async = true`, so a slow sound never blocks Claude Code.
Shared helpers live in `cc-notif-common.ps1`, copied next to the hook script.

The registered command looks like:

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\hooks\cc-notif.ps1" -HookEvent Stop
```

`-ExecutionPolicy Bypass` lets the hook run even when Windows blocks unsigned
scripts. It applies to that one hook process only and does not change your
system setting. Older installs used `& "...\cc-notif.ps1"`; re-running
`install.ps1` rewrites them in place.

## What the script does

1. Reads `cc-notif-config.json` from its own directory. Missing or malformed
   config is not fatal — defaults apply.
2. Picks the message and sound for the event. `Notification` uses `askMessage`
   and `askSound`, falling back to `sound` when `askSound` is empty.
3. Reads the hook payload from stdin as JSON, taking `session_id` and, for
   `Notification`, Claude's own `message` text.
4. Resolves a session name (below).
5. Shows a toast, then plays the sound.

## Session name resolution

Claude Code passes only a session ID, so the script looks up
`%USERPROFILE%\.claude\projects\**\<session_id>.jsonl` and tries, in order:

1. **Custom title** — the `customTitle` set by `/rename`
2. **Working directory** — leaf folder name of the session's `cwd`
3. **Session ID prefix** — first 8 characters
4. `unknown`, if there is no session ID at all

## Notification body

The title is `(jarvis-hook) [<session name>]` for `Stop` and `Notification`.

For `Stop`, the body is a recap of `last_assistant_message`: Markdown symbols
removed, line breaks collapsed, at most 200 characters. When the reply is empty,
no toast is shown. When `stopRecap` is `false`, `message` is used with `{0}`
replaced by the session name.

For `Notification`, if Claude supplied its own text, that is used instead,
prefixed with the session name, e.g.
`my-project: Claude needs your permission to use Bash`.
Claude's text says *what* is being asked, which the template cannot. When no
text is supplied, `askMessage` is used.

For `AgentStart`, the script reads `tool_input.subagent_type` and
`tool_input.description` from the `PreToolUse` payload. The title is
`jarvis-hook[subagents] - <description>` (80-character limit), and the body names
the agent type and session. Individual subagents finishing send no toast; the
main session's `Stop` toast marks the end of the job.

For `Stop`, a turn with no reply text sends no toast.

## Toast

Uses the WinRT `Windows.UI.Notifications` toast API with a `ToastGeneric`
two-line binding. Text is XML-escaped, so quotes and `&` in your message are
safe.

If WinRT is unavailable, it falls back to a legacy `NotifyIcon` balloon tip.

## Sound

Played through `winmm.dll`'s `mciSendString` — no extra dependencies, and it
handles MP3 as well as WAV. The script opens the file under a PID-scoped alias,
plays it, sleeps `soundDuration` seconds, then closes the alias.

`soundDuration` is a hard stop, not a length: a 10-second file with
`soundDuration: 3` plays the first 3 seconds. The audio alias is closed in a
`finally` block, so a playback error never leaves the file open.

## Speech

When `speakRecap` is `true`, the `Stop` recap is read with
`System.Speech.Synthesis.SpeechSynthesizer`, using `speechRate` and `speechVoice`.
It runs after the sound, inside the same async hook, so Claude Code is never
blocked.

Each hook call is its own process. A named mutex, `Local\cc-notif-speech`, makes
recaps speak one at a time: a second recap waits up to 30 seconds, then skips.
