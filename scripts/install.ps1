<#
.SYNOPSIS
    Downloads claude-local-agent from GitHub and runs its setup on Windows.

.DESCRIPTION
    irm https://raw.githubusercontent.com/EduardSmilyi/claude-local-agent/main/scripts/install.ps1 | iex

    No clone or git is needed. The download is removed afterwards.
    Linux and macOS use install.sh.

.PARAMETER Configure
    Ask for the settings again, even if they are filled in.

.PARAMETER InstallDir
    Install claude-local into this folder instead.
#>
param(
    [switch]$Configure,
    [string]$InstallDir
)

# A child scope, so that `| iex` leaves the caller's session untouched.
# `throw` rather than `exit`, which would close that session.
& {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'

    if ($env:OS -ne 'Windows_NT') {
        throw 'install: on Linux and macOS use scripts/install.sh.'
    }

    $url = 'https://github.com/EduardSmilyi/claude-local-agent/archive/refs/heads/main.zip'
    $work = Join-Path ([IO.Path]::GetTempPath()) ('claude-local-agent-' + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $work | Out-Null
    try {
        # Windows PowerShell 5.1 does not always offer TLS 1.2, which GitHub requires.
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $zip = Join-Path $work 'source.zip'
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
        Expand-Archive -LiteralPath $zip -DestinationPath $work

        $setup = Get-ChildItem -LiteralPath $work -Directory |
            ForEach-Object { Join-Path $_.FullName 'scripts\setup.ps1' } |
            Where-Object { Test-Path -LiteralPath $_ } |
            Select-Object -First 1
        if (-not $setup) {
            throw 'install: the download does not contain scripts/setup.ps1.'
        }

        $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $setup)
        if ($Configure) { $arguments += '-Configure' }
        if ($InstallDir) { $arguments += '-InstallDir', $InstallDir }

        # The same PowerShell as the caller's: 5.1 started from 7 can fail to
        # load its own modules.
        $shell = (Get-Process -Id $PID).Path
        if ((Split-Path $shell -Leaf) -notmatch '^(powershell|pwsh)\.exe$') { $shell = 'powershell' }
        & $shell @arguments
        if ($LASTEXITCODE -ne 0) {
            throw 'install: setup failed.'
        }
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}
