# config.ps1 — Interactive config editor for claude-code-notification

. "$PSScriptRoot\hook-common.ps1"

Write-Host ""
Write-Host "=== Claude Code Notification Config ===" -ForegroundColor Cyan
Write-Host ""

# Prompt for an audio file: accepts a typed path, 'b' to open the Explorer
# picker, or 'none' to clear. Returns $null when nothing should change.
function Read-SoundPath {
    param([string]$Label, [string]$Current)

    Write-Host ""
    Write-Host "$Label (.mp3 / .wav / .wma)" -ForegroundColor Yellow
    Write-Host "  Current: $(if ($Current) { $Current } else { '(none)' })" -ForegroundColor Gray
    Write-Host "  Type 'b' to browse, 'none' to clear, Enter to keep." -ForegroundColor Gray
    $v = Read-Host "  New value"

    if ($v -in 'b', 'browse') {
        Add-Type -AssemblyName System.Windows.Forms
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Title  = "Pick a notification sound"
        $dlg.Filter = "Audio (*.mp3;*.wav;*.wma)|*.mp3;*.wav;*.wma|All files (*.*)|*.*"
        if ($Current -and (Test-Path $Current)) {
            $dlg.InitialDirectory = Split-Path $Current -Parent
        }
        # Owner form keeps the dialog above the console instead of behind it.
        $owner = New-Object System.Windows.Forms.Form -Property @{ TopMost = $true }
        $v = if ($dlg.ShowDialog($owner) -eq 'OK') { $dlg.FileName } else { '' }
        $owner.Dispose()
        if ($v -eq '') { Write-Host "  Cancelled. Skipped." -ForegroundColor Gray }
    }

    if ($v -eq 'none') { return '' }
    if ($v -eq '') { return $null }

    if (!(Test-Path $v)) {
        Write-Host "  [!!] File not found: $v. Skipped." -ForegroundColor Red
        return $null
    }
    $ext = [System.IO.Path]::GetExtension($v).ToLower()
    if ($ext -notin '.mp3', '.wav', '.wma') {
        Write-Host "  [!!] Unsupported format ($ext). Skipped." -ForegroundColor Red
        return $null
    }
    return $v
}
Write-Host ""

# Step 1: Ask for config path
$DefaultPath = "$env:USERPROFILE\.claude\hooks\cc-notif-config.json"
Write-Host "Config file path" -ForegroundColor Yellow
Write-Host "  Default: $DefaultPath" -ForegroundColor Gray
$ConfigPath = Read-Host "  Path (Enter for default)"
if ($ConfigPath -eq '') { $ConfigPath = $DefaultPath }

if (!(Test-Path $ConfigPath)) {
    Write-Host ""
    Write-Host "File not found: $ConfigPath" -ForegroundColor Red
    Write-Host "Run install.ps1 first, or check the path." -ForegroundColor Yellow
    exit 1
}

# Step 2: Load and edit
$cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
Write-Host ""
Write-Host "Editing: $ConfigPath" -ForegroundColor Green
Write-Host "Press Enter to keep current value." -ForegroundColor Gray

