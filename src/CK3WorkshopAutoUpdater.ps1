$ErrorActionPreference = "Stop"

$ConfigPath = Join-Path $PSScriptRoot "config.json"
$DataFolder = Join-Path $PSScriptRoot "data"
$LastRunLog = Join-Path $DataFolder "LastRun.log"
$HistoryLog = Join-Path $DataFolder "History.log"
$StatePath = Join-Path $DataFolder "State.json"

New-Item -ItemType Directory -Path $DataFolder -Force | Out-Null

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string] $Message
    )

    $Line = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message

    Add-Content -LiteralPath $LastRunLog -Value $Line -Encoding UTF8
    Add-Content -LiteralPath $HistoryLog -Value $Line -Encoding UTF8
}

function Get-Configuration {
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "Configuration file not found: $ConfigPath"
    }

    $Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

    if ([string]::IsNullOrWhiteSpace([string] $Config.AppId)) {
        throw "AppId is missing from config.json."
    }

    return $Config
}

function Get-VdfSectionItems {
    param(
        [Parameter(Mandatory)]
        [string[]] $Lines,

        [Parameter(Mandatory)]
        [string] $SectionName
    )

    $Items = @{}
    $Depth = 0
    $PendingSection = $false
    $InSection = $false
    $SectionDepth = -1
    $PendingItem = $null
    $CurrentItem = $null
    $ItemDepth = -1

    foreach ($RawLine in $Lines) {
        $Line = $RawLine.Trim()

        if ($Line -match '^"(?<name>[^"]+)"$') {
            $Name = $Matches.name

            if (-not $InSection -and $Name -eq $SectionName) {
                $PendingSection = $true
                continue
            }

            if (
                $InSection -and
                $null -eq $CurrentItem -and
                $Depth -eq $SectionDepth -and
                $Name -match '^\d+$'
            ) {
                $PendingItem = $Name
                continue
            }
        }

        if ($Line -eq "{") {
            $Depth++

            if ($PendingSection) {
                $InSection = $true
                $SectionDepth = $Depth
                $PendingSection = $false
                continue
            }

            if ($InSection -and $null -ne $PendingItem) {
                $CurrentItem = $PendingItem
                $PendingItem = $null
                $ItemDepth = $Depth
                $Items[$CurrentItem] = @{}
                continue
            }

            continue
        }

        if ($Line -eq "}") {
            if (
                $InSection -and
                $null -ne $CurrentItem -and
                $Depth -eq $ItemDepth
            ) {
                $CurrentItem = $null
                $ItemDepth = -1
                $Depth--
                continue
            }

            if ($InSection -and $Depth -eq $SectionDepth) {
                $Depth--
                break
            }

            $Depth--
            continue
        }

        if (
            $InSection -and
            $null -ne $CurrentItem -and
            $Depth -eq $ItemDepth -and
            $Line -match '^"(?<key>[^"]+)"\s+"(?<value>[^"]*)"$'
        ) {
            $Items[$CurrentItem][$Matches.key] = $Matches.value
        }
    }

    return $Items
}

function Get-InstalledItems {
    param(
        [Parameter(Mandatory)]
        [string] $ManifestPath
    )

    for ($Attempt = 1; $Attempt -le 10; $Attempt++) {
        try {
            $Lines = Get-Content -LiteralPath $ManifestPath -ErrorAction Stop

            return Get-VdfSectionItems `
                -Lines $Lines `
                -SectionName "WorkshopItemsInstalled"
        }
        catch {
            if ($Attempt -eq 10) {
                throw
            }

            Start-Sleep -Seconds 1
        }
    }
}

function Get-SteamInformation {
    $Registry = Get-ItemProperty -Path "HKCU:\Software\Valve\Steam"

    if (-not (Test-Path -LiteralPath $Registry.SteamExe)) {
        throw "steam.exe was not found: $($Registry.SteamExe)"
    }

    return [PSCustomObject]@{
        Exe  = [string] $Registry.SteamExe
        Root = [string] $Registry.SteamPath
    }
}

