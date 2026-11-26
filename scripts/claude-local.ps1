<#
.SYNOPSIS
    Runs Claude Code exactly like `claude`, but loads settings from
    ~/.claude/local-agent/settings.json instead of ~/.claude/settings.json.

.DESCRIPTION
    Windows. Linux and macOS use the `claude-local` shell script.

    Every argument is passed through unchanged to the real claude executable,
    so `claude-local -p "hi"`, `claude-local --bg ...`, `claude-local agents`
    etc. behave the same as their `claude` counterparts. stdin, stdout, stderr
    and the exit code are passed through as well, so it can be used as a
    subagent or background process.

    How it works:
      --setting-sources project,local   skips the user-level settings.json
      --settings <settings.json>        loads the local settings file instead
    Credentials (.credentials.json) are not settings and are still used as-is.

    Overrides:
      CLAUDE_LOCAL_SETTINGS  path to a different settings file to use.
      CLAUDE_CONFIG_DIR      Claude Code's config folder (default ~/.claude).
#>

$configDir = if ($env:CLAUDE_CONFIG_DIR) {
    $env:CLAUDE_CONFIG_DIR
} else {
    Join-Path $env:USERPROFILE '.claude'
}
$settingsFile = if ($env:CLAUDE_LOCAL_SETTINGS) {
    $env:CLAUDE_LOCAL_SETTINGS
} else {
    Join-Path $configDir 'local-agent\settings.json'
}

if (-not (Test-Path -LiteralPath $settingsFile -PathType Leaf)) {
    [Console]::Error.WriteLine("claude-local: settings file not found: $settingsFile")
    exit 1
}

# PATH first, then the folder this script was installed into (next to claude).
$claude = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1
if (-not $claude) {
    $claude = Get-Command (Join-Path $PSScriptRoot 'claude') -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
}
if (-not $claude) {
    [Console]::Error.WriteLine('claude-local: the claude executable was not found on PATH.')
    exit 1
}

# Claude Code does not apply the "env" block of a --settings file to the
# variables it reads at startup (e.g. ANTHROPIC_BASE_URL), so export them here.
try {
    $localSettings = Get-Content -LiteralPath $settingsFile -Raw | ConvertFrom-Json
} catch {
    # Do not echo the parser message: it quotes the file, which can contain secrets.
    [Console]::Error.WriteLine("claude-local: $settingsFile is not valid JSON. Fix it and retry.")
    exit 1
}

# Run with `&`, this script shares the caller's process, so remember every
# variable it changes and put it back afterwards.
$previousEnv = @{}
function Set-ScopedEnv([string]$name, $value) {
    if (-not $previousEnv.ContainsKey($name)) {
        $previousEnv[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    }
    [Environment]::SetEnvironmentVariable($name, $value, 'Process')
}

try {
    # The desktop app passes this to child processes. With it set, requests to
    # the local server fail with 401.
    Set-ScopedEnv 'CLAUDE_CODE_ENTRYPOINT' $null

    if ($localSettings.env) {
        foreach ($prop in $localSettings.env.PSObject.Properties) {
            Set-ScopedEnv $prop.Name ([string]$prop.Value)
        }
    }

    # Our flags go first; anything the caller passes is forwarded after them.
    & $claude.Source '--setting-sources' 'project,local' '--settings' (Resolve-Path -LiteralPath $settingsFile).Path @args
    $exitCode = $LASTEXITCODE
} finally {
    foreach ($name in $previousEnv.Keys) {
        [Environment]::SetEnvironmentVariable($name, $previousEnv[$name], 'Process')
    }
}
exit $exitCode
