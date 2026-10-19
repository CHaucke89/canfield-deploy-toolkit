# Canfield Deployment Toolkit

Windows deployment toolkit for common machine-setup tasks in one GUI (window title: "Canfield Deployment Toolkit"):

- Rename the computer (with an optional restart).
- Set the password of the local `Site Photographer` account.
- Install LogMeIn using a sponsor-specific Deploy ID from a CSV file.
- Find and run Canfield Capture `setup.exe` installers from USB drives.
- Clean Canfield Capture site databases and force SSCT users to change passwords.

The toolkit can run as a PowerShell script or as a packaged executable (`DeployToolkit.exe`).

## Project Files

- `Install-Toolkit.ps1`: Entry point (startup, elevation, loads `src\`).
- `src\LoadOrder.ps1`: Ordered list of source files to load (also used by the build).
- `src\lib\`: UI-free helpers (validation, sponsor CSV, USB discovery, Canfield Capture cleanup).
- `src\ui\`: Main window and shared progress/message helpers.
- `src\tabs\`: One file per tab (Computer Name, Site Photographer, LogMeIn, Canfield Capture, Cleanup Tool).
- `Build-Toolkit-Exe.ps1`: Inlines `src\` into the entry script and builds a single `DeployToolkit.exe` using PS2EXE.
- `assets\toolkit.ico`: Icon embedded into the EXE (file icon, window and taskbar). Required by the build.
- `build_bypass.cmd`: Convenience wrapper to run the build script with execution policy bypass (run it from the repo folder).
- `.github/workflows/build-exe.yml`: Builds EXE on every push and uploads it as an artifact.
- `.github/workflows/release-exe.yml`: Builds EXE on version tag push and publishes it to a GitHub Release.

## Requirements

### Runtime (using the script or EXE)

- Windows with Windows PowerShell 5.1 (required: the Site Photographer and Cleanup tabs use `Set-LocalUser` / `Get-LocalGroupMember`).
- Administrator rights. The script relaunches itself elevated; the EXE asks for admin through UAC when it starts.
- Network access to download LogMeIn MSI.
- Optional: `sponsors.csv` next to script/EXE (needed for the LogMeIn tab unless one was embedded at build time).

### Local EXE Build

- Windows PowerShell.
- Internet access to install `ps2exe` from PSGallery (first build only).
- `assets\toolkit.ico` present (it is committed; the build fails without it).

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
- The custom window/taskbar icon only appears in the EXE; the script shows the standard PowerShell icon.
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

Optionally stamp a version into the EXE (defaults to `1.0.0.0`; a leading `v` is dropped and missing parts become `0`):

```powershell
powershell -ExecutionPolicy Bypass -File .\Build-Toolkit-Exe.ps1 -Version v1.2.0
```

What the build does:

1. Installs `ps2exe` if it is missing.
2. Inlines the `src\` files (in `src\LoadOrder.ps1` order) into a temporary copy of `Install-Toolkit.ps1`.
3. Embeds `sponsors.csv` as a fallback if it is present.
4. Runs PS2EXE with `assets\toolkit.ico` as the icon, a UAC admin manifest, no console window, and the chosen version.

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
- Action: builds EXE with the tag as its version (`v1.2.0` becomes `1.2.0.0`), then creates/updates the GitHub Release for the tag. Manual runs from a branch keep `1.0.0.0`.
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

- Scans attached USB drives for folders containing `setup.exe`. The scan runs automatically the first time the tab is opened, can be cancelled, and can be repeated with **Scan USB**.
- Lets you choose installer path and silent switches.
- Runs installer and reports result or reboot-required codes.

### Cleanup Tool Tab

Ported from the Cleanup Tool in the Canfield Setup Tool (`CST.ps1`, not included in this repo).

- Lists `C:\ProgramData\Canfield\Canfield Capture v*` versions, split into "needs cleanup" (a one-character site/PID folder exists under `Databases\*\`) and "already clean". Dirty versions are preselected.
- After confirmation, for each selected version: deletes `SSCT_System_Data*.sdf`, `Temp`, and everything in `Databases` except `Registered_Users.sdf`; clears `C:\Calibration Report`; removes Vectra calibration data for v3.4.0-v3.5.1; prefixes that version's `DiagLib` logs with `CU-`.
- Opens each cleaned version's Canfield Capture (`C:\Program Files (x86)\Canfield Scientific Inc\<version>\Canfield Capture.exe`) so the Site ID can be set, and waits for it to close. If that EXE is missing, it warns you to set the Site ID manually.
- Finally sets every local `SSCT` group member to change password at next logon. If that step fails, it reports that the databases were cleaned but the passwords were not expired.

## Troubleshooting

- No sponsors shown:
  - Check `sponsors.csv` exists and has `Sponsor,DeployID` headers.
- Build fails on module install:
  - Ensure internet access and PSGallery availability.
- Build fails mentioning the icon:
  - Confirm `assets\toolkit.ico` exists next to `Build-Toolkit-Exe.ps1`.
- Build fails with "is not a valid version":
  - Pass `-Version` (or tag) as `vMAJOR.MINOR[.BUILD[.REVISION]]`, for example `v1.2.0`. Suffixes like `-beta` are not supported.
- EXE missing after workflow run:
  - Check workflow logs and confirm `build/DeployToolkit.exe` was produced.
- Canfield install returns non-zero exit code:
  - Try different silent switches for that installer package type.
