$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path $PSScriptRoot -Parent
$SourceFolder = Join-Path $ProjectRoot "src"
$InstallFolder = Join-Path $env:LOCALAPPDATA "CK3WorkshopAutoUpdater"
$DataFolder = Join-Path $InstallFolder "data"
$StartupFolder = [Environment]::GetFolderPath("Startup")
$ShortcutPath = Join-Path $StartupFolder "CK3 Workshop Auto Updater.lnk"
$DisabledShortcutPath = "$ShortcutPath.disabled"

$PowerShellPath = $null

$PowerShell7Command = Get-Command `
    pwsh.exe `
    -ErrorAction SilentlyContinue |
    Select-Object -First 1

if ($PowerShell7Command) {
    $PowerShellPath = [string] $PowerShell7Command.Source
}

$DefaultPowerShell7Path = Join-Path `
    $env:ProgramFiles `
    "PowerShell\7\pwsh.exe"

if (
    [string]::IsNullOrWhiteSpace($PowerShellPath) -and
    (Test-Path -LiteralPath $DefaultPowerShell7Path)
) {
    $PowerShellPath = $DefaultPowerShell7Path
}

$WindowsPowerShellPath = Join-Path `
    $env:SystemRoot `
    "System32\WindowsPowerShell\v1.0\powershell.exe"

if (
    [string]::IsNullOrWhiteSpace($PowerShellPath) -and
    (Test-Path -LiteralPath $WindowsPowerShellPath)
) {
    $PowerShellPath = $WindowsPowerShellPath
}

if (
    [string]::IsNullOrWhiteSpace($PowerShellPath) -or
    -not (Test-Path -LiteralPath $PowerShellPath)
) {
    throw "Neither PowerShell 7 nor Windows PowerShell 5.1 was found."
}
if (-not (Test-Path -LiteralPath $SourceFolder)) {
    throw "Source folder not found: $SourceFolder"
}

New-Item -ItemType Directory -Path $InstallFolder -Force | Out-Null
New-Item -ItemType Directory -Path $DataFolder -Force | Out-Null

Copy-Item `
    -LiteralPath (Join-Path $SourceFolder "CK3WorkshopAutoUpdater.ps1") `
    -Destination (Join-Path $InstallFolder "CK3WorkshopAutoUpdater.ps1") `
    -Force

$InstalledConfig = Join-Path $InstallFolder "config.json"

if (-not (Test-Path -LiteralPath $InstalledConfig)) {
    Copy-Item `
        -LiteralPath (Join-Path $SourceFolder "config.json") `
        -Destination $InstalledConfig `
        -Force
}

$LegacyFolder = Join-Path $env:USERPROFILE "Documents\CK3WorkshopAutoUpdater"

foreach ($FileName in @("State.json", "History.log", "LastRun.log")) {
    $LegacyFile = Join-Path $LegacyFolder $FileName
    $NewFile = Join-Path $DataFolder $FileName

    if (
        (Test-Path -LiteralPath $LegacyFile) -and
        -not (Test-Path -LiteralPath $NewFile)
    ) {
        Copy-Item -LiteralPath $LegacyFile -Destination $NewFile -Force
    }
}

$RuntimeScript = Join-Path $InstallFolder "CK3WorkshopAutoUpdater.ps1"
$VbsPath = Join-Path $InstallFolder "RunHidden.vbs"

$CommandLine = (
    '"' + $PowerShellPath +
    '" -NoProfile -ExecutionPolicy Bypass -File "' +
    $RuntimeScript +
    '"'
)

$EscapedCommandLine = $CommandLine.Replace('"', '""')

$VbsContent = @(
    'Set shell = CreateObject("WScript.Shell")'
    ('shell.Run "{0}", 0, False' -f $EscapedCommandLine)
    'Set shell = Nothing'
)

Set-Content `
    -LiteralPath $VbsPath `
    -Value $VbsContent `
    -Encoding ASCII

if (Test-Path -LiteralPath $DisabledShortcutPath) {
    Remove-Item -LiteralPath $DisabledShortcutPath -Force
}

$WscriptPath = Join-Path $env:SystemRoot "System32\wscript.exe"
$Shell = New-Object -ComObject WScript.Shell
$Shortcut = $Shell.CreateShortcut($ShortcutPath)
$Shortcut.TargetPath = $WscriptPath
$Shortcut.Arguments = '"' + $VbsPath + '"'
$Shortcut.WorkingDirectory = $InstallFolder
$Shortcut.Description = "Checks CK3 Workshop items and requests missing updates"
$Shortcut.Save()

Write-Host ""
Write-Host "CK3 Workshop Auto Updater was installed successfully." -ForegroundColor Green
Write-Host "Install folder : $InstallFolder"
Write-Host "Startup entry  : $ShortcutPath"
Write-Host "Data folder    : $DataFolder"
Write-Host "PowerShell     : $PowerShellPath"
Write-Host ""
Write-Host "The existing Steam startup setting was not changed."
Write-Host "The updater will run invisibly at Windows sign-in."
