# functional-test.ps1 — end-to-end run of the real scripts in a temporary profile.
# Installs, fires every hook event through the installed cc-notif.ps1, checks the toast body,
# then uninstalls. Toasts appear on screen. Never touches the real profile.
param([switch]$Speak)

$ErrorActionPreference = 'Stop'
if (!$Speak) { $env:CC_NOTIF_SILENT = '1' }
$Root = Split-Path $PSScriptRoot -Parent
$script:Failures = 0
$Profile = Join-Path ([IO.Path]::GetTempPath()) "cc-notif-functional-$([guid]::NewGuid().ToString('N'))"
$Hooks = "$Profile\.claude\hooks"

function Assert($Condition, [string]$Name) {
    if ($Condition) { Write-Host "PASS  $Name" -ForegroundColor Green }
    else { Write-Host "FAIL  $Name" -ForegroundColor Red; $script:Failures++ }
}

function Invoke-InProfile([string]$Command, [string]$InputText = '') {
    $cmd = "`$env:USERPROFILE='$Profile'; $Command; exit `$LASTEXITCODE"
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = $InputText | powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $cmd 2>&1
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = @($out) }
    } finally { $ErrorActionPreference = $previous }
}

try {
    New-Item -ItemType Directory -Force "$Profile\.claude" | Out-Null
    '{ "model": "opus" }' | Set-Content "$Profile\.claude\settings.json" -Encoding utf8

    $r = Invoke-InProfile "& '$Root\install.ps1'"
    Assert ($r.ExitCode -eq 0) 'install: completes'
    Assert ((Invoke-InProfile "& '$Root\verify.ps1' -Expect Installed").ExitCode -eq 0) 'verify: Installed'

    # Fixed config so the expected text is known.
    @{ title = 'Claude Code'; message = "Session '{0}' done!"; askMessage = "Session '{0}' needs your input"
       subagentMessage = "{0} agent started in '{1}'"; sound = ''; askSound = ''; subagentSound = ''
       soundDuration = 0; stopRecap = $true; speakRecap = [bool]$Speak; speechRate = 0; speechVoice = ''; locale = 'en' } |
        ConvertTo-Json | Set-Content "$Hooks\cc-notif-config.json" -Encoding utf8

    # Mirror notify.ps1's body logic through the installed helper so the check uses installed code.
    $bodyOf = {
        param($Event, $Payload)
        . "$Hooks\cc-notif-common.ps1"
        $j = $Payload | ConvertFrom-Json
        switch ($Event) {
            'Stop'         { Get-StopBody ($j.session_id.Substring(0, 8)) $j.last_assistant_message "Session '{0}' done!" $true }
            'Notification' { $j.message }
            'AgentStart'   { Get-SubagentBody $j ($j.session_id.Substring(0, 8)) "{0} agent started in '{1}'" }
        }
    }

    $cases = @(
        @{ Event = 'Stop'; Payload = '{"session_id":"func0001aaaa","last_assistant_message":"Added **verify.ps1** and 72 tests."}'
           Expect = 'Added verify.ps1 and 72 tests.' },
        @{ Event = 'Stop'; Payload = '{"session_id":"func0002bbbb","last_assistant_message":""}'
           Expect = "Session 'func0002' done!" },
        @{ Event = 'Notification'; Payload = '{"session_id":"func0003cccc","message":"Claude needs your permission to use Bash"}'
           Expect = 'Claude needs your permission to use Bash' },
        @{ Event = 'AgentStart'; Payload = '{"session_id":"func0004dddd","tool_name":"Agent","tool_input":{"subagent_type":"Explore","description":"Find config files"}}'
           Expect = "Explore agent started in 'func0004'" }
    )

    foreach ($c in $cases) {
        $body = & $bodyOf $c.Event $c.Payload
        Assert ($body -eq $c.Expect) "$($c.Event): body is '$body'"
        $started = Get-Date
        $r = Invoke-InProfile "& '$Hooks\cc-notif.ps1' -HookEvent $($c.Event)" $c.Payload
        $errors = @($r.Output | Where-Object { $_ -is [Management.Automation.ErrorRecord] })
        Assert ($r.ExitCode -eq 0 -and $errors.Count -eq 0) "$($c.Event): installed hook exits 0 with no errors ($([Math]::Round(((Get-Date) - $started).TotalSeconds, 1))s)"
    }

    $r = Invoke-InProfile "& '$Hooks\cc-notif.ps1' -HookEvent Stop" 'not json at all'
    Assert ($r.ExitCode -eq 0) 'Stop: malformed payload still exits 0'

    if ($Speak) {
        $payload = '{"session_id":"func0004dddd","last_assistant_message":"Functional test. Two recaps, one at a time."}'
        $a = Start-Job -ScriptBlock { param($p, $h, $in) $env:USERPROFILE = $p; $in | powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$h\cc-notif.ps1" -HookEvent Stop } -ArgumentList $Profile, $Hooks, $payload
        $b = Start-Job -ScriptBlock { param($p, $h, $in) $env:USERPROFILE = $p; $in | powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$h\cc-notif.ps1" -HookEvent Stop } -ArgumentList $Profile, $Hooks, $payload
        $done = Wait-Job $a, $b -Timeout 90
        Assert (@($done).Count -eq 2) 'speech: two overlapping Stop events both finish'
        Remove-Job $a, $b -Force
    }

    $r = Invoke-InProfile "& '$Root\uninstall.ps1' -Mode 2"
    Assert ($r.ExitCode -eq 0) 'uninstall: completes'
    Assert ((Invoke-InProfile "& '$Root\verify.ps1' -Expect ProjectRemoved").ExitCode -eq 0) 'verify: ProjectRemoved'
    $settings = Get-Content "$Profile\.claude\settings.json" -Raw | ConvertFrom-Json
    Assert ($settings.model -eq 'opus') 'uninstall: other settings kept'
}
finally {
    Remove-Item -LiteralPath $Profile -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
if ($script:Failures) { Write-Host "$script:Failures functional check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host "All functional checks passed" -ForegroundColor Green
exit 0
