#Requires -Version 5.1
# watcher.ps1 — HibernateGuard: hibernate the PC when Claude Code is done and
# the user has been idle long enough. Runs once per invocation (Task Scheduler
# fires it every minute); a full run with countdown takes ~countdownSeconds.
#
# Test switches (never used by the scheduled task):
#   -SimulateIdleSeconds N   force the idle value; disables input auto-cancel
#   -CountdownOverrideSeconds N   shorten the popup countdown
param(
    [int]$SimulateIdleSeconds = 0,
    [int]$CountdownOverrideSeconds = 0
)
$ErrorActionPreference = 'Stop'

$baseDir    = $PSScriptRoot
$busyDir    = Join-Path $baseDir 'busy'
$pausedFlag = Join-Path $baseDir 'paused.flag'
$logFile    = Join-Path $baseDir 'watcher.log'
$config     = Get-Content (Join-Path $baseDir 'config.json') -Raw | ConvertFrom-Json

function Write-Log([string]$Message) {
    $line = '{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $Message
    Add-Content -Path $logFile -Value $line -Encoding UTF8
}

# keep the log from growing forever
if ((Test-Path $logFile) -and (Get-Item $logFile).Length -gt 1MB) {
    $tail = Get-Content $logFile -Tail 200
    Set-Content -Path $logFile -Value $tail -Encoding UTF8
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class HgIdle {
    [StructLayout(LayoutKind.Sequential)]
    struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [DllImport("user32.dll")]
    static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
    public static uint GetIdleMilliseconds() {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
        GetLastInputInfo(ref lii);
        return (uint)Environment.TickCount - lii.dwTime; // uint math survives TickCount wrap
    }
}
'@

function Get-IdleSeconds {
    if ($SimulateIdleSeconds -gt 0) { return $SimulateIdleSeconds }
    return [int]([HgIdle]::GetIdleMilliseconds() / 1000)
}

# Runs every pass regardless of idle state, so orphaned flags (crashed/killed
# sessions that never fired Stop) don't sit around simply because the machine
# stayed active and Test-Busy was never reached.
function Remove-StaleFlags {
    if (-not (Test-Path $busyDir)) { return }
    $staleBefore = (Get-Date).AddHours(-[double]$config.staleFlagHours)
    foreach ($f in Get-ChildItem $busyDir -Filter '*.flag' -ErrorAction SilentlyContinue) {
        if ($f.LastWriteTime -lt $staleBefore) {
            Write-Log "stale busy flag removed: $($f.Name) (last write $($f.LastWriteTime))"
            Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue
        }
    }
}

# $true = at least one (already-pruned) busy flag remains
function Test-Busy {
    if (-not (Test-Path $busyDir)) { return $false }
    return @(Get-ChildItem $busyDir -Filter '*.flag' -ErrorAction SilentlyContinue).Count -gt 0
}

# Popup with countdown + Cancel. Returns $true to proceed with hibernate.
# Any real user input during the countdown cancels it (idle counter resets).
function Show-CountdownPopup([int]$Seconds) {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $script:hgRemaining = $Seconds
    $script:hgProceed = $true
    $script:hgBaselineIdle = Get-IdleSeconds

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Hibernate Guard'
    $form.Size = New-Object System.Drawing.Size(440, 190)
    $form.StartPosition = 'CenterScreen'
    $form.TopMost = $true
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    $label = New-Object System.Windows.Forms.Label
    $label.AutoSize = $false
    $label.TextAlign = 'MiddleCenter'
    $label.Dock = 'Top'
    $label.Height = 90
    $label.Font = New-Object System.Drawing.Font('Segoe UI', 12)
    $label.Text = "Claude Code is done and you've been idle.`nHibernating in $script:hgRemaining s..."
    $form.Controls.Add($label)

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = 'Cancel'
    $btn.Width = 120
    $btn.Height = 34
    $btn.Left = [int](($form.ClientSize.Width - $btn.Width) / 2)
    $btn.Top = 100
    $btn.Add_Click({
        $script:hgProceed = $false
        $form.Close()
    })
    $form.Controls.Add($btn)

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 1000
    $timer.Add_Tick({
        $script:hgRemaining--
        # real input resets the idle counter -> current idle drops below baseline
        if ($SimulateIdleSeconds -eq 0 -and (Get-IdleSeconds) -lt $script:hgBaselineIdle) {
            $script:hgProceed = $false
            $form.Close()
            return
        }
        if ($script:hgRemaining -le 0) {
            $form.Close()
            return
        }
        $label.Text = "Claude Code is done and you've been idle.`nHibernating in $script:hgRemaining s..."
        $script:hgBaselineIdle = Get-IdleSeconds
    })
    $timer.Start()
    [void]$form.ShowDialog()
    $timer.Stop()
    $timer.Dispose()
    $form.Dispose()
    return $script:hgProceed
}

# ---- main: one check pass ------------------------------------------------------

if (Test-Path $pausedFlag) { exit 0 }

Remove-StaleFlags

$idleThreshold = [int]$config.idleMinutes * 60
$idle = Get-IdleSeconds
if ($idle -lt $idleThreshold) { exit 0 }

if (Test-Busy) {
    Write-Log "idle $([int]($idle / 60))m >= $($config.idleMinutes)m but a Claude session is busy - skip"
    exit 0
}

$countdown = [int]$config.countdownSeconds
if ($CountdownOverrideSeconds -gt 0) { $countdown = $CountdownOverrideSeconds }
Write-Log "idle $([int]($idle / 60))m, no busy session - showing $countdown s countdown"

if (-not (Show-CountdownPopup -Seconds $countdown)) {
    Write-Log 'countdown cancelled (user input or Cancel button)'
    exit 0
}

# conditions may have changed during the countdown - re-check everything
if (Test-Path $pausedFlag) { Write-Log 'paused during countdown - abort'; exit 0 }
if (Test-Busy)             { Write-Log 'session became busy during countdown - abort'; exit 0 }
if ((Get-IdleSeconds) -lt $idleThreshold) { Write-Log 'input detected during countdown - abort'; exit 0 }

if ($config.dryRun) {
    Write-Log 'DRY-RUN: would hibernate now (set dryRun=false in config.json to arm)'
    exit 0
}

Write-Log 'hibernating'
& shutdown.exe /h
if ($LASTEXITCODE -ne 0) {
    Write-Log "shutdown /h failed with exit code $LASTEXITCODE - will retry next cycle"
}
