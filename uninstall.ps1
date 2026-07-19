#Requires -Version 5.1
# uninstall.ps1 — Removes HibernateGuard: scheduled task, Claude Code hooks,
# desktop shortcut, and the install directory.
$ErrorActionPreference = 'Stop'
$installDir = Join-Path $env:LOCALAPPDATA 'HibernateGuard'
$taskName   = 'HibernateGuard'

Write-Host 'Removing scheduled task ...'
try {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
    Write-Host '  Done.' -ForegroundColor Green
} catch {
    Write-Host "  Task not found - skipped." -ForegroundColor Yellow
}

Write-Host 'Removing Claude Code hooks ...'
$settingsPath = Join-Path $env:USERPROFILE '.claude\settings.json'
if (Test-Path $settingsPath) {
    $json = Get-Content $settingsPath -Raw | ConvertFrom-Json
    $changed = $false
    if ($json.PSObject.Properties['hooks']) {
        foreach ($prop in @($json.hooks.PSObject.Properties)) {
            $kept = @($prop.Value | Where-Object {
                -not (($_ | ConvertTo-Json -Depth 10) -match 'HibernateGuard')
            })
            if ($kept.Count -ne @($prop.Value).Count) {
                $changed = $true
                if ($kept.Count -eq 0) { $json.hooks.PSObject.Properties.Remove($prop.Name) }
                else { $json.hooks.($prop.Name) = $kept }
            }
        }
    }
    if ($changed) {
        [IO.File]::WriteAllText($settingsPath, ($json | ConvertTo-Json -Depth 20))
        Write-Host '  Done.' -ForegroundColor Green
    } else {
        Write-Host '  No HibernateGuard hooks found - skipped.' -ForegroundColor Yellow
    }
}

Write-Host 'Removing desktop shortcut ...'
$lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Hibernate Guard Toggle.lnk'
if (Test-Path $lnk) { Remove-Item $lnk -Force }

Write-Host 'Removing install directory ...'
if (Test-Path $installDir) { Remove-Item $installDir -Recurse -Force }

Write-Host ''
Write-Host 'HibernateGuard uninstalled.' -ForegroundColor Green