function Find-WorkshopManifest {
    param(
        [Parameter(Mandatory)]
        [string] $SteamRoot,

        [Parameter(Mandatory)]
        [string] $AppId
    )

    $LibraryRoots = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )

    [void] $LibraryRoots.Add($SteamRoot)

    $LibraryFile = Join-Path $SteamRoot "steamapps\libraryfolders.vdf"

    if (Test-Path -LiteralPath $LibraryFile) {
        foreach ($Line in Get-Content -LiteralPath $LibraryFile) {
            if ($Line -match '"path"\s+"(?<path>[^"]+)"') {
                $LibraryPath = $Matches.path.Replace("\\", "\")

                if (Test-Path -LiteralPath $LibraryPath) {
                    [void] $LibraryRoots.Add($LibraryPath)
                }
            }
        }
    }

    foreach ($LibraryRoot in $LibraryRoots) {
        $Candidate = Join-Path `
            $LibraryRoot `
            "steamapps\workshop\appworkshop_$AppId.acf"

        if (Test-Path -LiteralPath $Candidate) {
            return $Candidate
        }
    }

    throw "The Workshop manifest for AppID $AppId was not found."
}

function Get-GameBuildId {
    param(
        [Parameter(Mandatory)]
        [string] $WorkshopManifest,

        [Parameter(Mandatory)]
        [string] $AppId
    )

    $WorkshopFolder = Split-Path $WorkshopManifest -Parent
    $SteamAppsFolder = Split-Path $WorkshopFolder -Parent
    $AppManifest = Join-Path $SteamAppsFolder "appmanifest_$AppId.acf"

    if (-not (Test-Path -LiteralPath $AppManifest)) {
        return ""
    }

    $Match = Select-String `
        -LiteralPath $AppManifest `
        -Pattern '"buildid"\s+"(?<id>\d+)"' |
        Select-Object -First 1

    if ($Match) {
        return [string] $Match.Matches[0].Groups["id"].Value
    }

    return ""
}

function Get-RemoteWorkshopItems {
    param(
        [Parameter(Mandatory)]
        [string[]] $ModIds,

        [Parameter(Mandatory)]
        [int] $RequestRetries,

        [Parameter(Mandatory)]
        [int] $RetryDelaySeconds
    )

    $RemoteItems = @{}
    $BatchSize = 50

    for ($Start = 0; $Start -lt $ModIds.Count; $Start += $BatchSize) {
        $Last = [Math]::Min($Start + $BatchSize - 1, $ModIds.Count - 1)
        $Batch = @($ModIds[$Start..$Last])

        $Body = @{
            itemcount = $Batch.Count
        }

        for ($Index = 0; $Index -lt $Batch.Count; $Index++) {
            $Body["publishedfileids[$Index]"] = $Batch[$Index]
        }

        $Response = $null

        for ($Attempt = 1; $Attempt -le $RequestRetries; $Attempt++) {
            try {
                $Response = Invoke-RestMethod `
                    -Method Post `
                    -Uri "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/" `
                    -Body $Body `
                    -TimeoutSec 30

                break
            }
            catch {
                if ($Attempt -eq $RequestRetries) {
                    throw
                }

                Start-Sleep -Seconds $RetryDelaySeconds
            }
        }

        foreach ($Item in @($Response.response.publishedfiledetails)) {
            $RemoteItems[[string] $Item.publishedfileid] = $Item
        }
    }

    return $RemoteItems
}

function ConvertTo-Hashtable {
    param(
        [Parameter(Mandatory = $false)]
        $InputObject
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $Result = @{}

        foreach ($Key in $InputObject.Keys) {
            $Result[[string] $Key] = ConvertTo-Hashtable `
                -InputObject $InputObject[$Key]
        }

        return $Result
    }

    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $Result = @{}

        foreach ($Property in $InputObject.PSObject.Properties) {
            $Result[$Property.Name] = ConvertTo-Hashtable `
                -InputObject $Property.Value
        }

        return $Result
    }

    return $InputObject
}
function Get-State {
    if (-not (Test-Path -LiteralPath $StatePath)) {
        return @{}
    }

    try {
        $Raw = Get-Content -LiteralPath $StatePath -Raw

        if ([string]::IsNullOrWhiteSpace($Raw)) {
            return @{}
        }

        $ParsedState = $Raw | ConvertFrom-Json

        return ConvertTo-Hashtable -InputObject $ParsedState
    }
    catch {
        Write-Log "State.json could not be read. Continuing with an empty state."
        return @{}
    }
}

