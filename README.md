# CK3 Workshop Auto Updater

An experimental Windows utility that checks installed **Crusader Kings III** Steam Workshop items and asks Steam to download items whose remote content manifest differs from the installed manifest.

It does **not** delete Workshop manifests, unsubscribe from mods, or replace Steam's normal startup behavior.

## Status

Version: **0.1.1 (experimental)**

Tested on one Windows 11 system with:

- Steam
- Crusader Kings III (AppID `1158310`)
- PowerShell 7

Steam Client Beta was used during development, but it has not been proven to be required.

## Installation

1. Extract the downloaded ZIP anywhere.
2. Double-click `Install.cmd`.
3. Keep Steam's own **Run Steam when my computer starts** setting enabled.

The installer copies the working files to:

```text
%LOCALAPPDATA%\CK3WorkshopAutoUpdater
```

It also creates a hidden startup entry. The extracted source folder can then be moved, renamed, used as a Git repository, or deleted.

You do not need to open or manually run any `.ps1` file.

## Included commands

- `Install.cmd` — installs or updates the utility.
- `Run Now.cmd` — starts a check immediately and invisibly.
- `Open Logs.cmd` — opens the runtime data and log folder.
- `Uninstall.cmd` — removes the utility and its startup entry.

## How it works

1. Waits for Steam after Windows sign-in.
2. Finds CK3's `appworkshop_1158310.acf`.
3. Reads installed Workshop manifest IDs.
4. Queries Steam's public Workshop details API in batches.
5. For differing content manifests, sends:

   ```text
   workshop_download_item 1158310 <WorkshopItemId>
   ```

6. Watches Steam's `workshop_log.txt`.
7. Verifies whether the installed manifest actually changed.

When Steam returns `OK` but keeps the same installed manifest, the item is recorded in `State.json` and is not forced again for 24 hours. A new remote manifest or a new CK3 build invalidates that suppression.

## Important limitation

Steam may expose a general latest content manifest through the public API while selecting a different branch-specific or author snapshot manifest for the current client. The updater therefore treats a changed installed manifest as success; `OK` alone is not considered proof of an update.

This project works around delayed or missed Workshop updates, but it cannot override every Steam Workshop version-selection rule.

## Data and logs

Runtime files are stored under:

```text
%LOCALAPPDATA%\CK3WorkshopAutoUpdater\data
```

Files include:

- `LastRun.log`
- `History.log`
- `State.json`

No Steam credentials are collected or stored.

## Configuration

Edit the installed `config.json` to change timing and retry behavior. Re-running `Install.cmd` updates the script while preserving an existing installed configuration and runtime data.

## Uninstallation

Double-click `Uninstall.cmd`.

Steam, CK3, Workshop subscriptions, and Workshop content are left unchanged.

## GitHub publishing

The repository is ready to publish. Runtime logs, state, backups, and generated release archives are excluded by `.gitignore`.

Suggested repository name:

```text
ck3-workshop-auto-updater
```

## Disclaimer

This project is not affiliated with Valve, Steam, or Paradox Interactive.
