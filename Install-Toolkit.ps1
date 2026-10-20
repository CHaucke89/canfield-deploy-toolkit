<#
.SYNOPSIS
    Deploy Toolkit: one window with six tabs.
      1) Computer         - renames the machine, sets the 'Site Photographer' password, sets the time zone, syncs the clock, opens Windows Update, shows BitLocker status.
      2) Users            - creates, resets and deletes SSCT site users; creates the SharedAdmin account.
      3) Remote Access    - installs LogMeIn for a sponsor from the CSV, enrolls in Resolve MDM, manages the Canfield scripts.
      4) Canfield Capture - finds setup.exe on connected USB drive(s); installs the chosen one silently.
      5) Cleanup Tool     - wipes Canfield Capture site data per version, sets Site IDs, expires SSCT passwords.
      6) Summary          - machine status and installed protocols; saves a QC report.

    This file is only the entry point (startup, elevation, loading, show window). The UI and logic live
    in src\ (see src\LoadOrder.ps1); Build-Toolkit-Exe.ps1 inlines those files into the single-file exe.

.PARAMETER CsvPath
    Sponsor CSV (Sponsor,DeployID). Defaults to sponsors.csv next to the script/exe.
    If missing, an embedded copy (added by Build-Toolkit-Exe.ps1) is used.

.PARAMETER SilentArgs
    Default silent switches for Canfield Capture installers (editable in the window).
    Common: /S (NSIS), /VERYSILENT /NORESTART (Inno), /quiet /norestart (WiX Burn), /s /v"/qn" (InstallShield).
#>
[CmdletBinding()]
param(
    [string]$CsvPath,
    [string]$SilentArgs = '/S /v/qn'
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$appTitle = 'Canfield Deployment Toolkit'

# --- Exe vs .ps1 detection (PS2EXE leaves $PSScriptRoot/$PSCommandPath empty) ---
$procPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$isExe    = (Split-Path -Leaf $procPath) -notmatch '^(powershell|powershell_ise|pwsh)\.exe$'
if ($isExe) {
    $scriptPath = $null
    $scriptDir  = Split-Path -Parent $procPath
} else {
    $scriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
    $scriptDir  = if ($scriptPath) { Split-Path -Parent $scriptPath } else { (Get-Location).Path }
}
if (-not $CsvPath) { $CsvPath = Join-Path $scriptDir 'sponsors.csv' }

# Build-Toolkit-Exe.ps1 replaces the next line with a snapshot of the CSV (fallback copy).
$EmbeddedCsv = $null # __EMBEDDED_CSV__

# --- Self-elevate when run as a .ps1 (the exe uses a UAC manifest instead) ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $isExe) {
    if (-not $scriptPath) {
        [void][System.Windows.Forms.MessageBox]::Show(
            'Run this as a saved .ps1 file (or use the exe) so it can relaunch as administrator.',
            $appTitle, 'OK', 'Warning')
        exit 1
    }
    $argList = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -CsvPath "{1}" -SilentArgs "{2}"' -f $scriptPath, $CsvPath, $SilentArgs
    try { Start-Process -FilePath powershell.exe -Verb RunAs -ArgumentList $argList }
    catch {
        [void][System.Windows.Forms.MessageBox]::Show(
            'Administrator rights are required to install software.', $appTitle, 'OK', 'Warning')
    }
    exit
}

# =====================================================================
#  Load modules (src\LoadOrder.ps1 lists them). Build-Toolkit-Exe.ps1 replaces everything
#  between the markers with the inlined file contents, so the exe needs no src\ folder.
# =====================================================================
# __SOURCES_BEGIN__
$srcDir = Join-Path $scriptDir 'src'
foreach ($rel in (& (Join-Path $srcDir 'LoadOrder.ps1'))) { . (Join-Path $srcDir $rel) }
# __SOURCES_END__

[void]$form.ShowDialog()
