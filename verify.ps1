# verify.ps1 — Read-only check of jarvis-claude-hook installation state
param([ValidateSet('Installed', 'ProjectRemoved', 'GlobalHooksReset')][string]$Expect)

. "$PSScriptRoot\hook-common.ps1"
$ClaudeDir    = "$env:USERPROFILE\.claude"
$HooksDir     = "$ClaudeDir\hooks"
$SettingsPath = "$ClaudeDir\settings.json"
$Events       = 'Stop', 'Notification', 'PreToolUse'
$Files        = 'cc-notif.ps1', 'cc-notif-common.ps1', 'cc-notif-config.json'

$settingsValid = $true
$s = $null
if (Test-Path $SettingsPath) {
    try { $s = Get-Content $SettingsPath -Raw | ConvertFrom-Json } catch { $settingsValid = $false }
    if ($settingsValid -and $null -eq $s) { $settingsValid = $false }
}

$registered = @()
$hookCount = 0
if ($s -and $s.PSObject.Properties['hooks']) {
    foreach ($evt in $s.hooks.PSObject.Properties) {
        foreach ($group in @($evt.Value)) {
            foreach ($h in @($group.hooks)) {
                $hookCount++
                if (Test-ProjectHookCommand $h.command) { $registered += $evt.Name }
            }
        }
    }
}
$registered = @($registered | Sort-Object -Unique)
$present = @($Files | Where-Object { Test-Path "$HooksDir\$_" })

$configValid = $false
$cfgPath = "$HooksDir\cc-notif-config.json"
if (Test-Path $cfgPath) {
    try {
        $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
        $configValid = $null -ne $cfg -and
            ($null -eq $cfg.soundDuration -or (Test-SoundDuration $cfg.soundDuration)) -and
            ($null -eq $cfg.message -or (Test-MessageTemplate $cfg.message)) -and
            ($null -eq $cfg.askMessage -or (Test-MessageTemplate $cfg.askMessage)) -and
            ($null -eq $cfg.subagentMessage -or (Test-MessageTemplate $cfg.subagentMessage 2)) -and
            ($null -eq $cfg.speechRate -or (Test-SpeechRate $cfg.speechRate))
    } catch {}
}

Write-Host "settings.json:   $(if (!(Test-Path $SettingsPath)) { 'missing' } elseif ($settingsValid) { 'valid' } else { 'INVALID JSON' })"
Write-Host "Project events:  $(if ($registered) { $registered -join ', ' } else { 'none' })"
Write-Host "Total hooks:     $hookCount"
Write-Host "Installed files: $(if ($present) { $present -join ', ' } else { 'none' })"
Write-Host "Config:          $(if (!(Test-Path $cfgPath)) { 'missing' } elseif ($configValid) { 'valid' } else { 'INVALID' })"

if (!$Expect) { exit $(if ($settingsValid) { 0 } else { 1 }) }

$ok = $settingsValid -and $(switch ($Expect) {
    'Installed'        { $registered.Count -eq $Events.Count -and $present.Count -eq $Files.Count -and $configValid }
    'ProjectRemoved'   { $registered.Count -eq 0 -and $present.Count -eq 0 }
    'GlobalHooksReset' { $hookCount -eq 0 }
})
Write-Host "Expect $Expect`: $(if ($ok) { 'PASS' } else { 'FAIL' })" -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
exit $(if ($ok) { 0 } else { 1 })
