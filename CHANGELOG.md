# Changelog

## 0.2.0 — 2026-08-05

- Removed the PowerShell 7 requirement.
- Added Windows PowerShell 5.1-compatible state loading.
- Updated installation, hidden startup, and uninstallation to use Windows PowerShell included with Windows.
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
