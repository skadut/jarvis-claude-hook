# notify.ps1 — Claude Code notification hook (Windows Toast + custom sound)
#   -HookEvent Stop          Claude finished responding (recap toast, optional speech)
#   -HookEvent Notification  Claude asks for input / permission
#   -HookEvent AgentStart    main agent launched a subagent (PreToolUse on the Agent tool)
# SubagentStop is still accepted so an old registration exits quietly until install.ps1 removes it.
param([ValidateSet('Stop', 'Notification', 'AgentStart', 'SubagentStop')][string]$HookEvent = 'Stop')
if ($HookEvent -eq 'SubagentStop') { exit 0 }

$common = "$PSScriptRoot\cc-notif-common.ps1"
if (!(Test-Path $common)) { $common = "$PSScriptRoot\hook-common.ps1" }
. $common

$cfgPath = "$PSScriptRoot\cc-notif-config.json"
$cfg = $null
if (Test-Path $cfgPath) {
    try { $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json } catch {}
}

$isAsk = $HookEvent -eq 'Notification'
$isSub = $HookEvent -eq 'AgentStart'

$title  = if ($cfg.title -is [string] -and $cfg.title -and $cfg.title -ne 'Claude Code') { $cfg.title } else { 'jarvis-hook' }
$sndDur = if (Test-SoundDuration $cfg.soundDuration) { [int]$cfg.soundDuration } else { 3 }
$locale = if ($cfg.locale -is [string]) { $cfg.locale } else { 'en' }

$localeMsgs = @{
    'en' = @{ Stop = "Session '{0}' done!"; Notification = "Session '{0}' needs your input"; AgentStart = "{0} agent started in '{1}'" }
    'id' = @{ Stop = "Sesi '{0}' selesai!"; Notification = "Sesi '{0}' butuh input kamu"; AgentStart = "Agent {0} dimulai di '{1}'" }
}
$defaultMsg = $localeMsgs['en'][$HookEvent]
$cfgMsg = switch ($HookEvent) { 'Notification' { $cfg.askMessage } 'AgentStart' { if ($cfg.subagentMessage -ne '{0} finished responding. {1}') { $cfg.subagentMessage } } default { $cfg.message } }
$argCount = if ($isSub) { 2 } else { 1 }
$msgTpl = if (Test-MessageTemplate $cfgMsg $argCount) { $cfgMsg } else { $defaultMsg }
if ($msgTpl -eq $defaultMsg -and $localeMsgs.ContainsKey($locale)) { $msgTpl = $localeMsgs[$locale][$HookEvent] }

$showRecap   = if ($cfg.stopRecap -is [bool]) { $cfg.stopRecap } else { $true }
$speak       = $cfg.speakRecap -is [bool] -and $cfg.speakRecap
$speechRate  = if (Test-SpeechRate $cfg.speechRate) { [int]$cfg.speechRate } else { 0 }
$speechVoice = if ($cfg.speechVoice -is [string]) { $cfg.speechVoice } else { '' }

$sndPath = if ($cfg.sound -is [string]) { $cfg.sound } else { '' }
if ($isAsk -and $cfg.askSound -is [string] -and $cfg.askSound) { $sndPath = $cfg.askSound }
if ($isSub -and $cfg.subagentSound -is [string] -and $cfg.subagentSound) { $sndPath = $cfg.subagentSound }

$raw = [Console]::In.ReadToEnd()
$j = $null
try { $j = $raw | ConvertFrom-Json } catch {}

$sid = [string]$j.session_id
$hookMsg = [string]$j.message
$name = ''
if ($sid) {
    $jf = Get-ChildItem "$env:USERPROFILE\.claude\projects" -Filter "$sid.jsonl" -Recurse -ErrorAction SilentlyContinue |
          Select-Object -First 1
    if ($jf) {
        try {
            $tl = Select-String -Path $jf.FullName -Pattern '"type":"custom-title"' | Select-Object -First 1
            if ($tl) { $name = ($tl.Line | ConvertFrom-Json).customTitle }
        } catch {}
        if (!$name) {
            try {
                $cwd = Get-Content $jf.FullName -First 20 | ForEach-Object {
                    try { $l = $_ | ConvertFrom-Json; if ($l.cwd) { $l.cwd } } catch {}
                } | Select-Object -First 1
                if ($cwd) { $name = Split-Path $cwd -Leaf }
            } catch {}
        }
    }
}
if (!$name) { $name = if ($sid) { $sid.Substring(0, [Math]::Min(8, $sid.Length)) } else { 'unknown' } }
if ($isSub) {
    $body = Get-SubagentBody $j $name $msgTpl
    $title = "$title[subagents] - $(Get-SubagentTask $j)"
} else {
    $title = "($title) [$name]"
    if ($isAsk) {
        $body = $msgTpl -f $name
        # Claude's own notification text is more specific than the template.
        if ($hookMsg) { $body = $hookMsg }
    } else {
        # No reply text means nothing worth reporting; skip the generic "done!" toast.
        if ($showRecap -and !(Get-Recap $j.last_assistant_message)) { exit 0 }
        $body = Get-StopBody $name $j.last_assistant_message $msgTpl $showRecap
    }
}

# Tests set CC_NOTIF_SILENT so they never pop real toasts or sounds.
if ($env:CC_NOTIF_SILENT) { exit 0 }

# --- Windows Toast notification ---
try {
    [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
    [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime]

    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml(@"
<toast>
  <visual>
    <binding template="ToastGeneric">
      <text>$([System.Security.SecurityElement]::Escape($title))</text>
      <text>$([System.Security.SecurityElement]::Escape($body))</text>
    </binding>
  </visual>
</toast>
"@)
    $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('ClaudeCode.Notify').Show($toast)
} catch {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $n = New-Object System.Windows.Forms.NotifyIcon
        $n.Icon = [System.Drawing.SystemIcons]::Information
        $n.Visible = $true
        $n.ShowBalloonTip(6000, $title, $body, [System.Windows.Forms.ToolTipIcon]::None)
        Start-Sleep 2
        $n.Dispose()
    } catch {}
}

# --- Play custom sound ---
if ($sndPath -and $sndDur -gt 0 -and (Test-Path $sndPath)) {
    $ext = [System.IO.Path]::GetExtension($sndPath).ToLower()
    if ($ext -in '.mp3', '.wav', '.wma') {
        $alias = "snd_$PID"
        $opened = $false
        try {
            Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public class WinMM {
    [DllImport("winmm.dll")]
    public static extern int mciSendString(string cmd, System.Text.StringBuilder ret, int retLen, System.IntPtr hwnd);
}
'@ -ErrorAction SilentlyContinue
            $opened = [WinMM]::mciSendString("open `"$sndPath`" type mpegvideo alias $alias", $null, 0, 0) -eq 0
            if ($opened) {
                [WinMM]::mciSendString("play $alias", $null, 0, 0) | Out-Null
                Start-Sleep -Seconds $sndDur
            }
        } catch {
        } finally {
            if ($opened) { [WinMM]::mciSendString("close $alias", $null, 0, 0) | Out-Null }
        }
    }
}

# --- Read the Stop recap aloud (opt-in) ---
if ($HookEvent -eq 'Stop' -and $speak) {
    $spoken = Get-Recap $j.last_assistant_message
    if ($spoken) { try { Invoke-Speech $spoken $speechRate $speechVoice | Out-Null } catch {} }
}
exit 0
