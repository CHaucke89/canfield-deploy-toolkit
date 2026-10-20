# Canfield Deployment Toolkit

Windows deployment toolkit for common machine-setup tasks in one GUI (window title: "Canfield Deployment Toolkit"):

- Rename the computer, set the `Site Photographer` password, and open Date/Time and Windows Update settings.
- Create, reset and delete SSCT site users, and create the `SharedAdmin` account.
- Install LogMeIn using a sponsor-specific Deploy ID from a CSV file, enroll in Resolve MDM, and manage the Canfield scripts.
- Find and run Canfield Capture `setup.exe` installers from USB drives.
- Clean Canfield Capture site databases, set Site IDs, and force SSCT users to change passwords.
- Check the machine's status and save a QC report.

The toolkit can run as a PowerShell script or as a packaged executable (`DeployToolkit.exe`).

## Project Files

- `Install-Toolkit.ps1`: Entry point (startup, elevation, loads `src\`).
- `src\LoadOrder.ps1`: Ordered list of source files to load (also used by the build).
- `src\lib\`: UI-free helpers (validation, sponsor CSV, USB discovery, Canfield Capture cleanup, local users, status checks).
- `src\ui\`: Main window and shared progress/message helpers.
- `src\tabs\`: One file per tab (Computer, Remote Access, Canfield Capture, Cleanup Tool, Summary, Users, Scripts).
- `Build-Toolkit-Exe.ps1`: Inlines `src\` into the entry script and builds a single `DeployToolkit.exe` using PS2EXE.
- `assets\toolkit.ico`: Icon embedded into the EXE (file icon, window and taskbar). Required by the build.
- `build_bypass.cmd`: Convenience wrapper to run the build script with execution policy bypass (run it from the repo folder).
- `.github/workflows/build-exe.yml`: Builds EXE on every push and uploads it as an artifact.
- `.github/workflows/release-exe.yml`: Builds EXE on version tag push and publishes it to a GitHub Release.

## Requirements

### Runtime (using the script or EXE)

- Windows with Windows PowerShell 5.1 (required: the Computer, Users and Cleanup tabs use the `LocalAccounts` cmdlets such as `Set-LocalUser` / `Get-LocalGroupMember`).
- Administrator rights. The script relaunches itself elevated; the EXE asks for admin through UAC when it starts.
- Network access to download LogMeIn MSI.
- Optional: `sponsors.csv` next to script/EXE (needed for LogMeIn on the Remote Access tab unless one was embedded at build time).
- Optional: a `Scripts` folder next to script/EXE for the Canfield scripts and Resolve MDM (see [Scripts Folder](#scripts-folder)).

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

## Scripts Folder

The Scripts tab (Canfield scripts) and the Remote Access tab (Resolve MDM) use these files. They are not in this repo. The toolkit looks in a `Scripts` folder next to the script/EXE first, then in `C:\tools\Canfield_Setup_Tool\Scripts` (the old Canfield Setup Tool location). Buttons are greyed out when a file is missing.

```text
Scripts\
  Reboot Script\wtrbt.bat
  bginfo\bginfosetup.bat
  WindowsUpdate\WindowsUpdate\WindowsUpdate.bat
  ResolveMDM\CanfieldScientific.ppkg
```

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

### Computer Tab

- Computer name: shows the current name, validates the new one (1-15 letters, digits or hyphens; no leading/trailing hyphen; not only digits), renames via `Rename-Computer` after confirmation, then offers to restart.
- Site Photographer password: the entered password is normalized (symbols, spaces and numbers removed, letters lower-cased); the account is set to never expire and the user cannot change the password.
- Date, time and time zone: picking a time zone from the dropdown sets it right away (`Set-TimeZone`). **Sync Time** starts the Windows Time service if needed and syncs the clock with the time server (`w32tm /resync /force`).
- Windows Update: opens Windows Update in Settings.
- BitLocker Encryption Status: shows whether the system drive is encrypted (green), encrypting or decrypting with the percentage done (amber, refreshed every 10 seconds while the tab is open), or not encrypted / missing a recovery key (red).

### Remote Access Tab

- LogMeIn: shows whether LogMeIn is installed, loads the sponsor list from CSV, downloads the latest `logmein.msi` via `curl.exe` and installs it silently with the selected `DEPLOYID` using `msiexec.exe`. Asks first if LogMeIn is already installed.
- Resolve MDM: shows the enrollment status and enrolls with `CanfieldScientific.ppkg` (`Install-ProvisioningPackage`).

### Canfield Capture Tab

- Scans attached USB drives for folders containing `setup.exe`. The scan runs automatically the first time the tab is opened, can be cancelled, and can be repeated with **Scan USB**.
- Lets you choose installer path and silent switches.
- Asks first if a version of Canfield Capture is already installed.
- Runs installer and reports result or reboot-required codes.

### Cleanup Tool Tab

Ported from the Cleanup Tool in the Canfield Setup Tool (`CST.ps1`, not included in this repo), like the Users, Remote Access and Summary features.

- Lists `C:\ProgramData\Canfield\Canfield Capture v*` versions, split into "needs cleanup" (a one-character site/PID folder exists under `Databases\*\`) and "already clean". Dirty versions are preselected.
- After confirmation, for each selected version: deletes `SSCT_System_Data*.sdf`, `Temp`, and everything in `Databases` except `Registered_Users.sdf` (kept at any depth; registered users are never deleted by cleanup); clears `C:\Calibration Report`; removes Vectra calibration data for v3.4.0-v3.5.1; prefixes that version's `DiagLib` logs with `CU-`.
- Opens each cleaned version's Canfield Capture (`C:\Program Files (x86)\Canfield Scientific Inc\<version>\Canfield Capture.exe`) so the Site ID can be set, and waits for it to close. If that EXE is missing, it warns you to set the Site ID manually.
- Finally sets every local `SSCT` group member to change password at next logon. If that step fails, it reports that the databases were cleaned but the passwords were not expired.
- **Set Site IDs** opens every installed version in turn so its Site ID can be set. First it copies `Registered_Users.sdf` from the first version that has one to versions that have none; an existing `Registered_Users.sdf` is never overwritten.

### Summary Tab

- Shows computer name, service tag, model, date and time, time zone, Wi-Fi, BitLocker, LogMeIn, Resolve MDM, installed Canfield Capture versions and the number of site users. Refreshes each time the tab is opened.
- Lists installed protocols with their version, SSO use, and the Site ID last logged by Canfield Capture (`C:\ProgramData\Canfield\DiagLib`). A cleaned version shows "Not set" until its Site ID is set again.
- **Save Report** (technician initials required) saves a JPG picture of the window plus a `.txt` with the same name, containing every check, the protocols, initials and comments.

### Users Tab

- Create site user: first name, last name and optional prefix. The username fills in as first initial + last name (letters only, lower case) and can be edited. The temporary password defaults to `Photo321`. The user is added to the local `SSCT` group (created if missing) and must change the password at first sign-in.
- If every installed protocol uses SSO, the tab warns that local users are usually not needed and asks before creating one.
- Lists the local users in the `SSCT` group. Reset Password sets a new temporary password (expired, so it must be changed at next sign-in); Change Name sets the full name.
- Delete User removes the selected Windows account after a Yes/No that names it. This is the only place the toolkit deletes a user. `Site Photographer`, `SharedAdmin`, `Administrator` and the signed-in account cannot be deleted.
- Create SharedAdmin Account asks for a password, then creates `SharedAdmin` (password never expires, user cannot change it) in the local Administrators group.
- Passwords are never stored on disk.

### Scripts Tab

- For the Reboot script (`RebootShutdown` task), BGInfo (`BginfoDesktop`) and the Windows Update script (`WindowsUpdate`), shows On/Off/Not installed and offers Install, Turn On and Turn Off.
- Installers come from the Scripts folder (see [Scripts Folder](#scripts-folder)).

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
