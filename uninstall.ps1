# uninstall.ps1 — Remove Claude Code hooks from the current Windows user
param([ValidateSet('1', '2')][string]$Mode)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\hook-common.ps1"
$ClaudeDir    = "$env:USERPROFILE\.claude"
$HooksDir     = "$ClaudeDir\hooks"
$SettingsPath = "$ClaudeDir\settings.json"
$ProjectFiles = @("cc-notif.ps1", "cc-notif-common.ps1", "cc-notif-config.json", "cc-notif-config.ps1.bak")

function Save-Settings($s) {
    $backup = "$SettingsPath.bak-$([guid]::NewGuid().ToString('N'))"
    Copy-Item $SettingsPath $backup
    $s | ConvertTo-Json -Depth 20 | Set-Content $SettingsPath -Encoding utf8
    Write-Host "[OK] settings.json saved. Backup: $backup" -ForegroundColor Green
}

if (!$Mode) {
    Write-Host "Claude Code hook uninstaller"
    Write-Host "  1. Reset all custom hooks in $SettingsPath"
    Write-Host "  2. Uninstall only jarvis-claude-hook"
    $Mode = Read-Host "Choose 1 or 2"
}
if ($Mode -notin '1', '2') { throw "Invalid choice: $Mode" }

$s = $null
if (Test-Path $SettingsPath) {
    try { $s = Get-Content $SettingsPath -Raw | ConvertFrom-Json }
    catch { throw "settings.json is not valid JSON. Nothing was changed: $SettingsPath" }
    if ($null -eq $s) { throw "settings.json is empty. Nothing was changed: $SettingsPath" }
}

if ($Mode -eq '1') {
    if (!$s -or !$s.PSObject.Properties['hooks']) { Write-Host "[--] No custom hooks found" -ForegroundColor Cyan; exit 0 }
    Write-Host "Hooks to remove:" -ForegroundColor Yellow
    foreach ($evt in $s.hooks.PSObject.Properties) {
        foreach ($group in @($evt.Value)) {
            foreach ($h in @($group.hooks)) { Write-Host "  [$($evt.Name)] $($h.type): $($h.command)$($h.prompt)$($h.url)" }
        }
    }
    if ((Read-Host "Type RESET to remove every hook above") -cne 'RESET') { Write-Host "Cancelled."; exit 0 }

    $s.PSObject.Properties.Remove('hooks')
    Save-Settings $s
    Write-Host "Done. Script files, plugin hooks, and managed hooks are preserved." -ForegroundColor White
    exit 0
}

$removed = $false
if ($s -and $s.PSObject.Properties['hooks']) {
    foreach ($evt in @($s.hooks.PSObject.Properties.Name)) {
        $groups = @($s.hooks.$evt) | ForEach-Object {
            $group = $_
            $hooks = @($group.hooks | Where-Object { !(Test-ProjectHookCommand $_.command) })
            if ($hooks.Count -ne @($group.hooks).Count) { $removed = $true }
            if ($hooks.Count) { $group.hooks = $hooks; $group }
        }
        if (@($groups).Count) { $s.hooks.$evt = @($groups) } else { $s.hooks.PSObject.Properties.Remove($evt) }
    }
    if (!@($s.hooks.PSObject.Properties).Count) { $s.PSObject.Properties.Remove('hooks') }
}
if ($removed) { Save-Settings $s } else { Write-Host "[--] jarvis-claude-hook is not registered" -ForegroundColor Cyan }

$cfg = "$HooksDir\cc-notif-config.json"
if (Test-Path $cfg) {
    $cfgBackup = "$cfg.bak-$([guid]::NewGuid().ToString('N'))"
    Copy-Item $cfg $cfgBackup
    Write-Host "[OK] Config backup: $cfgBackup" -ForegroundColor Green
}

foreach ($name in $ProjectFiles) {
    $f = "$HooksDir\$name"
    if (Test-Path $f) {
        Remove-Item $f -Force
        Write-Host "[OK] Deleted: $f" -ForegroundColor Green
    }
}
$AppIdKey = 'HKCU:\Software\Classes\AppUserModelId\ClaudeCode.Notify'
if (Test-Path $AppIdKey) {
    Remove-Item $AppIdKey -Force
    Write-Host "[OK] Toast app ID removed: ClaudeCode.Notify" -ForegroundColor Green
}
Write-Host "Done. Other hooks are preserved." -ForegroundColor White
