$ErrorActionPreference = "Stop"

$InstallFolder = Join-Path $env:LOCALAPPDATA "CK3WorkshopAutoUpdater"
$StartupFolder = [Environment]::GetFolderPath("Startup")
$ShortcutPath = Join-Path $StartupFolder "CK3 Workshop Auto Updater.lnk"
$DisabledShortcutPath = "$ShortcutPath.disabled"

foreach ($Path in @($ShortcutPath, $DisabledShortcutPath)) {
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Force
    }
}

if (Test-Path -LiteralPath $InstallFolder) {
    Remove-Item -LiteralPath $InstallFolder -Recurse -Force
}

Write-Host ""
Write-Host "CK3 Workshop Auto Updater was removed." -ForegroundColor Green
Write-Host "Steam itself and all Workshop subscriptions were left unchanged."
