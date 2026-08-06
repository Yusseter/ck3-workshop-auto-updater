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

function Get-WorkshopItemDetails {
    param(
        [Parameter(Mandatory)]
        [string] $ManifestPath
    )

    for ($Attempt = 1; $Attempt -le 10; $Attempt++) {
        try {
            $Lines = Get-Content -LiteralPath $ManifestPath -ErrorAction Stop

            return Get-VdfSectionItems `
                -Lines $Lines `
                -SectionName "WorkshopItemDetails"
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

function Get-WorkshopManifestEncoding {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $Bytes = [System.IO.File]::ReadAllBytes($Path)

    if (
        $Bytes.Length -ge 3 -and
        $Bytes[0] -eq 0xEF -and
        $Bytes[1] -eq 0xBB -and
        $Bytes[2] -eq 0xBF
    ) {
        return [System.Text.UTF8Encoding]::new($true)
    }

    if (
        $Bytes.Length -ge 2 -and
        $Bytes[0] -eq 0xFF -and
        $Bytes[1] -eq 0xFE
    ) {
        return [System.Text.UnicodeEncoding]::new(
            $false,
            $true
        )
    }

    if (
        $Bytes.Length -ge 2 -and
        $Bytes[0] -eq 0xFE -and
        $Bytes[1] -eq 0xFF
    ) {
        return [System.Text.UnicodeEncoding]::new(
            $true,
            $true
        )
    }

    return [System.Text.UTF8Encoding]::new($false)
}

function Find-NamedVdfBlock {
    param(
        [Parameter(Mandatory)]
        [string[]] $Lines,

        [Parameter(Mandatory)]
        [string] $Name,

        [int] $SearchStart = 0,

        [int] $SearchEnd = -1
    )

    if ($SearchEnd -lt 0) {
        $SearchEnd = $Lines.Count - 1
    }

    $NameLine = '"' + $Name + '"'

    for (
        $Index = $SearchStart;
        $Index -le $SearchEnd;
        $Index++
    ) {
        if ($Lines[$Index].Trim() -ne $NameLine) {
            continue
        }

        $OpenIndex = $Index + 1

        while (
            $OpenIndex -le $SearchEnd -and
            [string]::IsNullOrWhiteSpace(
                $Lines[$OpenIndex]
            )
        ) {
            $OpenIndex++
        }

        if (
            $OpenIndex -gt $SearchEnd -or
            $Lines[$OpenIndex].Trim() -ne "{"
        ) {
            continue
        }

        $Depth = 0

        for (
            $BlockIndex = $OpenIndex;
            $BlockIndex -le $SearchEnd;
            $BlockIndex++
        ) {
            $Trimmed = $Lines[$BlockIndex].Trim()

            if ($Trimmed -eq "{") {
                $Depth++
                continue
            }

            if ($Trimmed -eq "}") {
                $Depth--

                if ($Depth -eq 0) {
                    return [PSCustomObject]@{
                        NameIndex  = $Index
                        OpenIndex  = $OpenIndex
                        CloseIndex = $BlockIndex
                    }
                }
            }
        }

        throw "VDF block was opened but not closed: $Name"
    }

    return $null
}

function Get-WorkshopItemManifestStatus {
    param(
        [Parameter(Mandatory)]
        [string] $ManifestPath,

        [Parameter(Mandatory)]
        [string] $AppId,

        [Parameter(Mandatory)]
        [string] $ModId
    )

    $Encoding = Get-WorkshopManifestEncoding `
        -Path $ManifestPath

    $Lines = @(
        [System.IO.File]::ReadAllLines(
            $ManifestPath,
            $Encoding
        )
    )

    $InstalledItems = Get-VdfSectionItems `
        -Lines $Lines `
        -SectionName "WorkshopItemsInstalled"

    $DetailsItems = Get-VdfSectionItems `
        -Lines $Lines `
        -SectionName "WorkshopItemDetails"

    $InstalledManifest = ""
    $SelectedManifest = ""
    $LatestManifest = ""

    if ($InstalledItems.ContainsKey($ModId)) {
        $InstalledManifest = [string] (
            $InstalledItems[$ModId]["manifest"]
        )
    }

    if ($DetailsItems.ContainsKey($ModId)) {
        $SelectedManifest = [string] (
            $DetailsItems[$ModId]["manifest"]
        )

        $LatestManifest = [string] (
            $DetailsItems[$ModId]["latest_manifest"]
        )
    }

    $WorkshopFolder = Split-Path `
        -Path $ManifestPath `
        -Parent

    $ItemFolder = Join-Path `
        $WorkshopFolder `
        "content\$AppId\$ModId"

    return [PSCustomObject]@{
        InstalledManifest = $InstalledManifest
        SelectedManifest  = $SelectedManifest
        LatestManifest    = $LatestManifest
        ItemFolder        = $ItemFolder
        ItemFolderExists  = (
            Test-Path -LiteralPath $ItemFolder
        )
    }
}

function Stop-SteamForWorkshopRepair {
    param(
        [Parameter(Mandatory)]
        [string] $SteamExe
    )

    $SteamProcesses = @(
        Get-Process `
            -Name "steam" `
            -ErrorAction SilentlyContinue
    )

    if ($SteamProcesses.Count -eq 0) {
        return
    }

    Start-Process `
        -FilePath $SteamExe `
        -ArgumentList "-shutdown" `
        -WindowStyle Hidden |
        Out-Null

    $Deadline = (Get-Date).AddSeconds(120)

    while (
        (Get-Process `
            -Name "steam" `
            -ErrorAction SilentlyContinue) -and
        (Get-Date) -lt $Deadline
    ) {
        Start-Sleep -Seconds 2
    }

    if (
        Get-Process `
            -Name "steam" `
            -ErrorAction SilentlyContinue
    ) {
        throw (
            "Steam did not close within 120 seconds. " +
            "No forced termination was attempted."
        )
    }
}

function Start-SteamAfterWorkshopRepair {
    param(
        [Parameter(Mandatory)]
        [string] $SteamExe,

        [Parameter(Mandatory)]
        [int] $InitializationDelaySeconds
    )

    Start-Process `
        -FilePath $SteamExe |
        Out-Null

    $Deadline = (Get-Date).AddSeconds(90)

    while (
        -not (
            Get-Process `
                -Name "steam" `
                -ErrorAction SilentlyContinue
        ) -and
        (Get-Date) -lt $Deadline
    ) {
        Start-Sleep -Seconds 2
    }

    if (
        -not (
            Get-Process `
                -Name "steam" `
                -ErrorAction SilentlyContinue
        )
    ) {
        throw "Steam did not start after the Workshop repair."
    }

    Start-Sleep -Seconds $InitializationDelaySeconds
}

function Invoke-WorkshopRecordRepair {
    param(
        [Parameter(Mandatory)]
        [string] $SteamExe,

        [Parameter(Mandatory)]
        [string] $ManifestPath,

        [Parameter(Mandatory)]
        [string] $AppId,

        [Parameter(Mandatory)]
        [string] $ModId,

        [Parameter(Mandatory)]
        [string] $TargetManifest,

        [Parameter(Mandatory)]
        [string] $GameProcessName,

        [Parameter(Mandatory)]
        [int] $InitializationDelaySeconds,

        [Parameter(Mandatory)]
        [int] $TimeoutMinutes
    )

    if (
        Get-Process `
            -Name $GameProcessName `
            -ErrorAction SilentlyContinue
    ) {
        return [PSCustomObject]@{
            Success    = $false
            Reason     = "$GameProcessName started before the repair."
            BackupPath = ""
        }
    }

    $InitialStatus = Get-WorkshopItemManifestStatus `
        -ManifestPath $ManifestPath `
        -AppId $AppId `
        -ModId $ModId

    if (
        $InitialStatus.InstalledManifest -eq $TargetManifest -and
        $InitialStatus.SelectedManifest -eq $TargetManifest -and
        $InitialStatus.ItemFolderExists
    ) {
        return [PSCustomObject]@{
            Success           = $true
            AlreadyCurrent    = $true
            InstalledManifest = $InitialStatus.InstalledManifest
            SelectedManifest  = $InitialStatus.SelectedManifest
            BackupPath        = ""
        }
    }

    $Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

    $RepairRoot = Join-Path `
        $DataFolder `
        "repair-backups\$ModId-$Timestamp"

    $ManifestBackup = Join-Path `
        $RepairRoot `
        "workshop-manifest.original"

    $ContentBackup = Join-Path `
        $RepairRoot `
        "content-original"

    $FailedContent = Join-Path `
        $RepairRoot `
        "failed-new-content"

    New-Item `
        -ItemType Directory `
        -Path $RepairRoot `
        -Force |
        Out-Null

    $MutationStarted = $false
    $SteamStopped = $false

    try {
        Stop-SteamForWorkshopRepair `
            -SteamExe $SteamExe

        $SteamStopped = $true

        $Encoding = Get-WorkshopManifestEncoding `
            -Path $ManifestPath

        $Lines = @(
            [System.IO.File]::ReadAllLines(
                $ManifestPath,
                $Encoding
            )
        )

        $InstalledSection = Find-NamedVdfBlock `
            -Lines $Lines `
            -Name "WorkshopItemsInstalled"

        $DetailsSection = Find-NamedVdfBlock `
            -Lines $Lines `
            -Name "WorkshopItemDetails"

        if (
            $null -eq $InstalledSection -or
            $null -eq $DetailsSection
        ) {
            throw "Required Workshop manifest sections were not found."
        }

        $InstalledItem = Find-NamedVdfBlock `
            -Lines $Lines `
            -Name $ModId `
            -SearchStart ($InstalledSection.OpenIndex + 1) `
            -SearchEnd ($InstalledSection.CloseIndex - 1)

        $DetailsItem = Find-NamedVdfBlock `
            -Lines $Lines `
            -Name $ModId `
            -SearchStart ($DetailsSection.OpenIndex + 1) `
            -SearchEnd ($DetailsSection.CloseIndex - 1)

        if (
            $null -eq $InstalledItem -or
            $null -eq $DetailsItem
        ) {
            throw (
                "Both Workshop records could not be found " +
                "for item $ModId."
            )
        }

        Copy-Item `
            -LiteralPath $ManifestPath `
            -Destination $ManifestBackup `
            -Force

        $MutationStarted = $true

        if (
            Test-Path `
                -LiteralPath $InitialStatus.ItemFolder
        ) {
            Move-Item `
                -LiteralPath $InitialStatus.ItemFolder `
                -Destination $ContentBackup
        }

        $MutableLines = (
            [System.Collections.Generic.List[string]]::new()
        )

        $MutableLines.AddRange(
            [string[]] $Lines
        )

        $Ranges = @(
            $InstalledItem
            $DetailsItem
        ) |
            Sort-Object NameIndex -Descending

        foreach ($Range in $Ranges) {
            $RemoveCount = (
                $Range.CloseIndex -
                $Range.NameIndex +
                1
            )

            $MutableLines.RemoveRange(
                $Range.NameIndex,
                $RemoveCount
            )
        }

        $RemainingIdCount = @(
            $MutableLines |
                Where-Object {
                    $_.Trim() -eq ('"' + $ModId + '"')
                }
        ).Count

        if ($RemainingIdCount -ne 0) {
            throw (
                "Workshop item records were not removed completely. " +
                "Remaining record count: $RemainingIdCount"
            )
        }

        $BraceDepth = 0

        foreach ($Line in $MutableLines) {
            $Trimmed = $Line.Trim()

            if ($Trimmed -eq "{") {
                $BraceDepth++
                continue
            }

            if ($Trimmed -eq "}") {
                $BraceDepth--

                if ($BraceDepth -lt 0) {
                    throw (
                        "The edited Workshop manifest has " +
                        "an invalid closing brace."
                    )
                }
            }
        }

        if ($BraceDepth -ne 0) {
            throw (
                "The edited Workshop manifest has " +
                "unbalanced braces."
            )
        }

        [System.IO.File]::WriteAllLines(
            $ManifestPath,
            [string[]] $MutableLines,
            $Encoding
        )

        Start-SteamAfterWorkshopRepair `
            -SteamExe $SteamExe `
            -InitializationDelaySeconds `
                $InitializationDelaySeconds

        $SteamStopped = $false

        Start-Process `
            -FilePath $SteamExe `
            -ArgumentList @(
                "-console",
                "+workshop_download_item",
                $AppId,
                $ModId
            ) |
            Out-Null

        $Deadline = (Get-Date).AddMinutes(
            $TimeoutMinutes
        )

        while ((Get-Date) -lt $Deadline) {
            Start-Sleep -Seconds 5

            $CurrentStatus = $null

            try {
                $CurrentStatus = (
                    Get-WorkshopItemManifestStatus `
                        -ManifestPath $ManifestPath `
                        -AppId $AppId `
                        -ModId $ModId
                )
            }
            catch {
                continue
            }

            if (
                $CurrentStatus.InstalledManifest -eq
                    $TargetManifest -and
                $CurrentStatus.SelectedManifest -eq
                    $TargetManifest -and
                $CurrentStatus.ItemFolderExists
            ) {
                return [PSCustomObject]@{
                    Success           = $true
                    AlreadyCurrent    = $false
                    InstalledManifest = (
                        $CurrentStatus.InstalledManifest
                    )
                    SelectedManifest  = (
                        $CurrentStatus.SelectedManifest
                    )
                    BackupPath        = $RepairRoot
                }
            }
        }

        $FinalStatus = Get-WorkshopItemManifestStatus `
            -ManifestPath $ManifestPath `
            -AppId $AppId `
            -ModId $ModId

        throw (
            "Steam did not install the target manifest. " +
            "Installed=$($FinalStatus.InstalledManifest); " +
            "Selected=$($FinalStatus.SelectedManifest); " +
            "Target=$TargetManifest"
        )
    }
    catch {
        $FailureReason = $_.Exception.Message

        try {
            if (
                Get-Process `
                    -Name "steam" `
                    -ErrorAction SilentlyContinue
            ) {
                Stop-SteamForWorkshopRepair `
                    -SteamExe $SteamExe

                $SteamStopped = $true
            }

            if ($MutationStarted) {
                if (
                    Test-Path `
                        -LiteralPath $InitialStatus.ItemFolder
                ) {
                    Move-Item `
                        -LiteralPath $InitialStatus.ItemFolder `
                        -Destination $FailedContent
                }

                Copy-Item `
                    -LiteralPath $ManifestBackup `
                    -Destination $ManifestPath `
                    -Force

                if (
                    Test-Path `
                        -LiteralPath $ContentBackup
                ) {
                    Move-Item `
                        -LiteralPath $ContentBackup `
                        -Destination $InitialStatus.ItemFolder
                }
            }

            if ($SteamStopped) {
                Start-SteamAfterWorkshopRepair `
                    -SteamExe $SteamExe `
                    -InitializationDelaySeconds `
                        $InitializationDelaySeconds

                $SteamStopped = $false
            }
        }
        catch {
            throw (
                "Workshop repair rollback failed. " +
                "Backup directory: $RepairRoot | " +
                "Original failure: $FailureReason | " +
                "Rollback failure: $($_.Exception.Message)"
            )
        }

        return [PSCustomObject]@{
            Success    = $false
            Reason     = $FailureReason
            BackupPath = $RepairRoot
        }
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

    $WorkshopItemDetails = Get-WorkshopItemDetails `
        -ManifestPath $ManifestPath

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
    $StateChanged = $false
    $Candidates = @()
    $UnavailableCount = 0
    $ApiTargetCount = 0
    $CachedLatestTargetCount = 0
    $SelectedFallbackCount = 0
    $SelectionDifferenceCount = 0

    foreach ($ModId in $ModIds) {
        $Local = $InstalledItems[$ModId]
        $Details = $WorkshopItemDetails[$ModId]
        $Remote = $RemoteItems[$ModId]

        $RemoteAvailable = (
            $null -ne $Remote -and
            [int] $Remote.result -eq 1
        )

        if (-not $RemoteAvailable) {
            $UnavailableCount++
        }

        $LocalManifest = [string] $Local.manifest
        $SelectedManifest = ""
        $CachedLatestManifest = ""
        $ApiManifest = ""
        $Name = "Workshop item"

        if ($Details) {
            $SelectedManifest = [string] $Details.manifest
            $CachedLatestManifest = [string] $Details.latest_manifest
        }

        if ($RemoteAvailable) {
            $ApiManifest = [string] $Remote.hcontent_file

            if (
                -not [string]::IsNullOrWhiteSpace(
                    [string] $Remote.title
                )
            ) {
                $Name = [string] $Remote.title
            }
        }

        $HasSelectedManifest = (
            -not [string]::IsNullOrWhiteSpace($SelectedManifest) -and
            $SelectedManifest -ne "0"
        )

        $HasCachedLatestManifest = (
            -not [string]::IsNullOrWhiteSpace($CachedLatestManifest) -and
            $CachedLatestManifest -ne "0"
        )

        $HasApiManifest = (
            -not [string]::IsNullOrWhiteSpace($ApiManifest) -and
            $ApiManifest -ne "0"
        )

        $TargetManifest = ""
        $ManifestSource = ""

        if ($HasApiManifest) {
            $TargetManifest = $ApiManifest
            $ManifestSource = "WebApiLatest"
            $ApiTargetCount++
        }
        elseif ($HasCachedLatestManifest) {
            $TargetManifest = $CachedLatestManifest
            $ManifestSource = "SteamCachedLatest"
            $CachedLatestTargetCount++
        }
        elseif ($HasSelectedManifest) {
            $TargetManifest = $SelectedManifest
            $ManifestSource = "SelectedFallback"
            $SelectedFallbackCount++
        }

        if (
            [string]::IsNullOrWhiteSpace($TargetManifest) -or
            $TargetManifest -eq "0"
        ) {
            continue
        }

        if (
            $HasSelectedManifest -and
            $SelectedManifest -ne $TargetManifest
        ) {
            $SelectionDifferenceCount++
        }

        if ($LocalManifest -eq $TargetManifest) {
            if ($State.ContainsKey($ModId)) {
                [void] $State.Remove($ModId)
                $StateChanged = $true

                Write-Log -Message ((
                    "Resolved state removed: {0} [{1}] — the installed " +
                    "manifest already matches the latest manifest."
                ) -f @(
                    $Name
                    $ModId
                ))
            }

            continue
        }

        $Candidates += [PSCustomObject]@{
            ModId               = $ModId
            Name                = $Name
            LocalManifest       = $LocalManifest
            SelectedManifest    = $SelectedManifest
            CachedLatestManifest = $CachedLatestManifest
            ApiManifest         = $ApiManifest
            TargetManifest      = $TargetManifest
            ManifestSource      = $ManifestSource
        }
    }

    Write-Log "Items with a different latest manifest: $($Candidates.Count)"
    Write-Log "Items unavailable through the public API: $UnavailableCount"
    Write-Log "Items using API latest manifests: $ApiTargetCount"
    Write-Log "Items using cached latest manifests: $CachedLatestTargetCount"
    Write-Log "Items using selected-manifest fallback: $SelectedFallbackCount"
    Write-Log "Items where Steam selection differs from latest: $SelectionDifferenceCount"

    if ($StateChanged) {
        Save-State -State $State
    }

    if ($Candidates.Count -eq 0) {
        Write-Log "No Workshop items require action."
        exit 0
    }

    $RepairCandidates = @()

    foreach ($Candidate in $Candidates) {
        $StateEntry = $State[$Candidate.ModId]
        $StoredTargetManifest = ""
        $StateStatus = ""
        $StateMatchesTarget = $false
        $RetryAfter = $null

        if ($StateEntry) {
            $StateStatus = [string] $StateEntry.Status
            $StoredTargetManifest = [string] (
                $StateEntry.TargetManifest
            )

            if (
                [string]::IsNullOrWhiteSpace(
                    $StoredTargetManifest
                )
            ) {
                $StoredTargetManifest = [string] (
                    $StateEntry.RemoteManifest
                )
            }

            $StateMatchesTarget = (
                $StoredTargetManifest -eq
                    $Candidate.TargetManifest -and
                [string] $StateEntry.GameBuildId -eq
                    $GameBuildId
            )
        }

        if (
            $StateMatchesTarget -and
            $StateStatus -in @(
                "RepairPending",
                "NoChange"
            )
        ) {
            $RepairCandidates += $Candidate

            Write-Log -Message ((
                "Repair pending: {0} [{1}] — a clean Workshop " +
                "re-registration will be attempted."
            ) -f @(
                $Candidate.Name
                $Candidate.ModId
            ))

            continue
        }

        if (
            $StateMatchesTarget -and
            $StateStatus -eq "RepairFailed"
        ) {
            $Suppressed = $false

            try {
                $RetryAfter = [DateTimeOffset]::Parse(
                    [string] $StateEntry.RetryAfter
                )

                if (
                    [DateTimeOffset]::UtcNow -lt
                    $RetryAfter
                ) {
                    $Suppressed = $true
                }
            }
            catch {
                $Suppressed = $false
            }

            if ($Suppressed) {
                Write-Log -Message ((
                    "Repair skipped: {0} [{1}] — retry after {2}."
                ) -f @(
                    $Candidate.Name
                    $Candidate.ModId
                    $RetryAfter.ToLocalTime().ToString(
                        "yyyy-MM-dd HH:mm:ss"
                    )
                ))

                continue
            }

            $RepairCandidates += $Candidate
            continue
        }

        $BeforeManifest = $Candidate.LocalManifest

        $InitialLineCount = @(
            Get-Content -LiteralPath $WorkshopLog
        ).Count

        Write-Log (
            "Update requested: " +
            "$($Candidate.Name) [$($Candidate.ModId)]"
        )

        Start-Process `
            -FilePath $SteamInfo.Exe `
            -ArgumentList @(
                "-console",
                "+workshop_download_item",
                $AppId,
                $Candidate.ModId
            ) |
            Out-Null

        $Result = Wait-WorkshopResult `
            -WorkshopLog $WorkshopLog `
            -ModId $Candidate.ModId `
            -InitialLineCount $InitialLineCount `
            -TimeoutMinutes $WorkshopResultTimeoutMinutes

        Start-Sleep -Seconds 2

        $AfterItems = Get-InstalledItems `
            -ManifestPath $ManifestPath

        $AfterManifest = ""

        if (
            $AfterItems.ContainsKey(
                $Candidate.ModId
            )
        ) {
            $AfterManifest = [string] (
                $AfterItems[$Candidate.ModId].manifest
            )
        }

        if (
            $AfterManifest -eq
            $Candidate.TargetManifest
        ) {
            Write-Log -Message ((
                "Updated: {0} [{1}] — installed manifest " +
                "changed from {2} to {3}."
            ) -f @(
                $Candidate.Name
                $Candidate.ModId
                $BeforeManifest
                $AfterManifest
            ))

            [void] $State.Remove(
                $Candidate.ModId
            )

            Save-State -State $State
            continue
        }

        if (
            $Result.Completed -and
            $Result.Result -eq "OK"
        ) {
            $State[$Candidate.ModId] = @{
                Status           = "RepairPending"
                TargetManifest   = $Candidate.TargetManifest
                LocalManifest    = $AfterManifest
                SelectedManifest = (
                    $Candidate.SelectedManifest
                )
                GameBuildId      = $GameBuildId
                LastAttempt      = (
                    [DateTimeOffset]::UtcNow.ToString("o")
                )
            }

            $RepairCandidates += $Candidate

            Write-Log -Message ((
                "Repair queued: {0} [{1}] — Steam returned OK, " +
                "but the latest manifest was not installed."
            ) -f @(
                $Candidate.Name
                $Candidate.ModId
            ))

            Save-State -State $State
            continue
        }

        Write-Log -Message ((
            "Incomplete: {0} [{1}] — Steam result: {2}; " +
            "installed manifest: {3}; target manifest: {4}."
        ) -f @(
            $Candidate.Name
            $Candidate.ModId
            $Result.Result
            $AfterManifest
            $Candidate.TargetManifest
        ))

        Save-State -State $State
    }

    if ($RepairCandidates.Count -gt 0) {
        $RepairCandidate = $RepairCandidates[0]

        Write-Log -Message ((
            "Starting clean Workshop repair: {0} [{1}]"
        ) -f @(
            $RepairCandidate.Name
            $RepairCandidate.ModId
        ))

        $RepairResult = Invoke-WorkshopRecordRepair `
            -SteamExe $SteamInfo.Exe `
            -ManifestPath $ManifestPath `
            -AppId $AppId `
            -ModId $RepairCandidate.ModId `
            -TargetManifest $RepairCandidate.TargetManifest `
            -GameProcessName $GameProcessName `
            -InitializationDelaySeconds `
                $SteamInitializationDelaySeconds `
            -TimeoutMinutes $WorkshopResultTimeoutMinutes

        if ($RepairResult.Success) {
            [void] $State.Remove(
                $RepairCandidate.ModId
            )

            Write-Log -Message ((
                "Repair succeeded: {0} [{1}] — installed " +
                "manifest is now {2}. Backup: {3}"
            ) -f @(
                $RepairCandidate.Name
                $RepairCandidate.ModId
                $RepairResult.InstalledManifest
                $RepairResult.BackupPath
            ))
        }

        if (-not $RepairResult.Success) {
            $RetryAfter = (
                [DateTimeOffset]::UtcNow.AddHours(
                    $NoChangeRetryHours
                )
            )

            $State[$RepairCandidate.ModId] = @{
                Status         = "RepairFailed"
                TargetManifest = (
                    $RepairCandidate.TargetManifest
                )
                LocalManifest  = (
                    $RepairCandidate.LocalManifest
                )
                GameBuildId    = $GameBuildId
                LastAttempt    = (
                    [DateTimeOffset]::UtcNow.ToString("o")
                )
                RetryAfter     = $RetryAfter.ToString("o")
                FailureReason  = $RepairResult.Reason
                BackupPath     = $RepairResult.BackupPath
            }

            Write-Log -Message ((
                "Repair failed: {0} [{1}] — {2}. " +
                "Retry after: {3}. Backup: {4}"
            ) -f @(
                $RepairCandidate.Name
                $RepairCandidate.ModId
                $RepairResult.Reason
                $RetryAfter.ToLocalTime().ToString(
                    "yyyy-MM-dd HH:mm:ss"
                )
                $RepairResult.BackupPath
            ))
        }

        Save-State -State $State

        if ($RepairCandidates.Count -gt 1) {
            Write-Log (
                "$($RepairCandidates.Count - 1) additional " +
                "repair candidate(s) remain pending."
            )
        }
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
