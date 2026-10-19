# Claude Code: Windows Notification Hook Spec

Toast recap of each finished turn, with optional text-to-speech, driven by Claude
Code's hook system.

## Hook events used

| Event | Fires when | Behavior |
|---|---|---|
| `Notification` | Claude needs input or permission | Toast with Claude's own request text |
| `Stop` | Claude finishes responding for a turn | Toast recap of the reply, optional speech |
| `PreToolUse` (`Agent|Task`) | Main agent launches a subagent | Toast with the task description |

`Stop` input includes `last_assistant_message`: Claude's final response text for
that turn, provided in the hook's JSON payload. No transcript parsing is needed for
the recap.

## Registration

`install.ps1` registers one script, `cc-notif.ps1`, for all three events in
`%USERPROFILE%\.claude\settings.json`:

```json
{
  "type": "command",
  "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"$env:USERPROFILE\\.claude\\hooks\\cc-notif.ps1\" -HookEvent Stop",
  "shell": "powershell",
  "async": true
}
```

`-ExecutionPolicy Bypass` keeps the hook working when Windows blocks unsigned
scripts. It applies to the hook process only.

`async: true` is required. Speech blocks the script, and without `async` Claude Code
waits for the hook to exit before it accepts the next prompt.

## Stop recap

- The toast body is `<session name>: <recap>`.
- The recap is `last_assistant_message` with Markdown symbols (`# * \` _`) removed,
  line breaks collapsed, and a 200-character limit.
- When the reply is empty, the toast falls back to `message`
  (default `Session '{0}' done!`).
- `stopRecap: false` turns the recap off and always uses `message`.

## Text-to-speech (opt-in)

- Off by default. Turn it on in `config.ps1` or set `speakRecap: true`.
- Uses `System.Speech.Synthesis.SpeechSynthesizer` at volume 100.
- `speechRate` sets the speed, from `-10` (slow) to `10` (fast). Default `0`.
- `speechVoice` picks an installed voice. Empty uses the Windows default.
  `config.ps1` lists the installed voices to choose from.
- Speaks the same cleaned recap shown in the toast. People nearby can hear it.

## Speech lock

Each hook invocation is its own process, so two `Stop` events close together could
speak at the same time. A named mutex, `Local\cc-notif-speech`, lets one recap speak
at a time. A second recap waits up to 30 seconds for the first to finish, then
skips.

## Behavior notes

- **Recap source**: the text is Claude's actual closing message for the turn, not a
  separately generated summary. Quality depends on how Claude phrases its reply.
- **Per-turn, not per-session**: `Stop` fires once per turn. A task that pauses to
  ask a question triggers a notification at that pause too.
- **Never blocks the agent loop**: the script always exits 0. `Stop` would force
  Claude to keep responding on exit code 2.
- **Toast truncation**: Windows toasts render 2 to 3 lines regardless of length, so
  the 200-character limit is a ceiling, not a guarantee of what is shown.
