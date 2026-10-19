# Configuration

Config lives at `%USERPROFILE%\.claude\hooks\cc-notif-config.json`.

Edit it interactively — recommended:

```powershell
.\config.ps1
```

Or open it directly:

```powershell
notepad "$env:USERPROFILE\.claude\hooks\cc-notif-config.json"
```

## Keys

| Key | Default | What it does |
|---|---|---|
| `title` | `jarvis-hook` | Title prefix. Shown as `(jarvis-hook) [session]`, or `jarvis-hook[subagents] - task` |
| `message` | `Session '{0}' done!` | Shown when a session finishes |
| `askMessage` | `Session '{0}' needs your input` | Shown when Claude asks for input |
| `subagentMessage` | `{0} agent started in '{1}'` | Shown when the main agent launches a subagent |
| `sound` | `""` | Audio file for "done". Empty = silent |
| `askSound` | `""` | Audio file for "needs input". Empty = reuse `sound` |
| `subagentSound` | `""` | Audio file for a launched subagent. Empty = reuse `sound` |
| `soundDuration` | `3` | Whole seconds, 0 or more, to let the sound play. `0` = no sound |
| `stopRecap` | `true` | Show Claude's last reply in the "done" toast. A turn with no reply text shows no toast |
| `speakRecap` | `false` | Read the "done" recap aloud with text-to-speech |
| `speechRate` | `0` | Speech speed, `-10` (slow) to `10` (fast) |
| `speechVoice` | `""` | Installed voice name. Empty = Windows default |
| `locale` | `en` | `en` or `id`. Only applies while messages are at their defaults |

In `message` and `askMessage`, `{0}` is the session name. In `subagentMessage`,
`{0}` is the agent type and `{1}` is the session name.
Use `{{` and `}}` for literal braces.

`config.ps1` rejects broken braces and negative or fractional durations, and
keeps your previous value. If you edit the file by hand and make a mistake, the
hook uses the default for that field instead of failing.

Supported audio: `.mp3`, `.wav`, `.wma`.

## Example

```json
{
  "title": "jarvis-hook",
  "message": "Session '{0}' done!",
  "askMessage": "Session '{0}' needs your input",
  "subagentMessage": "{0} agent started in '{1}'",
  "sound": "C:\\Users\\me\\sounds\\done.mp3",
  "askSound": "C:\\Users\\me\\sounds\\ping.wav",
  "subagentSound": "",
  "stopRecap": true,
  "speakRecap": false,
  "speechRate": 0,
  "speechVoice": "",
  "soundDuration": 3,
  "locale": "en"
}
```

Backslashes in JSON paths must be doubled. `config.ps1` handles this for you.

## Picking a sound

At either sound prompt in `config.ps1`:

| Input | Result |
|---|---|
| `b` | Opens the Windows file picker, filtered to audio files |
| a path | Used directly, if it exists and the format is supported |
| `none` | Clears the sound |
| Enter | Keeps the current value |

## Text-to-speech

Off by default. `config.ps1` asks whether to read the "done" recap aloud. When you
answer `y`, it also asks for a speech rate and lists your installed voices.

Speech reads Claude's reply out loud, so anyone nearby can hear it. Only one recap
speaks at a time; a second one waits up to 30 seconds, then skips.

## Locales

`locale` swaps the built-in default text. It is ignored once you set your own
`message` / `askMessage` — your text always wins.

| Locale | Done | Needs input |
|---|---|---|
| `en` | `Session '{0}' done!` | `Session '{0}' needs your input` |
| `id` | `Sesi '{0}' selesai!` | `Sesi '{0}' butuh input kamu` |
