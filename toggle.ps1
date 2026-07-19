#Requires -Version 5.1
# toggle.ps1 — pause/resume HibernateGuard by toggling paused.flag.
# Bound to the "Hibernate Guard Toggle" desktop shortcut.
$ErrorActionPreference = 'Stop'
$baseDir = Join-Path $env:LOCALAPPDATA 'HibernateGuard'
$pausedFlag = Join-Path $baseDir 'paused.flag'

Add-Type -AssemblyName System.Windows.Forms

if (Test-Path $pausedFlag) {
    Remove-Item $pausedFlag -Force
    [void][System.Windows.Forms.MessageBox]::Show(
        'Hibernate Guard is now ACTIVE.', 'Hibernate Guard',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information)
} else {
    if (-not (Test-Path $baseDir)) { New-Item -ItemType Directory -Path $baseDir -Force | Out-Null }
    Set-Content -Path $pausedFlag -Value (Get-Date -Format o)
    [void][System.Windows.Forms.MessageBox]::Show(
        'Hibernate Guard is now PAUSED. Run the toggle again to resume.', 'Hibernate Guard',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning)
}