function Save-State {
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $State
    )

    $TemporaryPath = "$StatePath.tmp"

    $State |
        ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $TemporaryPath -Encoding UTF8

    Move-Item `
        -LiteralPath $TemporaryPath `
        -Destination $StatePath `
        -Force
}

function Wait-WorkshopResult {
    param(
        [Parameter(Mandatory)]
        [string] $WorkshopLog,

        [Parameter(Mandatory)]
        [string] $ModId,

        [Parameter(Mandatory)]
        [int] $InitialLineCount,

        [Parameter(Mandatory)]
        [int] $TimeoutMinutes
    )

    $Deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $Pattern = "Download item $ModId result : (?<result>.+)$"

    do {
        Start-Sleep -Seconds 2

        $Lines = @(Get-Content -LiteralPath $WorkshopLog)

        if ($Lines.Count -lt $InitialLineCount) {
            $InitialLineCount = 0
        }

        $NewLines = @($Lines | Select-Object -Skip $InitialLineCount)

        $ResultLine = $NewLines |
            Select-String -Pattern $Pattern |
            Select-Object -Last 1

        if ($ResultLine) {
            return [PSCustomObject]@{
                Completed = $true
                Result = $ResultLine.Matches[0].Groups["result"].Value.Trim()
            }
        }
    }
    while ((Get-Date) -lt $Deadline)

    return [PSCustomObject]@{
        Completed = $false
        Result = "Timeout"
    }
}

$Mutex = [System.Threading.Mutex]::new(
    $false,
    "Local\CK3WorkshopAutoUpdater"
)

$HasMutex = $false

try {
    $HasMutex = $Mutex.WaitOne(0)

    if (-not $HasMutex) {
        exit 0
    }

    Set-Content -LiteralPath $LastRunLog -Value "" -Encoding UTF8
    Write-Log "CK3 Workshop check started."

    $Config = Get-Configuration
    $AppId = [string] $Config.AppId
    $GameProcessName = [string] $Config.GameProcessName
    $SteamWaitMinutes = [int] $Config.SteamWaitMinutes
    $SteamInitializationDelaySeconds = [int] $Config.SteamInitializationDelaySeconds
    $WorkshopResultTimeoutMinutes = [int] $Config.WorkshopResultTimeoutMinutes
    $NoChangeRetryHours = [int] $Config.NoChangeRetryHours
    $RequestRetries = [int] $Config.RequestRetries
    $RequestRetryDelaySeconds = [int] $Config.RequestRetryDelaySeconds

    if (Get-Process -Name $GameProcessName -ErrorAction SilentlyContinue) {
        Write-Log "$GameProcessName is running. No changes were made."
        exit 0
    }

    $SteamInfo = Get-SteamInformation
    Write-Log "Waiting for Steam to start."

    $SteamDeadline = (Get-Date).AddMinutes($SteamWaitMinutes)

    while (-not (Get-Process -Name "steam" -ErrorAction SilentlyContinue)) {
        if ((Get-Date) -ge $SteamDeadline) {
            throw "Steam did not start within $SteamWaitMinutes minute(s)."
        }

        Start-Sleep -Seconds 3
    }

    Write-Log "Steam found. Waiting for the client to initialize."
    Start-Sleep -Seconds $SteamInitializationDelaySeconds

    $ManifestPath = Find-WorkshopManifest `
        -SteamRoot $SteamInfo.Root `
        -AppId $AppId

    $WorkshopLog = Join-Path $SteamInfo.Root "logs\workshop_log.txt"

    if (-not (Test-Path -LiteralPath $WorkshopLog)) {
        throw "Steam Workshop log was not found: $WorkshopLog"
    }

    $GameBuildId = Get-GameBuildId `
        -WorkshopManifest $ManifestPath `
        -AppId $AppId

    $InstalledItems = Get-InstalledItems -ManifestPath $ManifestPath

    $ModIds = @(
        $InstalledItems.Keys |
            Where-Object { $_ -match '^\d+$' } |
            Sort-Object { [uint64] $_ }
    )

    Write-Log "Installed Workshop item count: $($ModIds.Count)"
    Write-Log "Game build ID: $GameBuildId"

    $RemoteItems = Get-RemoteWorkshopItems `
        -ModIds $ModIds `
        -RequestRetries $RequestRetries `
        -RetryDelaySeconds $RequestRetryDelaySeconds

    $State = Get-State
    $Candidates = @()
    $UnavailableCount = 0

    foreach ($ModId in $ModIds) {
        $Local = $InstalledItems[$ModId]
        $Remote = $RemoteItems[$ModId]

        if ($null -eq $Remote -or [int] $Remote.result -ne 1) {
            $UnavailableCount++
            continue
        }

        $LocalManifest = [string] $Local.manifest
        $RemoteManifest = [string] $Remote.hcontent_file

        if (
            -not [string]::IsNullOrWhiteSpace($RemoteManifest) -and
            $RemoteManifest -ne "0" -and
            $RemoteManifest -ne $LocalManifest
        ) {
            $Candidates += [PSCustomObject]@{
                ModId          = $ModId
                Name           = [string] $Remote.title
                LocalManifest  = $LocalManifest
                RemoteManifest = $RemoteManifest
            }
        }
    }

    Write-Log "Items with a different remote manifest: $($Candidates.Count)"
    Write-Log "Items unavailable through the public API: $UnavailableCount"

    if ($Candidates.Count -eq 0) {
        Write-Log "No Workshop items require action."
        exit 0
    }

    foreach ($Candidate in $Candidates) {
        $StateEntry = $State[$Candidate.ModId]
        $Suppressed = $false
        $RetryAfter = $null

        if (
            $StateEntry -and
            [string] $StateEntry.Status -eq "NoChange" -and
            [string] $StateEntry.RemoteManifest -eq $Candidate.RemoteManifest -and
            [string] $StateEntry.GameBuildId -eq $GameBuildId
        ) {
            try {
                $RetryAfter = [DateTimeOffset]::Parse(
                    [string] $StateEntry.RetryAfter
                )

                if ([DateTimeOffset]::UtcNow -lt $RetryAfter) {
                    $Suppressed = $true
                }
            }
            catch {
                $Suppressed = $false
            }
        }

        if ($Suppressed) {
            Write-Log -Message ((
                "Skipped: {0} [{1}] — Steam previously returned OK without changing " +
                "the installed manifest. Retry after: {2}"
            ) -f @(
                $Candidate.Name
                $Candidate.ModId
                $RetryAfter.ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss")
            ))

            continue
        }

        $BeforeManifest = $Candidate.LocalManifest
        $InitialLineCount = @(Get-Content -LiteralPath $WorkshopLog).Count

        Write-Log "Update requested: $($Candidate.Name) [$($Candidate.ModId)]"

        Start-Process `
            -FilePath $SteamInfo.Exe `
            -ArgumentList @(
                "-console",
                "+workshop_download_item",
                $AppId,
                $Candidate.ModId
            )

        $Result = Wait-WorkshopResult `
            -WorkshopLog $WorkshopLog `
            -ModId $Candidate.ModId `
            -InitialLineCount $InitialLineCount `
            -TimeoutMinutes $WorkshopResultTimeoutMinutes

        Start-Sleep -Seconds 2

        $AfterItems = Get-InstalledItems -ManifestPath $ManifestPath
        $AfterManifest = [string] $AfterItems[$Candidate.ModId].manifest

        if ($AfterManifest -ne $BeforeManifest) {
            Write-Log -Message ((
                "Updated: {0} [{1}] — installed manifest changed from {2} to {3}."
            ) -f @(
                $Candidate.Name
                $Candidate.ModId
                $BeforeManifest
                $AfterManifest
            ))

            [void] $State.Remove($Candidate.ModId)
        }
        elseif ($Result.Completed -and $Result.Result -eq "OK") {
            $RetryAfter = [DateTimeOffset]::UtcNow.AddHours(
                $NoChangeRetryHours
            )

            $State[$Candidate.ModId] = @{
                Status         = "NoChange"
                RemoteManifest = $Candidate.RemoteManifest
                LocalManifest  = $BeforeManifest
                GameBuildId    = $GameBuildId
                LastAttempt    = [DateTimeOffset]::UtcNow.ToString("o")
                RetryAfter     = $RetryAfter.ToString("o")
            }

            Write-Log -Message ((
                "No change: {0} [{1}] — Steam returned OK, but the installed " +
                "manifest did not change. The same remote manifest will not be " +
                "forced again until {2}."
            ) -f @(
                $Candidate.Name
                $Candidate.ModId
                $RetryAfter.ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss")
            ))
        }
        else {
            Write-Log -Message ((
                "Incomplete: {0} [{1}] — Steam result: {2}"
            ) -f @(
                $Candidate.Name
                $Candidate.ModId
                $Result.Result
            ))
        }

        Save-State -State $State
    }

    Write-Log "Workshop check completed."
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
}
finally {
    if ($HasMutex) {
        [void] $Mutex.ReleaseMutex()
    }

    $Mutex.Dispose()
}
