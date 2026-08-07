# Changelog

## 0.3.0 — 2026-08-07

- Added a user-friendly Windows Setup executable.
- Added automatic installer builds through GitHub Actions.
- Added an Installed Apps uninstaller and Start menu shortcuts.
- Preserved existing configuration, state, and log files during upgrades.
- Changed Workshop update detection to prefer the newest manifest reported by Steam's public Workshop API.
- Added fallback to Steam's cached latest manifest when public API metadata is unavailable.
- Changed the updater to attempt a normal Steam Workshop download before using repair mode.
- Added controlled repair for Workshop items that remain stuck on outdated manifests after Steam reports a successful download.
- Added automatic backups of the affected Workshop manifest records and mod content before repair.
- Added automatic rollback when a repair does not complete successfully.
- Limited clean Workshop repair to one affected item per updater run.

## 0.2.0 — 2026-08-05

- Removed the PowerShell 7 requirement while continuing to prefer PowerShell 7 when installed.
- Added automatic fallback to Windows PowerShell 5.1.
- Added Windows PowerShell 5.1-compatible state loading.
- Updated installation, hidden startup, uninstallation, and release building to select the available PowerShell runtime automatically.
- Added a release builder that creates versioned ZIP and SHA-256 files in `dist`.

## 0.1.1 — 2026-08-05

- Fixed formatted log messages incorrectly treating PowerShell's `-f` operator as a command parameter.
- Fixed crashes after Steam returned a Workshop download result.
- The updater now continues processing the remaining Workshop items after each result.

## 0.1.0 — 2026-08-03

- Initial experimental release.
- Detects differing CK3 Workshop content manifests.
- Requests targeted Steam Workshop downloads.
- Verifies actual installed manifest changes.
- Suppresses repeated no-change requests for the same remote manifest.
- Runs invisibly at Windows sign-in.
- Includes double-click installation, manual run, log access, and uninstallation commands.
- Uses English runtime messages.
