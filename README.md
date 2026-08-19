# CK3 Workshop Auto Updater

An experimental Windows utility that checks installed **Crusader Kings III** Steam Workshop items and asks Steam to download mods that are using outdated Workshop manifests.

When Steam reports a successful download but leaves a mod on an outdated manifest, the updater can perform a controlled repair for that specific Workshop item. It creates backups before changing local Steam records and restores them automatically if the repair fails.

It does **not** unsubscribe from mods, collect Steam credentials, or replace Steam's normal startup behavior.

## Status

Version: **0.3.1**

Tested on one Windows 11 system with:

- Steam
- Crusader Kings III (AppID `1158310`)
- PowerShell 7 when available
- Windows PowerShell 5.1 as a fallback

PowerShell 7 is preferred automatically when installed. Windows PowerShell 5.1 is included with Windows and is used as a fallback, so PowerShell 7 is not required.

Steam Client Beta was used during development, but it has not been proven to be required.

## Installation

### Windows Setup executable — recommended

1. Open the latest release.
2. Download `CK3WorkshopAutoUpdater-Setup-vX.Y.Z.exe`.
3. Run the setup file.

The installer places the utility under:

```text
%LOCALAPPDATA%\CK3WorkshopAutoUpdater
```

It also:

- Creates the hidden Windows startup entry.
- Adds **Run Now**, **Open Logs**, and **Uninstall** shortcuts to the Start menu.
- Adds the utility to Windows **Installed apps**.
- Preserves existing configuration, state, and log files during upgrades.

PowerShell 7 is preferred when available. Windows PowerShell 5.1 is used as a fallback.

### Portable ZIP

1. Download and extract the portable ZIP archive.
2. Double-click `Install.cmd`.
3. Keep Steam's own **Run Steam when my computer starts** setting enabled.

The extracted source folder can be moved, renamed, used as a Git repository, or deleted after installation.

You do not need to open or manually run any `.ps1` file.

## Included portable commands

- `Install.cmd` — installs or updates the utility.
- `Run Now.cmd` — starts a check immediately and invisibly.
- `Open Logs.cmd` — opens the runtime data and log folder.
- `Uninstall.cmd` — removes the utility and its startup entry.

## How it works

1. Starts invisibly when the user signs in to Windows.
2. Waits for Steam to start and initialize.
3. Skips the run if Crusader Kings III is currently open.
4. Finds CK3's `appworkshop_1158310.acf`.
5. Reads the installed and Steam-selected Workshop manifest IDs.
6. Queries Steam's public Workshop details API in batches.
7. Chooses the newest available target manifest in this order:
   - Steam's public Workshop API
   - Steam's cached latest manifest
   - Steam's selected manifest as a fallback
8. Requests a normal Steam Workshop download for outdated items:

   ```text
   workshop_download_item 1158310 <WorkshopItemId>
   ```

9. Watches Steam's `workshop_log.txt` and verifies the actual installed manifest.
10. If Steam reports success but the newest manifest is still not installed, queues the item for controlled repair.

## Controlled repair

A clean repair is used only when the normal Steam download does not replace an outdated manifest.

Before repair, the updater:

- Stops Steam safely.
- Backs up the Workshop manifest file.
- Backs up the affected mod's local content.
- Removes only the affected item's local records from:
  - `WorkshopItemsInstalled`
  - `WorkshopItemDetails`

It then restarts Steam and requests the mod again.

The repair is considered successful only when:

- The installed manifest matches the target manifest.
- Steam's selected manifest matches the target manifest.
- The mod content folder exists.

If any part of the repair fails, the original Workshop manifest and mod content are restored automatically.

To reduce risk, the updater performs at most one clean repair per run.

## Retry behavior

Failed or incomplete updates are recorded in `State.json`.

The updater temporarily suppresses repeated attempts for the same unresolved manifest. A new remote manifest, a new CK3 build, or the configured retry time can allow another attempt.

The default retry period is 24 hours.

## Data and logs

Runtime data is stored under:

```text
%LOCALAPPDATA%\CK3WorkshopAutoUpdater\data
```

Files include:

- `LastRun.log` — the most recent run
- `History.log` — accumulated run history
- `State.json` — retry and repair state
- `repair-backups` — temporary recovery data created during controlled repairs

No Steam credentials are collected or stored.

## Configuration

Edit the installed `config.json` to change timing and retry behavior.

Installing a newer version updates the application files while preserving the existing configuration and runtime data.

Default settings include:

- Steam startup wait time
- Steam initialization delay
- Workshop result timeout
- No-change retry period
- Public API request retries
- Delay between failed API requests

## Uninstallation

For the Setup executable installation:

1. Open Windows **Installed apps**.
2. Find **CK3 Workshop Auto Updater**.
3. Select **Uninstall**.

For the portable ZIP installation, double-click:

```text
Uninstall.cmd
```

Steam, Crusader Kings III, Workshop subscriptions, and installed Workshop content are left unchanged.

## Building a portable release archive

Portable release archives can be created by double-clicking:

```text
Build Release.cmd
```

The builder reads the version from `VERSION`, verifies that the current branch is `main` and the Git working tree is clean, and creates:

```text
dist/ck3-workshop-auto-updater-v<VERSION>.zip
dist/ck3-workshop-auto-updater-v<VERSION>.sha256
```

Only files committed to Git are included.

## Building the Windows installer

The Windows installer is built automatically through GitHub Actions.

The workflow:

- Reads the version from `VERSION`.
- Compiles the Inno Setup installer.
- Creates a SHA-256 checksum file.
- Uploads both files as a workflow artifact.

The installer is intentionally **not rebuilt when a GitHub release is published**.

Release assets should be taken from the exact GitHub Actions artifact that was tested and validated. This ensures that the published installer has the same SHA-256 hash as the binary that was tested before release.

## Safety notes

The updater changes Steam Workshop data only when a mod remains stuck after a normal Steam download attempt.

Repair operations are limited to the affected Workshop item and use backups with automatic rollback.

Despite these safeguards, this project is experimental. Keep important game saves backed up and review logs after unexpected Steam or Workshop behavior.

## Disclaimer

This project is not affiliated with Valve, Steam, or Paradox Interactive.
