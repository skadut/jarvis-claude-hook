# run-tests.ps1 — assertion tests against temporary USERPROFILE folders. Never touches the real profile.
$ErrorActionPreference = 'Stop'
$env:CC_NOTIF_SILENT = '1'
$Root = Split-Path $PSScriptRoot -Parent
. "$Root\hook-common.ps1"
$script:Failures = 0
$TempRoot = Join-Path ([IO.Path]::GetTempPath()) "cc-notif-tests-$([guid]::NewGuid().ToString('N'))"

function Assert($Condition, [string]$Name) {
    if ($Condition) { Write-Host "PASS  $Name" -ForegroundColor Green }
    else { Write-Host "FAIL  $Name" -ForegroundColor Red; $script:Failures++ }
}

function New-Profile([string]$Name) {
    $p = Join-Path $TempRoot $Name
    New-Item -ItemType Directory -Force "$p\.claude\hooks" | Out-Null
    return $p
}

function Write-Settings([string]$ProfilePath, $Object) {
    $Object | ConvertTo-Json -Depth 20 | Set-Content "$ProfilePath\.claude\settings.json" -Encoding utf8
}

function Read-Settings([string]$ProfilePath) {
    Get-Content "$ProfilePath\.claude\settings.json" -Raw | ConvertFrom-Json
}

function Invoke-Script([string]$ProfilePath, [string]$ScriptName, [string]$Arguments = '', [string]$InputText = '') {
    $cmd = "`$env:USERPROFILE='$ProfilePath'; & '$Root\$ScriptName' $Arguments; exit `$LASTEXITCODE"
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = $InputText | powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $cmd 2>&1
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previous }
    return [pscustomobject]@{ ExitCode = $code; Output = ($output -join "`n") }
}

function Get-Commands($Settings, [string]$Event) {
    if (!$Settings.hooks -or !$Settings.hooks.PSObject.Properties[$Event]) { return @() }
    @($Settings.hooks.$Event | ForEach-Object { $_.hooks } | ForEach-Object { $_.command })
}

