$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$VersionPath = Join-Path $RepoRoot "VERSION"
$OutputFolder = Join-Path $RepoRoot "dist"

$GitCommand = Get-Command git.exe -ErrorAction SilentlyContinue

if (-not $GitCommand) {
    throw "Git was not found."
}

$GitPath = $GitCommand.Source

$IsRepository = (
    & $GitPath `
        -C $RepoRoot `
        rev-parse `
        --is-inside-work-tree `
        2>$null
).Trim()

if (
    $LASTEXITCODE -ne 0 -or
    $IsRepository -ne "true"
) {
    throw "The project folder is not a Git repository."
}

$CurrentBranch = (
    & $GitPath `
        -C $RepoRoot `
        branch `
        --show-current
).Trim()

if ($LASTEXITCODE -ne 0) {
    throw "The current Git branch could not be determined."
}

if ($CurrentBranch -ne "main") {
    throw "Release archives must be built from main. Current branch: $CurrentBranch"
}

$WorkingTreeStatus = @(
    & $GitPath `
        -C $RepoRoot `
        status `
        --porcelain
)

if ($LASTEXITCODE -ne 0) {
    throw "The Git working tree status could not be read."
}

if ($WorkingTreeStatus.Count -gt 0) {
    throw "The Git working tree is not clean. Commit, discard, or stash the changes before building a release."
}

if (-not (Test-Path -LiteralPath $VersionPath)) {
    throw "VERSION file not found: $VersionPath"
}

$Version = (
    Get-Content `
        -LiteralPath $VersionPath `
        -Raw
).Trim()

if ($Version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') {
    throw "Invalid version in VERSION: $Version"
}

$ArchiveBaseName = "ck3-workshop-auto-updater-v$Version"
$ZipPath = Join-Path $OutputFolder "$ArchiveBaseName.zip"
$HashPath = Join-Path $OutputFolder "$ArchiveBaseName.sha256"

New-Item `
    -ItemType Directory `
    -Path $OutputFolder `
    -Force |
    Out-Null

foreach ($Path in @(
    $ZipPath
    $HashPath
)) {
    if (Test-Path -LiteralPath $Path) {
        Remove-Item `
            -LiteralPath $Path `
            -Force
    }
}

& $GitPath `
    -C $RepoRoot `
    archive `
    --format=zip `
    "--prefix=$ArchiveBaseName/" `
    "--output=$ZipPath" `
    HEAD

if ($LASTEXITCODE -ne 0) {
    throw "Git could not create the release archive."
}

if (-not (Test-Path -LiteralPath $ZipPath)) {
    throw "The release archive was not created."
}

$ArchiveFile = Get-Item -LiteralPath $ZipPath

if ($ArchiveFile.Length -le 0) {
    throw "The release archive is empty."
}

$Hash = (
    Get-FileHash `
        -LiteralPath $ZipPath `
        -Algorithm SHA256
).Hash.ToLowerInvariant()

$HashLine = "$Hash  $($ArchiveFile.Name)"
$Utf8WithoutBom = New-Object `
    System.Text.UTF8Encoding `
    -ArgumentList $false

[System.IO.File]::WriteAllText(
    $HashPath,
    $HashLine + [Environment]::NewLine,
    $Utf8WithoutBom
)

Write-Host ""
Write-Host "Release archive created successfully." -ForegroundColor Green
Write-Host "Version    : $Version"
Write-Host "Branch     : $CurrentBranch"
Write-Host "Archive    : $ZipPath"
Write-Host "Size       : $($ArchiveFile.Length) bytes"
Write-Host "SHA-256    : $Hash"
Write-Host "Hash file  : $HashPath"
Write-Host ""

Start-Process `
    -FilePath "explorer.exe" `
    -ArgumentList "/select,`"$ZipPath`""
