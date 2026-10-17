# Canfield Deploy Toolkit

Windows deployment toolkit for common machine-setup tasks in one GUI:

- Rename the computer (with an optional restart).
- Set the password of the local `Site Photographer` account.
- Install LogMeIn using a sponsor-specific Deploy ID from a CSV file.
- Find and run Canfield Capture `setup.exe` installers from USB drives.

The toolkit can run as a PowerShell script or as a packaged executable.

## Project Files

- `Install-Toolkit.ps1`: Main WinForms app.
- `Build-Toolkit-Exe.ps1`: Builds `DeployToolkit.exe` using PS2EXE.
- `build_bypass.cmd`: Convenience wrapper to run the build script with execution policy bypass.
- `.github/workflows/build-exe.yml`: Builds EXE on every push and uploads it as an artifact.
- `.github/workflows/release-exe.yml`: Builds EXE on version tag push and publishes it to a GitHub Release.

## Requirements

### Runtime (using the script or EXE)

- Windows (PowerShell 5.1+ recommended).
- Administrator rights to install software.
- Network access to download LogMeIn MSI.
- Optional: `sponsors.csv` next to script/EXE (needed for the LogMeIn tab unless one was embedded at build time).

### Local EXE Build

- Windows PowerShell.
- Internet access to install `ps2exe` from PSGallery (first build only).

## CSV Format

The sponsor file must be named `sponsors.csv` and contain headers:

```csv
Sponsor,DeployID
My Sponsor,123456789
Another Sponsor,987654321
```

Behavior:

- If `sponsors.csv` exists beside the script/EXE, it is used.
- If missing, the EXE can fall back to an embedded CSV snapshot created at build time. The snapshot is only embedded when `sponsors.csv` exists next to `Build-Toolkit-Exe.ps1` during the build (it is not committed, so CI builds have no embedded list).

## Run the Toolkit (Script)

From PowerShell in this folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install-Toolkit.ps1
```

Optional parameters:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install-Toolkit.ps1 -CsvPath .\sponsors.csv -SilentArgs '/S /v/qn'
```

Notes:

- The script self-elevates to admin when needed.
- Default Canfield silent args are `/S /v/qn` and can be edited in the UI.

## Build EXE Locally

Option 1:

```powershell
powershell -ExecutionPolicy Bypass -File .\Build-Toolkit-Exe.ps1
```

Option 2:

```cmd
build_bypass.cmd
```

Output:

- `build\DeployToolkit.exe`

## GitHub Actions

### Push Build Workflow

Workflow: `.github/workflows/build-exe.yml`

- Trigger: every push (plus manual dispatch).
- Runner: `windows-latest`.
- Action: runs `Build-Toolkit-Exe.ps1`.
- Artifact: `DeployToolkit-exe` containing `build/DeployToolkit.exe`.

### Release Workflow

Workflow: `.github/workflows/release-exe.yml`

- Trigger: tag pushes matching `v*` (for example `v1.0.0`) and manual dispatch.
- Runner: `windows-latest`.
- Action: builds EXE, then creates/updates the GitHub Release for the tag.
- Asset uploaded: `build/DeployToolkit.exe`.

Create a release by pushing a version tag:

```bash
git tag v1.0.0
git push origin v1.0.0
```

## How the Toolkit Works

### Computer Name Tab

- Shows the current computer name.
- Validates the new name (1-15 letters, digits or hyphens; no leading/trailing hyphen; not only digits).
- Renames via `Rename-Computer` after confirmation, then offers to restart.

### Site Photographer Tab

- Sets the password of the local `Site Photographer` account.
- The entered password is normalized: symbols, spaces and numbers are removed and letters are lower-cased.
- The account is set to never expire and the user cannot change the password.

### LogMeIn Tab

- Loads sponsor list from CSV.
- Downloads latest `logmein.msi` via `curl.exe`.
- Installs silently with selected `DEPLOYID` using `msiexec.exe`.

### Canfield Capture Tab

- Scans attached USB drives for folders containing `setup.exe`.
- Lets you choose installer path and silent switches.
- Runs installer and reports result or reboot-required codes.

## Troubleshooting

- No sponsors shown:
  - Check `sponsors.csv` exists and has `Sponsor,DeployID` headers.
- Build fails on module install:
  - Ensure internet access and PSGallery availability.
- EXE missing after workflow run:
  - Check workflow logs and confirm `build/DeployToolkit.exe` was produced.
- Canfield install returns non-zero exit code:
  - Try different silent switches for that installer package type.
