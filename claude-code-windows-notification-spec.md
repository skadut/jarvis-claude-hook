# Claude Code — Windows Notification Hook Spec

Toast + text-to-speech recap of completed tasks, driven by Claude Code's hook system.

## Purpose

Extend the existing Windows toast notification hook (permission/idle prompts) with a
second hook that fires when Claude finishes a turn, surfaces a recap of what was done,
and optionally reads it aloud.

## Hook events used

| Event          | Fires when                                | Role in this spec                                   |
| -------------- | ------------------------------------------ | ----------------------------------------------------- |
| `Notification` | Claude needs input/permission (system event) | Existing toast — generic "needs attention" message |
| `Stop`         | Claude finishes responding for a turn        | New — toast + TTS recap of the completed task        |

`Stop` input includes `last_assistant_message`: Claude's final response text for that
turn, provided directly in the hook's JSON payload — no transcript parsing needed.

## Configuration — `settings.json`

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe -ExecutionPolicy Bypass -File \"C:\\path\\to\\toast-notification.ps1\""
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe -ExecutionPolicy Bypass -File \"C:\\path\\to\\stop-notify.ps1\"",
            "async": true
          }
        ]
      }
    ]
  }
}
```

`async: true` on the `Stop` handler is required — TTS playback blocks the script, and
without `async` Claude Code waits for the hook to exit before it's ready for the next
prompt.

## Script — `stop-notify.ps1`

```powershell
$callInput = [Console]::In.ReadToEnd() | ConvertFrom-Json
$summary = $callInput.last_assistant_message

if ([string]::IsNullOrWhiteSpace($summary)) {
    $summary = "Task selesai"
} elseif ($summary.Length -gt 200) {
    $summary = $summary.Substring(0, 200) + "..."
}

# strip markdown noise so it reads clean in a toast / TTS
$summary = $summary -replace '[#*`_]', ''

# Toast
powershell.exe -ExecutionPolicy Bypass -File "C:\path\to\toast-notification.ps1" `
  -Title "Claude Code selesai" -Message $summary

# Text-to-speech
Add-Type -AssemblyName System.Speech
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
$synth.Rate = 0        # -10 (slow) to 10 (fast)
$synth.Volume = 100
$synth.Speak($summary)
```

## Behavior notes

- **Recap source**: the toast/speech text is Claude's actual closing message for the
  turn, not a separately generated summary — quality depends on how Claude phrases
  its final reply.
- **Per-turn, not per-session**: `Stop` fires once per turn. A multi-step task that
  pauses to ask a question will trigger a notification at that pause too, not only at
  true completion.
- **Must not block the agent loop**: the script should always exit 0. `Stop` can force
  Claude to keep responding on exit code 2.
- **Toast truncation**: Windows toast templates typically render 2–3 lines regardless
  of string length, so the 200-char trim is a ceiling, not a guarantee of what's shown.
- **Overlapping speech**: each hook invocation spawns its own process, so two `Stop`
  events close together can produce overlapping audio. Add a mutex/lock-file check at
  the top of the script if this becomes a problem in practice.
- **Voice selection**: default SAPI voices are usable but robotic. List installed
  voices with:
  ```powershell
  Add-Type -AssemblyName System.Speech
  (New-Object System.Speech.Synthesis.SpeechSynthesizer).GetInstalledVoices() |
    ForEach-Object { $_.VoiceInfo.Name }
  ```
  Select one with `$synth.SelectVoice("Microsoft Zira Desktop")`.

## Optional enhancements (not yet implemented)

1. **Steer the recap via `CLAUDE.md`** — add "end each turn with a one-line summary of
   what was done" so `last_assistant_message` is consistently short and speakable.
2. **`"type": "prompt"` hook on `Stop`** — send the turn to a fast model for a short,
   structured recap instead of using the raw closing message. More consistent, adds a
   small extra API call per turn. Worth splitting into two strings if adopted: a
   readable toast line and a shorter, cleaner line for `Speak()` (code identifiers and
   file paths read awkwardly aloud).
