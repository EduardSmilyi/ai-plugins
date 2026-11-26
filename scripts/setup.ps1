<#
.SYNOPSIS
    Installs claude-local and the local-agent skill on Windows.

.DESCRIPTION
    claude-local.ps1 is placed in the folder that holds claude, the skill in
    ~/.claude/skills/local-agent and the settings in ~/.claude/local-agent.
    Replaced files are kept with a .bak suffix. PATH is never changed.

    The settings are asked for in this terminal. Linux and macOS use setup.sh.

.PARAMETER Configure
    Ask for the settings again, even if they are filled in.

.PARAMETER InstallDir
    Install claude-local into this folder instead.
#>
param(
    [switch]$Configure,
    [string]$InstallDir
)

$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'setup: on Linux and macOS run: bash scripts/setup.sh'
}

$repo = Split-Path $PSScriptRoot
$configDir = if ($env:CLAUDE_CONFIG_DIR) {
    $env:CLAUDE_CONFIG_DIR
} else {
    Join-Path $env:USERPROFILE '.claude'
}
$settingsDir = Join-Path $configDir 'local-agent'
$settingsFile = Join-Path $settingsDir 'settings.json'
$oldSettingsFile = Join-Path $configDir 'settings-local.json'

if (-not $InstallDir) {
    $claude = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $claude) {
        throw 'setup: claude was not found on PATH. Install Claude Code, or pass -InstallDir.'
    }
    $InstallDir = Split-Path $claude.Source
}

function Install-File([string]$label, [string]$source, [string]$target) {
    if (-not (Test-Path -LiteralPath $target)) {
        Copy-Item -LiteralPath $source -Destination $target
        "${label}: installed at $target"
    } elseif ((Get-FileHash -LiteralPath $source).Hash -eq (Get-FileHash -LiteralPath $target).Hash) {
        "${label}: up to date at $target"
    } else {
        Copy-Item -LiteralPath $target -Destination "$target.bak" -Force
        Copy-Item -LiteralPath $source -Destination $target -Force
        "${label}: updated $target (previous copy: $target.bak)"
    }
}

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Install-File 'launcher' (Join-Path $PSScriptRoot 'claude-local.ps1') (Join-Path $InstallDir 'claude-local.ps1')
$onPath = ($env:PATH -split ';' | ForEach-Object { $_.TrimEnd('\') }) -contains $InstallDir.TrimEnd('\')
if (-not $onPath) {
    "path: $InstallDir is NOT on PATH. Add it to your user PATH, then restart your terminal."
}

$skillDir = Join-Path $configDir 'skills\local-agent'
New-Item -ItemType Directory -Force -Path $skillDir | Out-Null
Install-File 'skill' (Join-Path $repo 'skills\local-agent\SKILL.md') (Join-Path $skillDir 'SKILL.md')

New-Item -ItemType Directory -Force -Path $settingsDir | Out-Null
if (-not (Test-Path -LiteralPath $settingsFile) -and (Test-Path -LiteralPath $oldSettingsFile)) {
    Move-Item -LiteralPath $oldSettingsFile -Destination $settingsFile
    "settings: moved $oldSettingsFile to $settingsFile"
}

$template = Join-Path $repo 'settings.template.json'
$base = if (Test-Path -LiteralPath $settingsFile) { $settingsFile } else { $template }
try {
    $settings = Get-Content -LiteralPath $base -Raw | ConvertFrom-Json
} catch {
    # Do not echo the parser message: it quotes the file, which can contain secrets.
    throw "setup: $base is not valid JSON. Fix or delete it and run setup again."
}
if (-not $settings.env) {
    $settings | Add-Member -NotePropertyName env -NotePropertyValue ([pscustomobject]@{}) -Force
}

# Current value of a variable, or nothing if it is missing or still a <placeholder>.
function Get-Value([string]$name) {
    $value = [string]$settings.env.$name
    if ($value -notmatch '^<.*>$') { $value }
}

function Set-Value([string]$name, [string]$value) {
    $settings.env | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force
}

$filled = (Get-Value 'ANTHROPIC_BASE_URL') -and (Get-Value 'ANTHROPIC_MODEL')
$interactive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected

if (-not $Configure -and -not $interactive) {
    if (-not (Test-Path -LiteralPath $settingsFile)) {
        Copy-Item -LiteralPath $template -Destination $settingsFile
    }
    if ($filled) {
        "settings: $settingsFile kept"
    } else {
        "settings: $settingsFile is not filled in. Run this script in a terminal to answer the questions."
    }
    return
}

if (-not $Configure -and $filled) {
    if ((Read-Host "Settings already exist at $settingsFile. Change them? [y/N]") -notmatch '^[Yy]') {
        "settings: $settingsFile kept"
        return
    }
}

function Read-Setting([string]$prompt, [string]$default, [string]$pattern) {
    while ($true) {
        $label = if ($default) { "$prompt [$default]" } else { $prompt }
        $answer = ([string](Read-Host $label)).Trim()
        if (-not $answer) { $answer = $default }
        if ($answer -match $pattern) { return $answer }
        # Without a terminal a retry would loop forever.
        if (-not $answer -and [Console]::IsInputRedirected) {
            throw 'setup: input ended; settings were not changed.'
        }
        Write-Host '  Not a valid value, try again.'
    }
}

Write-Host ''
Write-Host 'Local model settings (press Enter to keep the value in brackets).'
$url = Read-Setting 'Server URL, e.g. http://localhost:1234' (Get-Value 'ANTHROPIC_BASE_URL') '^https?://.+'

$oldToken = Get-Value 'ANTHROPIC_AUTH_TOKEN'
$hint = if ($oldToken) { 'Enter keeps the current one' } else { 'Enter if the server needs none' }
$secure = Read-Host "Server token, input hidden ($hint)" -AsSecureString
$token = (New-Object System.Net.NetworkCredential('', $secure)).Password
if (-not $token) { $token = if ($oldToken) { $oldToken } else { 'local' } }

$oldModel = Get-Value 'ANTHROPIC_MODEL'
$model = Read-Setting 'Model name' $oldModel '^[^<\s]+$'

$context = Get-Value 'CLAUDE_CODE_MAX_CONTEXT_TOKENS'
if (-not $context) { $context = '204800' }
$context = Read-Setting 'Context window, tokens' $context '^[1-9]\d*$'

$output = Get-Value 'CLAUDE_CODE_MAX_OUTPUT_TOKENS'
if (-not $output) { $output = '25600' }
$output = Read-Setting 'Max output, tokens' $output '^[1-9]\d*$'

Set-Value 'ANTHROPIC_BASE_URL' $url
Set-Value 'ANTHROPIC_AUTH_TOKEN' $token
Set-Value 'ANTHROPIC_MODEL' $model
foreach ($name in 'ANTHROPIC_SMALL_FAST_MODEL', 'ANTHROPIC_DEFAULT_SONNET_MODEL',
    'ANTHROPIC_DEFAULT_OPUS_MODEL', 'ANTHROPIC_DEFAULT_HAIKU_MODEL') {
    # Keep a hand-set per-tier model unless the main model changed.
    if ($model -cne $oldModel -or -not (Get-Value $name)) { Set-Value $name $model }
}
Set-Value 'CLAUDE_CODE_MAX_CONTEXT_TOKENS' $context
Set-Value 'CLAUDE_CODE_MAX_OUTPUT_TOKENS' $output

# No BOM, so that every JSON reader accepts the file.
[IO.File]::WriteAllText($settingsFile, (ConvertTo-Json $settings -Depth 20), (New-Object Text.UTF8Encoding($false)))
"settings: saved to $settingsFile"