# Older config files predate askMessage/askSound — add the property if missing.
function Set-Field {
    param([string]$Name, $Value)
    if ($cfg.PSObject.Properties[$Name]) { $cfg.$Name = $Value }
    else { $cfg | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

function Read-Message {
    param([string]$Name, [string]$Label, [int]$ArgumentCount = 1)
    Write-Host ""
    Write-Host $Label -ForegroundColor Yellow
    $current = $cfg.$Name
    Write-Host "  Current: $(if ($current) { $current } else { '(default)' })" -ForegroundColor Gray
    $v = Read-Host "  New value"
    if ($v -eq '') { return }
    if (Test-MessageTemplate $v $ArgumentCount) { Set-Field $Name $v }
    else { Write-Host "  [!!] Invalid braces. Use {0}$(if ($ArgumentCount -gt 1) { ' and {1}' }), or {{ }} for literal braces. Skipped." -ForegroundColor Red }
}


# Title
Write-Host ""
Write-Host "Notification title" -ForegroundColor Yellow
Write-Host "  Current: $($cfg.title)" -ForegroundColor Gray
$v = Read-Host "  New value"
if ($v -ne '') { $cfg.title = $v }

Read-Message 'message' 'Notification message ({0} = session name)'
Read-Message 'askMessage' 'Input-needed message ({0} = session name)'
Read-Message 'subagentMessage' 'Agent-started message ({0} = agent type, {1} = session name)' 2

# Done sound
$v = Read-SoundPath "Sound when a session finishes" $cfg.sound
if ($null -ne $v) { Set-Field 'sound' $v }

# Ask sound
$v = Read-SoundPath "Sound when Claude needs your input (empty = same as above)" $cfg.askSound
if ($null -ne $v) { Set-Field 'askSound' $v }

# Subagent sound
$v = Read-SoundPath "Sound when a subagent starts (empty = finished sound)" $cfg.subagentSound
if ($null -ne $v) { Set-Field 'subagentSound' $v }

# Sound Duration
Write-Host ""
Write-Host "Sound duration in seconds" -ForegroundColor Yellow
Write-Host "  Current: $($cfg.soundDuration)" -ForegroundColor Gray
$v = Read-Host "  New value"
if ($v -ne '') {
    if ($v -match '^\d+$' -and [long]$v -le [int]::MaxValue) { Set-Field 'soundDuration' ([int]$v) }
    else { Write-Host "  [!!] Use a whole number 0 or higher. Skipped." -ForegroundColor Red }
}

function Read-YesNo {
    param([string]$Name, [string]$Label, [bool]$Default)
    $current = if ($cfg.$Name -is [bool]) { $cfg.$Name } else { $Default }
    Write-Host ""
    Write-Host "$Label (y/n)" -ForegroundColor Yellow
    Write-Host "  Current: $(if ($current) { 'y' } else { 'n' })" -ForegroundColor Gray
    $v = Read-Host "  New value"
    if ($v -in 'y', 'yes') { Set-Field $Name $true }
    elseif ($v -in 'n', 'no') { Set-Field $Name $false }
    elseif ($v -ne '') { Write-Host "  [!!] Type y or n. Skipped." -ForegroundColor Red }
}

# Stop recap
Read-YesNo 'stopRecap' "Show Claude's last reply in the finished toast" $true

# Text-to-speech
Read-YesNo 'speakRecap' 'Read the finished recap aloud (text-to-speech; people nearby will hear it)' $false

if ($cfg.speakRecap -eq $true) {
    Write-Host ""
    Write-Host "Speech rate (-10 slow to 10 fast)" -ForegroundColor Yellow
    Write-Host "  Current: $(if (Test-SpeechRate $cfg.speechRate) { $cfg.speechRate } else { 0 })" -ForegroundColor Gray
    $v = Read-Host "  New value"
    if ($v -ne '') {
        if ($v -match '^-?\d+$' -and [int]$v -ge -10 -and [int]$v -le 10) { Set-Field 'speechRate' ([int]$v) }
        else { Write-Host "  [!!] Use a whole number from -10 to 10. Skipped." -ForegroundColor Red }
    }

    $voices = @()
    try {
        Add-Type -AssemblyName System.Speech
        $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
        $voices = @($synth.GetInstalledVoices() | Where-Object Enabled | ForEach-Object { $_.VoiceInfo.Name })
        $synth.Dispose()
    } catch {}
    Write-Host ""
    Write-Host "Voice" -ForegroundColor Yellow
    Write-Host "  Current: $(if ($cfg.speechVoice) { $cfg.speechVoice } else { '(Windows default)' })" -ForegroundColor Gray
    for ($i = 0; $i -lt $voices.Count; $i++) { Write-Host "  $($i + 1). $($voices[$i])" -ForegroundColor Gray }
    $v = Read-Host "  Number, 'default', or Enter to keep"
    if ($v -eq 'default') { Set-Field 'speechVoice' '' }
    elseif ($v -match '^\d+$' -and [int]$v -ge 1 -and [int]$v -le $voices.Count) { Set-Field 'speechVoice' $voices[[int]$v - 1] }
    elseif ($v -ne '') { Write-Host "  [!!] Unknown voice. Skipped." -ForegroundColor Red }
}

# Locale
Write-Host ""
Write-Host "Locale (en, id)" -ForegroundColor Yellow
Write-Host "  Current: $($cfg.locale)" -ForegroundColor Gray
$v = Read-Host "  New value"
if ($v -ne '' -and $v -in 'en', 'id') { $cfg.locale = $v }
elseif ($v -ne '') { Write-Host "  [!!] Unknown locale. Skipped." -ForegroundColor Red }

# Step 3: Save
# PS 5.1 escapes ' < > & as \uXXXX; decode them so the file stays hand-editable.
$json = $cfg | ConvertTo-Json -Depth 5
$map = @{ '\u0027' = "'"; '\u003c' = '<'; '\u003e' = '>'; '\u0026' = '&' }
foreach ($k in $map.Keys) { $json = $json.Replace($k, $map[$k]) }
$json | Set-Content $ConfigPath -Encoding utf8

Write-Host ""
Write-Host "--- Saved ---" -ForegroundColor Green
Write-Host "  File:     $ConfigPath"
Write-Host "  Title:    $($cfg.title)"
Write-Host "  Message:  $(if (Test-MessageTemplate $cfg.message) { $cfg.message -f 'my-project' } else { '(default)' })"
Write-Host "  Ask msg:  $(if (Test-MessageTemplate $cfg.askMessage) { $cfg.askMessage -f 'my-project' } else { '(default)' })"
Write-Host "  Subagent: $(if (Test-MessageTemplate $cfg.subagentMessage 2) { $cfg.subagentMessage -f 'Explore', 'my-project' } else { '(default)' })"
Write-Host "  Sub snd:  $(if ($cfg.subagentSound) { $cfg.subagentSound } else { '(same as finished)' })"
Write-Host "  Sound:    $(if ($cfg.sound) { $cfg.sound } else { '(disabled)' })"
Write-Host "  Ask snd:  $(if ($cfg.askSound) { $cfg.askSound } else { '(same as above)' })"
Write-Host "  Duration: $($cfg.soundDuration)s"
Write-Host "  Recap:    $(if ($cfg.stopRecap -eq $false) { 'off' } else { 'on' })"
Write-Host "  Speech:   $(if ($cfg.speakRecap -eq $true) { "on, rate $(if (Test-SpeechRate $cfg.speechRate) { $cfg.speechRate } else { 0 }), voice $(if ($cfg.speechVoice) { $cfg.speechVoice } else { 'default' })" } else { 'off' })"
Write-Host "  Locale:   $($cfg.locale)"
Write-Host ""
