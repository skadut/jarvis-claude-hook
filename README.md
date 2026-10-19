# claude-code-notification

Desktop notification hook for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).
Toasts you when Claude **finishes responding**, when it **needs your input**,
and when the main agent **launches subagents**.

> **Windows only.** Windows 10/11 + PowerShell. macOS and Linux are not supported yet.

- Shows the session name and a recap of Claude's last reply, and plays a custom sound
- Optional text-to-speech reads the recap aloud, one recap at a time
- Separate message + sound for "done", "needs input", and "agent started"
- When the main agent hands work to subagents, one toast shows `jarvis-hook[subagents] - <task>`
- Pick sounds with an Explorer file picker — no path typing

---

## Install

```powershell
git clone https://github.com/skadut/claude-code-notification
cd claude-code-notification
.\install.ps1
.\config.ps1
```

Git Bash / CMD, or if PowerShell says *running scripts is disabled on this
system*: prefix each script with `powershell -ExecutionPolicy Bypass -File`, for
example `powershell -ExecutionPolicy Bypass -File .\install.ps1`.

Restart Claude Code. Done.

## Configure

```powershell
.\config.ps1
```

Walks through every setting. At a sound prompt, type `b` to browse, `none` to clear.

## Uninstall

```powershell
.\uninstall.ps1
```

Choose `1` to reset all your user hooks, or `2` to remove only this project.
Check the result with `.\verify.ps1`.

---

## Docs

Consolidated local documentation is maintained in the Obsidian vault:

```text
D:/redwine-obsidian-local/Wiki/Projects/Claude-hooks-notif/
```

Start at `00_Indeks_Dokumentasi.md`.

| | |
|---|---|
| [Configuration](documentations/configuration.md) | Every config key, locales, message templates |
| [Notification examples](documentations/notifications.md) | What each notification looks like, event by event |
| [How it works](documentations/how-it-works.md) | Hook events, session-name resolution, toast + sound internals |
| [Install details](documentations/install.md) | Per-terminal steps, what gets written where, manual setup |
| [Troubleshooting](documentations/troubleshooting.md) | No toast, no sound, execution policy, upgrading from v1 |

## License

MIT — see [LICENSE](LICENSE).
