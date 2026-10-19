function Test-ProjectHookCommand {
    param([string]$Command, [string]$UserProfile = $env:USERPROFILE)
    if ([string]::IsNullOrWhiteSpace($Command)) { return $false }
    $tokens = $null
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($Command, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { return $false }
    $commands = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] }, $true))
    if ($commands.Count -ne 1) { return $false }
    $elements = @($commands[0].CommandElements)
    $pathIndex = 0
    $executable = $elements[0].Extent.Text.Trim('"', "'")
    if ($executable -match '^(?i)(?:.*[\\/])?(?:powershell|pwsh)(?:\.exe)?$') {
        $pathIndex = -1
        for ($i = 1; $i -lt $elements.Count - 1; $i++) {
            if ($elements[$i].Extent.Text -ieq '-File') { $pathIndex = $i + 1; break }
        }
        if ($pathIndex -lt 0) { return $false }
    }
    $path = $elements[$pathIndex].Extent.Text.Trim('"', "'")
    $path = $path.Replace('${env:USERPROFILE}', $UserProfile).Replace('$env:USERPROFILE', $UserProfile).Replace('%USERPROFILE%', $UserProfile)
    if ($path -match '[$`]' -or ![IO.Path]::IsPathRooted($path)) { return $false }
    try {
        return [IO.Path]::GetFullPath($path) -ieq [IO.Path]::GetFullPath("$UserProfile\.claude\hooks\cc-notif.ps1")
    } catch { return $false }
}

function Test-MessageTemplate {
    param($Template, [int]$ArgumentCount = 1)
    if ($Template -isnot [string]) { return $false }
    $values = @('sample-agent', 'sample recap')[0..($ArgumentCount - 1)]
    try { $null = $Template -f $values; return $true } catch { return $false }
}

function Test-WholeNumber {
    param($Value)
    return $Value -is [int] -or $Value -is [long] -or $Value -is [int16] -or $Value -is [sbyte] -or $Value -is [byte]
}

function Test-SoundDuration {
    param($Value)
    return (Test-WholeNumber $Value) -and $Value -ge 0 -and $Value -le [int]::MaxValue
}

function Get-Recap {
    param($Text, [int]$MaxLength = 200)
    $recap = ([string]$Text -replace '[#*`_]', '' -replace '[\p{Cc}\p{Cf}]', ' ' -replace '\s+', ' ').Trim()
    if ($recap.Length -gt $MaxLength) { $recap = $recap.Substring(0, $MaxLength - 3) + '...' }
    return $recap
}

# PreToolUse payload for the Agent tool: tool_input carries subagent_type and description.
function Get-SubagentType {
    param($Payload)
    $t = Get-Recap $Payload.tool_input.subagent_type 100
    if ($t) { $t } else { 'general-purpose' }
}

function Get-SubagentTask {
    param($Payload)
    $t = Get-Recap $Payload.tool_input.description 80
    if ($t) { $t } else { Get-SubagentType $Payload }
}

function Get-SubagentBody {
    param($Payload, [string]$Name, [string]$Template)
    if (!(Test-MessageTemplate $Template 2)) { $Template = "{0} agent started in '{1}'" }
    return $Template -f (Get-SubagentType $Payload), $Name
}

function Get-StopBody {
    param([string]$Name, $LastMessage, [string]$Template, [bool]$ShowRecap)
    if (!(Test-MessageTemplate $Template)) { $Template = "Session '{0}' done!" }
    $body = $Template -f $Name
    if ($ShowRecap) {
        # Session name is already in the title.
        $recap = Get-Recap $LastMessage
        if ($recap) { $body = $recap }
    }
    return $body
}

function Test-SpeechRate {
    param($Value)
    return (Test-WholeNumber $Value) -and $Value -ge -10 -and $Value -le 10
}

# One recap speaks at a time. A second Stop event waits up to $WaitSeconds for the first, then skips.
function Invoke-Speech {
    param([string]$Text, [int]$Rate = 0, [string]$Voice = '', [int]$WaitSeconds = 30)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    $mutex = New-Object System.Threading.Mutex($false, 'Local\cc-notif-speech')
    $owned = $false
    try {
        try { $owned = $mutex.WaitOne([TimeSpan]::FromSeconds($WaitSeconds)) }
        catch [System.Threading.AbandonedMutexException] { $owned = $true }
        if (!$owned) { return $false }
        Add-Type -AssemblyName System.Speech
        $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
        try {
            if ($Voice) { try { $synth.SelectVoice($Voice) } catch {} }
            $synth.Rate = $Rate
            $synth.Volume = 100
            $synth.Speak($Text)
        } finally { $synth.Dispose() }
        return $true
    } finally {
        if ($owned) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}
