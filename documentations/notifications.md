# Notification examples

What the hook shows, event by event. Every example uses the default config
(`title: "jarvis-hook"`, `locale: "en"`) and a session named `my-project`,
unless the example says otherwise.

A notification has two lines: the **title** and the **body**. For session
events the title is `(<title>) [<session name>]`. For subagents it is
`<title>[subagents] - <task>`.

## Session finished (`Stop`)

Fires each time Claude finishes responding. The body is a recap of Claude's
last reply:

```text
(jarvis-hook) [my-project]
Added verify.ps1 and 72 tests.
```

The recap has Markdown symbols removed, line breaks collapsed, and a 200-character
limit. When the reply is empty, no toast is shown. With `"stopRecap": false`, the
template is always used instead:

```text
(jarvis-hook) [my-project]
Session 'my-project' done!
```

## Claude needs you (`Notification`)

When Claude sends its own text, the body is that text:

```text
(jarvis-hook) [my-project]
Claude needs your permission to use Bash
```

When Claude sends no text, `askMessage` is used:

```text
(jarvis-hook) [my-project]
Session 'my-project' needs your input
```

The locale never changes Claude's own text. It only replaces the default
templates.

## Main agent launches a subagent (`PreToolUse` on the Agent tool)

Fires when the main agent hands work to a subagent and waits for it. The title
carries the task description Claude gave the subagent:

```text
jarvis-hook[subagents] - Find config files
Explore agent started in 'my-project'
```

The task is `tool_input.description`, cut to 80 characters. Without one, the
agent type is used: `jarvis-hook[subagents] - Explore`.

Subagents finishing send no toast. When the whole job is done, the main
session's `Stop` toast appears.

## Where the session name comes from

The name in the title is picked in this order:

| Source | Example title |
|---|---|
| `/rename` title | `(jarvis-hook) [payment-fix]` |
| Folder of the session's working directory | `(jarvis-hook) [jarvis-claude-hook]` |
| First 8 characters of the session ID | `(jarvis-hook) [3f9a1c2e]` |
| No session ID at all | `(jarvis-hook) [unknown]` |

A new session often shows the ID form, because its transcript has not been
written yet. Use `/rename` to get a readable name.

## Custom messages

`{0}` is replaced with the session name. Text without `{0}` is shown as is.

| Config | Result |
|---|---|
| `"message": "{0} is ready for review"` | Body `my-project is ready for review` |
| `"message": "Done."` | Body `Done.` |
| `"title": "Jarvis"` | Title `(Jarvis) [my-project]` |

An old config with `"title": "Claude Code"` is treated as the default
`jarvis-hook`.

Changing `message`, `askMessage`, or `subagentMessage` turns off the locale for
that field. A message with broken braces, such as `Done {`, falls back to the
default text instead of failing.

## Sound

The sound plays right after the notification appears.

| Event | Sound used |
|---|---|
| `Stop` | `sound` |
| `Notification` | `askSound`, or `sound` when `askSound` is empty |
| Agent start | `subagentSound`, or `sound` when `subagentSound` is empty |

Playback stops after `soundDuration` seconds. With both sounds empty, the
notification is silent.

## Spoken recap

With `"speakRecap": true`, the "done" recap is also read aloud after the sound,
for example: "Added verify.ps1 and 72 tests." Only the `Stop` event speaks.
`Notification` and agent-start toasts never do. Two recaps never speak at once.

## Older Windows

When the toast API is not available, the same title and body appear as a
system tray balloon instead.

## Try it

Run the installed hook by hand. These commands show a real notification:

```powershell
'{"session_id":"test1234","last_assistant_message":"Added verify.ps1 and 72 tests."}' | powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\hooks\cc-notif.ps1" -HookEvent Stop
```

Expected: `(jarvis-hook) [test1234]` / `Added verify.ps1 and 72 tests.`

```powershell
'{"session_id":"test1234","message":"Claude needs your permission to use Bash"}' | powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\hooks\cc-notif.ps1" -HookEvent Notification
```

Expected: `(jarvis-hook) [test1234]` / `Claude needs your permission to use Bash`

`test1234` has no transcript, so the session ID itself becomes the name.

```powershell
'{"session_id":"test1234","tool_name":"Agent","tool_input":{"subagent_type":"Explore","description":"Find config files"}}' | powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\hooks\cc-notif.ps1" -HookEvent AgentStart
```

Expected: `jarvis-hook[subagents] - Find config files` / `Explore agent started in 'test1234'`
