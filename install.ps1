# install.ps1 — One-command setup for claude-code-notification

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\hook-common.ps1"
$HooksDir     = "$env:USERPROFILE\.claude\hooks"
$SettingsPath = "$env:USERPROFILE\.claude\settings.json"
$ScriptDir    = $PSScriptRoot
# Bypass applies to this one process, so the hook runs even when the user's execution policy blocks scripts.
$HookCmd      = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\hooks\cc-notif.ps1"'

# 1. Ensure hooks dir
New-Item -ItemType Directory -Force $HooksDir | Out-Null

# 2. Install hook script
Copy-Item "$ScriptDir\notify.ps1" "$HooksDir\cc-notif.ps1" -Force
Copy-Item "$ScriptDir\hook-common.ps1" "$HooksDir\cc-notif-common.ps1" -Force
Write-Host "[OK] Hook installed: $HooksDir\cc-notif.ps1" -ForegroundColor Green

# Windows 11 silently drops toasts from an unregistered app ID; register ours for this user.
$AppIdKey = 'HKCU:\Software\Classes\AppUserModelId\ClaudeCode.Notify'
New-Item $AppIdKey -Force | Out-Null
New-ItemProperty $AppIdKey -Name DisplayName -Value 'Claude Code' -Force | Out-Null
Write-Host "[OK] Toast app ID registered: ClaudeCode.Notify" -ForegroundColor Green

# 3. Config: migrate old .ps1 config or create new .json
$OldConfig = "$HooksDir\cc-notif-config.ps1"
$NewConfig = "$HooksDir\cc-notif-config.json"

if ((Test-Path $OldConfig) -and !(Test-Path $NewConfig)) {
    Write-Host "[!!] Found old .ps1 config — migrating to .json" -ForegroundColor Yellow
    try {
        $raw = Get-Content $OldConfig -Raw
        $extract = { param($varName, $default)
            if ($raw -match ('\$' + $varName + '\s*=\s*[''"](.+?)[''"]')) { $Matches[1] } else { $default }
        }
        $extractNum = { param($varName, $default)
            if ($raw -match ('\$' + $varName + '\s*=\s*(\d+)')) { [int]$Matches[1] } else { $default }
        }
        $migrated = @{
            title         = & $extract 'NotifTitle'   'Claude Code'
            message       = & $extract 'NotifMessage' "Session '{0}' done!"
            askMessage    = "Session '{0}' needs your input"
            sound         = & $extract 'SoundPath'    ''
            askSound      = ''
            soundDuration = & $extractNum 'SoundDuration' 3
            locale        = 'en'
        }
        $migrated | ConvertTo-Json -Depth 5 | Set-Content $NewConfig -Encoding utf8
        Rename-Item $OldConfig "$OldConfig.bak"
        Write-Host "[OK] Migrated config: $NewConfig (old renamed to .bak)" -ForegroundColor Green
    } catch {
        Write-Host "[!!] Migration failed, creating fresh config" -ForegroundColor Red
        Copy-Item "$ScriptDir\config.example.json" $NewConfig
    }
} elseif (!(Test-Path $NewConfig)) {
    Copy-Item "$ScriptDir\config.example.json" $NewConfig
    Write-Host "[OK] Config created: $NewConfig" -ForegroundColor Green
    Write-Host "     -> Edit it to set your message and sound." -ForegroundColor Yellow
} else {
    Write-Host "[--] Config exists, skipping: $NewConfig" -ForegroundColor Cyan
}

# 4. Patch settings.json — APPEND to existing hooks, don't overwrite
if (Test-Path $SettingsPath) {
    try { $s = Get-Content $SettingsPath -Raw | ConvertFrom-Json }
    catch { throw "settings.json is not valid JSON. Nothing was changed: $SettingsPath" }
    if ($null -eq $s) { throw "settings.json is empty. Nothing was changed: $SettingsPath" }
} else {
    $s = [PSCustomObject]@{}
}

if (!$s.PSObject.Properties['hooks']) {
    $s | Add-Member -NotePropertyName hooks -NotePropertyValue ([PSCustomObject]@{})
}

# Older installs toasted every finished subagent; drop that registration.
if ($s.hooks.PSObject.Properties['SubagentStop']) {
    $groups = @($s.hooks.SubagentStop | ForEach-Object {
        $_.hooks = @($_.hooks | Where-Object { !(Test-ProjectHookCommand $_.command) })
        if ($_.hooks.Count) { $_ }
    })
    if ($groups.Count) { $s.hooks.SubagentStop = $groups } else { $s.hooks.PSObject.Properties.Remove('SubagentStop') }
    Write-Host "[OK] Removed old per-subagent SubagentStop hook." -ForegroundColor Green
}

# PreToolUse on the Agent tool fires when the main agent launches a subagent.
foreach ($evt in 'Stop', 'Notification', 'PreToolUse') {
    $flag = if ($evt -eq 'PreToolUse') { 'AgentStart' } else { $evt }
    $cmd = "$HookCmd -HookEvent $flag"
    $newHookGroup = [PSCustomObject]@{
        hooks = @([PSCustomObject]@{
            type    = "command"
            command = $cmd
            shell   = "powershell"
            async   = $true
        })
    }
    if ($evt -eq 'PreToolUse') { $newHookGroup | Add-Member -NotePropertyName matcher -NotePropertyValue 'Agent|Task' }

    if ($s.hooks.PSObject.Properties[$evt]) {
        $existing = @($s.hooks.$evt)
        # An older install may use a command the execution policy blocks; rewrite it in place.
        $alreadyInstalled = $false
        foreach ($group in $existing) {
            foreach ($h in @($group.hooks)) {
                if (Test-ProjectHookCommand $h.command) {
                    $alreadyInstalled = $true
                    if ($h.command -ne $cmd) {
                        $h.command = $cmd
                        Write-Host "[OK] $evt hook updated to bypass execution policy." -ForegroundColor Green
                    }
                }
            }
        }
        if (!$alreadyInstalled) {
            $s.hooks.$evt = @($existing) + @($newHookGroup)
            Write-Host "[OK] Hook appended to existing $evt hooks." -ForegroundColor Green
        } else {
            Write-Host "[--] Hook already registered in $evt hooks." -ForegroundColor Cyan
        }
    } else {
        $s.hooks | Add-Member -NotePropertyName $evt -NotePropertyValue @($newHookGroup)
        Write-Host "[OK] $evt hook registered." -ForegroundColor Green
    }
}

$s | ConvertTo-Json -Depth 10 | Set-Content $SettingsPath -Encoding utf8
Write-Host "[OK] settings.json saved." -ForegroundColor Green

Write-Host ""
Write-Host "Done! Edit your config:" -ForegroundColor White
Write-Host "  notepad `"$NewConfig`"" -ForegroundColor Yellow
