#Requires -Version 5.1
# install.ps1 — Installs HibernateGuard. No administrator rights required.
# Non-interactive; safe to re-run (idempotent).
$ErrorActionPreference = 'Stop'
$installDir = Join-Path $env:LOCALAPPDATA 'HibernateGuard'
$srcDir     = $PSScriptRoot
$taskName   = 'HibernateGuard'

Write-Host ''
Write-Host 'HibernateGuard Installer' -ForegroundColor Cyan
Write-Host '========================' -ForegroundColor Cyan

# -- 1. Copy files ---------------------------------------------------------------
Write-Host "Copying files to $installDir ..."
if (-not (Test-Path $installDir)) { New-Item -ItemType Directory -Path $installDir | Out-Null }
if (-not (Test-Path "$installDir\busy")) { New-Item -ItemType Directory -Path "$installDir\busy" | Out-Null }
foreach ($f in 'watcher.ps1', 'hibernate-hook.ps1', 'toggle.ps1') {
    Copy-Item "$srcDir\$f" "$installDir\$f" -Force
}
# keep existing config on re-install
if (-not (Test-Path "$installDir\config.json")) {
    Copy-Item "$srcDir\config.json" "$installDir\config.json"
}
Write-Host '  Done.' -ForegroundColor Green

# -- 2. Scheduled task (every minute, hidden, current user) ----------------------
Write-Host "Registering scheduled task '$taskName' ..."
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$installDir\watcher.ps1`"" `
    -WorkingDirectory $installDir
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
    -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration (New-TimeSpan -Days 3650)
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -StartWhenAvailable `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
    -Settings $settings -Description 'HibernateGuard: hibernate when Claude Code is done and user is idle' `
    -Force | Out-Null
Write-Host '  Done.' -ForegroundColor Green

# -- 3. Patch Claude Code hooks into ~/.claude/settings.json ---------------------
Write-Host 'Patching Claude Code hooks (~/.claude/settings.json) ...'
$settingsPath = Join-Path $env:USERPROFILE '.claude\settings.json'
$backupPath   = "$settingsPath.hibernateguard.bak"
$json = Get-Content $settingsPath -Raw | ConvertFrom-Json
if (-not $json.PSObject.Properties['hooks']) {
    $json | Add-Member -MemberType NoteProperty -Name hooks -Value ([pscustomobject]@{})
}

function New-HookEntry([string]$HookAction) {
    [pscustomobject]@{
        matcher = ''
        hooks   = @([pscustomobject]@{
            type    = 'command'
            command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$installDir\hibernate-hook.ps1`" -Action $HookAction"
        })
    }
}

$patched = $false
foreach ($evt in @(
    @{ Name = 'UserPromptSubmit'; HookAction = 'busy' },
    @{ Name = 'Stop';             HookAction = 'idle' },
    @{ Name = 'SessionEnd';       HookAction = 'idle' }
)) {
    $name = $evt.Name
    $existing = $json.hooks.PSObject.Properties[$name]
    if ($null -eq $existing) {
        $json.hooks | Add-Member -MemberType NoteProperty -Name $name -Value @(New-HookEntry $evt.HookAction)
        $patched = $true
    } elseif (-not (($existing.Value | ConvertTo-Json -Depth 10) -match 'HibernateGuard')) {
        $json.hooks.$name = @($existing.Value) + @(New-HookEntry $evt.HookAction)
        $patched = $true
    }
}
if ($patched) {
    Copy-Item $settingsPath $backupPath -Force
    [IO.File]::WriteAllText($settingsPath, ($json | ConvertTo-Json -Depth 20))
    Write-Host "  Done (backup: $backupPath)." -ForegroundColor Green
} else {
    Write-Host '  Hooks already present - skipped.' -ForegroundColor Green
}

# -- 4. Desktop toggle shortcut --------------------------------------------------
Write-Host "Creating 'Hibernate Guard Toggle' desktop shortcut ..."
try {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $shell = New-Object -ComObject WScript.Shell
    $sc = $shell.CreateShortcut("$desktop\Hibernate Guard Toggle.lnk")
    $sc.TargetPath       = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
    $sc.Arguments        = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$installDir\toggle.ps1`""
    $sc.WorkingDirectory = $installDir
    $sc.IconLocation     = 'powercpl.dll,0'
    $sc.WindowStyle      = 7
    $sc.Save()
    Write-Host '  Done.' -ForegroundColor Green
} catch {
    Write-Host "  Could not create desktop shortcut: $_" -ForegroundColor Yellow
}

# -- 5. Verify hibernate support (locale-independent registry check) -------------
Write-Host 'Checking hibernate support ...'
$pwr = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -ErrorAction SilentlyContinue
$hib = $pwr.HibernateEnabled
if ($null -eq $hib) { $hib = $pwr.HibernateEnabledDefault }  # absent = OS default applies
if ($hib -eq 1) {
    Write-Host '  Hibernate is enabled.' -ForegroundColor Green
} else {
    Write-Host '  WARNING: Hibernate appears DISABLED. Run as admin:  powercfg /hibernate on' -ForegroundColor Yellow
}

# -- 6. Summary ------------------------------------------------------------------
$cfg = Get-Content "$installDir\config.json" -Raw | ConvertFrom-Json
Write-Host ''
Write-Host '================================================' -ForegroundColor Cyan
Write-Host ' Installation complete!' -ForegroundColor Green
Write-Host "  Installed to : $installDir"
Write-Host "  Idle limit   : $($cfg.idleMinutes) min, countdown $($cfg.countdownSeconds) s"
if ($cfg.dryRun) {
    Write-Host '  Mode         : DRY-RUN (logs only, no real hibernate)' -ForegroundColor Yellow
    Write-Host "  Arm it later : set dryRun=false in $installDir\config.json" -ForegroundColor Yellow
} else {
    Write-Host '  Mode         : ARMED (will really hibernate)' -ForegroundColor Green
}
Write-Host "  Activity log : $installDir\watcher.log"
Write-Host '  Pause/resume : desktop shortcut "Hibernate Guard Toggle"'
Write-Host '  NOTE: hooks take effect in NEW Claude Code sessions only.'
Write-Host '================================================' -ForegroundColor Cyan