try {
    $canonical = '& "$env:USERPROFILE\.claude\hooks\cc-notif.ps1" -HookEvent Stop'

    # --- Matcher ---
    $p = 'C:\Users\tester'
    Assert (Test-ProjectHookCommand $canonical $p) 'matcher: installer-style command'
    Assert (Test-ProjectHookCommand '& "$env:USERPROFILE\.claude\hooks\cc-notif.ps1"' $p) 'matcher: legacy command without event'
    Assert (Test-ProjectHookCommand '& "C:\Users\tester\.claude\hooks\cc-notif.ps1" -HookEvent Stop' $p) 'matcher: absolute quoted path'
    Assert (Test-ProjectHookCommand 'powershell -ExecutionPolicy Bypass -File "C:\Users\tester\.claude\hooks\cc-notif.ps1" -HookEvent Stop' $p) 'matcher: powershell -File form'
    Assert (Test-ProjectHookCommand 'powershell.exe -File C:\Users\tester\.claude\hooks\cc-notif.ps1' $p) 'matcher: unquoted -File path'
    Assert (!(Test-ProjectHookCommand '& "$env:USERPROFILE\.claude\hooks\cc-notif-old.ps1"' $p)) 'matcher: rejects similarly named script'
    Assert (!(Test-ProjectHookCommand '& "$env:USERPROFILE\.claude\hooks\on-stop.ps1"' $p)) 'matcher: rejects unrelated script'
    Assert (!(Test-ProjectHookCommand '& "C:\Other\.claude\hooks\cc-notif.ps1"' $p)) 'matcher: rejects other profile path'
    Assert (!(Test-ProjectHookCommand 'echo cc-notif.ps1' $p)) 'matcher: rejects mention in another command'
    Assert (!(Test-ProjectHookCommand '' $p)) 'matcher: rejects empty command'

    # --- Templates and duration ---
    Assert (Test-MessageTemplate "Session '{0}' done!") 'template: placeholder'
    Assert (Test-MessageTemplate 'Done.') 'template: static text'
    Assert (Test-MessageTemplate 'Braces {{ok}} {0}') 'template: escaped braces'
    Assert (!(Test-MessageTemplate 'Done {')) 'template: rejects unbalanced brace'
    Assert (!(Test-MessageTemplate '{1}')) 'template: rejects missing argument'
    Assert (Test-MessageTemplate '{0}: {1}' 2) 'template: two-argument subagent form'
    Assert (!(Test-MessageTemplate $null)) 'template: rejects null'
    Assert (Test-SoundDuration 0) 'duration: zero allowed'
    Assert (Test-SoundDuration 5) 'duration: positive integer'
    Assert (!(Test-SoundDuration (-1))) 'duration: rejects negative'
    Assert (!(Test-SoundDuration 2.5)) 'duration: rejects fraction'
    Assert (!(Test-SoundDuration 'abc')) 'duration: rejects string'
    Assert (!(Test-SoundDuration $null)) 'duration: rejects null'

    # --- Agent start (PreToolUse on the Agent tool) ---
    $full = [pscustomobject]@{ tool_name = 'Agent'; tool_input = [pscustomobject]@{ subagent_type = 'Explore'; description = 'Find **config** files' } }
    Assert ((Get-SubagentTask $full) -eq 'Find config files') 'agent start: task from description'
    Assert ((Get-SubagentBody $full 'my-project' "{0} agent started in '{1}'") -eq "Explore agent started in 'my-project'") 'agent start: body'
    $bare = [pscustomobject]@{ tool_input = [pscustomobject]@{} }
    Assert ((Get-SubagentTask $bare) -eq 'general-purpose') 'agent start: missing description falls back to type'
    Assert ((Get-SubagentBody $bare 'p' 'Done {') -eq "general-purpose agent started in 'p'") 'agent start: invalid template falls back'
    Assert ((Get-SubagentTask ([pscustomobject]@{ tool_input = [pscustomobject]@{ description = ('x' * 200) } })).Length -eq 80) 'agent start: task bounded to 80'

    # --- Stop recap ---
    $b = Get-StopBody 'my-project' 'Added **verify.ps1** and tests.' "Session '{0}' done!" $true
    Assert ($b -eq 'Added verify.ps1 and tests.') "stop: recap replaces template ($b)"
    $b = Get-StopBody 'my-project' '' "Session '{0}' done!" $true
    Assert ($b -eq "Session 'my-project' done!") 'stop: empty reply falls back to template'
    $b = Get-StopBody 'my-project' 'Some reply' "Session '{0}' done!" $false
    Assert ($b -eq "Session 'my-project' done!") 'stop: recap off keeps template'
    $b = Get-StopBody 'my-project' $null 'Done {' $true
    Assert ($b -eq "Session 'my-project' done!") 'stop: invalid template falls back'
    $b = Get-StopBody 'p' ('x' * 500) "{0}" $true
    Assert ($b.Length -eq 200 -and $b.EndsWith('...')) "stop: recap bounded to 200 characters (length $($b.Length))"
    Assert ((Get-Recap "## Title`r`n`r`n- one`n- two") -eq 'Title - one - two') 'recap: markdown and line breaks removed'

    # --- Speech settings and lock ---
    Assert (Test-SpeechRate 0) 'speech rate: zero'
    Assert (Test-SpeechRate (-10)) 'speech rate: minimum'
    Assert (Test-SpeechRate 10) 'speech rate: maximum'
    Assert (!(Test-SpeechRate 11)) 'speech rate: rejects above range'
    Assert (!(Test-SpeechRate 1.5)) 'speech rate: rejects fraction'
    Assert (!(Test-SpeechRate 'fast')) 'speech rate: rejects string'
    Assert (!(Invoke-Speech '' 0 '' 1)) 'speech: empty text is not spoken'

    $holder = Start-Job -ScriptBlock {
        $m = New-Object System.Threading.Mutex($false, 'Local\cc-notif-speech')
        [void]$m.WaitOne()
        Start-Sleep -Seconds 6
        $m.ReleaseMutex()
        $m.Dispose()
    }
    Start-Sleep -Seconds 2
    $started = Get-Date
    $spoke = Invoke-Speech 'should not play' 0 '' 1
    $waited = ((Get-Date) - $started).TotalSeconds
    Assert (!$spoke -and $waited -ge 0.9 -and $waited -lt 4) "speech lock: second recap waits then skips ($([Math]::Round($waited, 1))s)"
    Wait-Job $holder -Timeout 15 | Out-Null
    Remove-Job $holder -Force

    # --- Install / uninstall ---
    $prof = New-Profile 'install'
    $unrelated = [pscustomobject]@{ type = 'command'; command = 'echo other-tool' }
    Write-Settings $prof @{ model = 'opus'; hooks = @{ Stop = @(@{ hooks = @($unrelated) }) } }
    $r = Invoke-Script $prof 'install.ps1'
    Assert ($r.ExitCode -eq 0) 'install: exit code 0'
    $s = Read-Settings $prof
    Assert ((Get-Commands $s 'Stop') -contains 'echo other-tool') 'install: keeps unrelated hook'
    foreach ($evt in 'Stop', 'Notification', 'PreToolUse') {
        Assert (@(Get-Commands $s $evt | Where-Object { Test-ProjectHookCommand $_ $prof }).Count -eq 1) "install: registers $evt once"
    }
    Assert (Test-Path "$prof\.claude\hooks\cc-notif-common.ps1") 'install: copies helper script'
    Assert (@(Get-Commands $s 'Stop' | Where-Object { $_ -match '-ExecutionPolicy Bypass -File' }).Count -eq 1) 'install: hook command bypasses execution policy'

    # Upgrade rewrites an old command that a blocked execution policy would stop
    $prof = New-Profile 'upgrade-policy'
    Write-Settings $prof @{ hooks = @{ Stop = @(@{ hooks = @(@{ type = 'command'; command = '& "$env:USERPROFILE\.claude\hooks\cc-notif.ps1" -HookEvent Stop'; shell = 'powershell'; async = $true }) }) } }
    Invoke-Script $prof 'install.ps1' | Out-Null
    $cmds = @(Get-Commands (Read-Settings $prof) 'Stop')
    Assert ($cmds.Count -eq 1 -and $cmds[0] -match '-ExecutionPolicy Bypass -File') 'install: upgrades old command in place, no duplicate'
    Write-Settings $prof @{ hooks = @{ SubagentStop = @(@{ hooks = @(@{ type = 'command'; command = 'powershell.exe -NoProfile -File "$env:USERPROFILE\.claude\hooks\cc-notif.ps1" -HookEvent SubagentStop' }, @{ type = 'command'; command = 'echo keep-me' }) }) } }
    Invoke-Script $prof 'install.ps1' | Out-Null
    $s = Read-Settings $prof
    Assert (@(Get-Commands $s 'SubagentStop') -join '|' -eq 'echo keep-me') 'install: drops old SubagentStop hook, keeps others'
    Assert (@($s.hooks.PreToolUse)[0].matcher -eq 'Agent|Task') 'install: PreToolUse matches Agent tool'
    Write-Settings $prof @{}
    Invoke-Script $prof 'install.ps1' | Out-Null
    $installed = @(Get-Commands (Read-Settings $prof) 'Stop')[0].Replace('$env:USERPROFILE', $prof)
    '{"soundDuration":0}' | Set-Content "$prof\.claude\hooks\cc-notif-config.json"
    $previous = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $out = '{"session_id":"policy01"}' | powershell.exe -NoProfile -ExecutionPolicy Restricted -Command $installed 2>&1
    $ErrorActionPreference = $previous
    Assert (!($out | Select-String 'disabled on this system') -and $LASTEXITCODE -eq 0) 'install: hook runs under Restricted policy'
    $prof = New-Profile 'install'
    Write-Settings $prof @{ model = 'opus'; hooks = @{ Stop = @(@{ hooks = @($unrelated) }) } }
    Invoke-Script $prof 'install.ps1' | Out-Null
    $s = Read-Settings $prof
    Invoke-Script $prof 'install.ps1' | Out-Null
    $s = Read-Settings $prof
    Assert (@(Get-Commands $s 'Stop' | Where-Object { Test-ProjectHookCommand $_ $prof }).Count -eq 1) 'install: repeat is idempotent'
    Assert ((Invoke-Script $prof 'verify.ps1' '-Expect Installed').ExitCode -eq 0) 'verify: Installed passes after install'

    $r = Invoke-Script $prof 'uninstall.ps1' '-Mode 2'
    Assert ($r.ExitCode -eq 0) 'uninstall 2: exit code 0'
    $s = Read-Settings $prof
    Assert ((Get-Commands $s 'Stop') -contains 'echo other-tool') 'uninstall 2: keeps unrelated hook in same event'
    Assert (!$s.hooks.PSObject.Properties['Notification']) 'uninstall 2: removes emptied event'
    Assert ($s.model -eq 'opus') 'uninstall 2: keeps other settings'
    Assert (!(Test-Path "$prof\.claude\hooks\cc-notif.ps1")) 'uninstall 2: deletes hook script'
    Assert (@(Get-ChildItem "$prof\.claude\hooks\cc-notif-config.json.bak-*").Count -eq 1) 'uninstall 2: backs up config'
    Assert (@(Get-ChildItem "$prof\.claude\settings.json.bak-*").Count -ge 1) 'uninstall 2: backs up settings'
    Assert ((Invoke-Script $prof 'verify.ps1' '-Expect ProjectRemoved').ExitCode -eq 0) 'verify: ProjectRemoved passes'
    Assert ((Invoke-Script $prof 'verify.ps1' '-Expect Installed').ExitCode -ne 0) 'verify: Installed fails after removal'
    Assert ((Invoke-Script $prof 'verify.ps1' '-Expect GlobalHooksReset').ExitCode -ne 0) 'verify: GlobalHooksReset fails while hooks remain'

    # Same group shared with another hook, absolute path form
    $prof = New-Profile 'shared-group'
    $abs = "& `"$prof\.claude\hooks\cc-notif.ps1`" -HookEvent Stop"
    Write-Settings $prof @{ hooks = @{ Stop = @(@{ hooks = @(@{ type = 'command'; command = $abs }, @{ type = 'command'; command = 'echo keep' }) }) } }
    Invoke-Script $prof 'uninstall.ps1' '-Mode 2' | Out-Null
    $s = Read-Settings $prof
    Assert ((Get-Commands $s 'Stop') -join '|' -eq 'echo keep') 'uninstall 2: absolute path removed, sibling hook kept'

    # Missing settings: still cleans project files
    $prof = New-Profile 'missing-settings'
    'x' | Set-Content "$prof\.claude\hooks\cc-notif.ps1"
    $r = Invoke-Script $prof 'uninstall.ps1' '-Mode 2'
    Assert ($r.ExitCode -eq 0 -and !(Test-Path "$prof\.claude\hooks\cc-notif.ps1")) 'uninstall 2: cleans files without settings.json'

    # Malformed settings: stops, deletes nothing, rewrites nothing
    $prof = New-Profile 'malformed'
    '{ not json' | Set-Content "$prof\.claude\settings.json"
    'x' | Set-Content "$prof\.claude\hooks\cc-notif.ps1"
    $r = Invoke-Script $prof 'uninstall.ps1' '-Mode 2'
    Assert ($r.ExitCode -ne 0) 'uninstall 2: malformed settings fails'
    Assert (Test-Path "$prof\.claude\hooks\cc-notif.ps1") 'uninstall 2: malformed settings deletes nothing'
    Assert ((Get-Content "$prof\.claude\settings.json" -Raw).Trim() -eq '{ not json') 'uninstall 2: malformed settings unchanged'
    Assert ((Invoke-Script $prof 'verify.ps1' '-Expect ProjectRemoved').ExitCode -ne 0) 'verify: malformed settings is a failure'

    # Reset mode
    $prof = New-Profile 'reset'
    Write-Settings $prof @{ model = 'opus'; hooks = @{ Stop = @(@{ hooks = @($unrelated) }) } }
    'x' | Set-Content "$prof\.claude\hooks\on-stop.ps1"
    Invoke-Script $prof 'uninstall.ps1' '-Mode 1' 'nope' | Out-Null
    Assert ((Read-Settings $prof).hooks) 'uninstall 1: wrong confirmation cancels'
    Invoke-Script $prof 'uninstall.ps1' '-Mode 1' 'RESET' | Out-Null
    $s = Read-Settings $prof
    Assert (!$s.PSObject.Properties['hooks'] -and $s.model -eq 'opus') 'uninstall 1: RESET removes hooks, keeps settings'
    Assert (Test-Path "$prof\.claude\hooks\on-stop.ps1") 'uninstall 1: keeps script files'
    Assert ((Invoke-Script $prof 'verify.ps1' '-Expect GlobalHooksReset').ExitCode -eq 0) 'verify: GlobalHooksReset passes'

    # Verify is read-only
    $before = (Get-FileHash "$prof\.claude\settings.json").Hash
    Invoke-Script $prof 'verify.ps1' | Out-Null
    Assert ((Get-FileHash "$prof\.claude\settings.json").Hash -eq $before) 'verify: does not modify settings'
}
finally {
    Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
if ($script:Failures) { Write-Host "$script:Failures test(s) failed" -ForegroundColor Red; exit 1 }
Write-Host "All tests passed" -ForegroundColor Green
exit 0
