#Requires -Version 5.1
# hibernate-hook.ps1 — Claude Code hook: track whether a session is mid-turn.
#   UserPromptSubmit -> -Action busy  (create busy\<session_id>.flag)
#   Stop/SessionEnd  -> -Action idle  (remove the flag)
# Must never block Claude Code: always exits 0, swallows all errors.
param(
    [Parameter(Mandatory)][ValidateSet('busy', 'idle')][string]$Action
)
$ErrorActionPreference = 'SilentlyContinue'
try {
    $raw = [Console]::In.ReadToEnd()
    $sid = ''
    if ($raw) {
        $obj = $raw | ConvertFrom-Json
        $sid = [string]$obj.session_id
    }
    if (-not $sid) { exit 0 }
    # session_id becomes a filename — strip anything path-unsafe
    $sid = $sid -replace '[^\w\-]', ''
    if (-not $sid) { exit 0 }

    $busyDir = Join-Path $env:LOCALAPPDATA 'HibernateGuard\busy'
    $flag = Join-Path $busyDir "$sid.flag"
    if ($Action -eq 'busy') {
        if (-not (Test-Path $busyDir)) {
            New-Item -ItemType Directory -Path $busyDir -Force | Out-Null
        }
        Set-Content -Path $flag -Value (Get-Date -Format o)
    } else {
        if (Test-Path $flag) { Remove-Item $flag -Force }
    }
} catch {}
exit 0
