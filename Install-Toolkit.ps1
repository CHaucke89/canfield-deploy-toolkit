<#
.SYNOPSIS
        Deploy Toolkit: one window with three tabs.
      1) LogMeIn      - pick a sponsor from the CSV; installs LogMeIn silently with that Deploy ID.
      2) Canfield Capture Installer - finds setup.exe on connected USB drive(s); installs the chosen one silently.
            3) Device Status - shows ResolveMDM and BitLocker status; can enroll ResolveMDM.

.PARAMETER CsvPath
    Sponsor CSV (Sponsor,DeployID). Defaults to LogMeInDeploy.csv next to the script/exe.
    If missing, an embedded copy (added by Build-Toolkit-Exe.ps1) is used.

.PARAMETER SilentArgs
    Default silent switches for Canfield Capture installer (editable in the window).
#>
[CmdletBinding()]
param(
    [string]$CsvPath,
    [string]$SilentArgs = '/S /v/qn'
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$appTitle = 'Canfield Deploy Toolkit'

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
if (-not $CsvPath) { $CsvPath = Join-Path $scriptDir 'LogMeInDeploy.csv' }

# Build-Toolkit-Exe.ps1 replaces the next line with a snapshot of the CSV (fallback copy).
$EmbeddedCsv = $null # __EMBEDDED_CSV__

$logMeInScript = Join-Path $scriptDir 'Install-LogMeIn.ps1'
$canfieldScript = Join-Path $scriptDir 'Install-CanfieldCapture.ps1'
$deviceStatusScript = Join-Path $scriptDir 'Install-DeviceStatus.ps1'
foreach ($requiredScript in @($logMeInScript, $canfieldScript, $deviceStatusScript)) {
    if (-not (Test-Path -LiteralPath $requiredScript)) {
        [void][System.Windows.Forms.MessageBox]::Show(
            "Required file not found:`n$requiredScript",
            $appTitle, 'OK', 'Error')
        exit 1
    }
    . $requiredScript
}

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
#  Main window
# =====================================================================
$form = New-Object System.Windows.Forms.Form
$form.Text            = $appTitle
$form.ClientSize      = New-Object System.Drawing.Size(540, 430)
$form.StartPosition   = 'CenterScreen'
$form.FormBorderStyle = 'Sizable'
$form.MinimumSize     = New-Object System.Drawing.Size(520, 460)   # smallest window size allowed

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = New-Object System.Drawing.Point(10, 10)
$tabs.Size     = New-Object System.Drawing.Size(520, 370)
$tabs.Anchor = 'Top,Bottom,Left,Right'
$form.Controls.Add($tabs)

$tabLmi = New-Object System.Windows.Forms.TabPage; $tabLmi.Text = 'LogMeIn'
$tabUsb = New-Object System.Windows.Forms.TabPage; $tabUsb.Text = 'Canfield Capture Installer'
$tabStatus = New-Object System.Windows.Forms.TabPage; $tabStatus.Text = 'Device Status'
$tabs.TabPages.Add($tabLmi); $tabs.TabPages.Add($tabUsb); $tabs.TabPages.Add($tabStatus)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text         = 'Close'
$btnClose.Location     = New-Object System.Drawing.Point(445, 390)
$btnClose.Size         = New-Object System.Drawing.Size(85, 28)
$btnClose.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
$btnClose.Anchor = 'Bottom,Right'
$form.Controls.Add($btnClose)
$form.CancelButton = $btnClose

# =====================================================================
#  Shared progress window + helpers
# =====================================================================
$status = New-Object System.Windows.Forms.Form
$status.Text            = $appTitle
$status.ClientSize      = New-Object System.Drawing.Size(410, 120)
$status.StartPosition   = 'CenterParent'
$status.FormBorderStyle = 'FixedDialog'
$status.ControlBox      = $false
$status.ShowInTaskbar   = $false
$status.TopMost         = $true

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = New-Object System.Drawing.Point(15, 12)
$statusLabel.Size     = New-Object System.Drawing.Size(380, 40)
$status.Controls.Add($statusLabel)

$bar = New-Object System.Windows.Forms.ProgressBar
$bar.Style    = 'Marquee'
$bar.Location = New-Object System.Drawing.Point(15, 58)
$bar.Size     = New-Object System.Drawing.Size(380, 18)
$status.Controls.Add($bar)

$script:cancelRequested = $false
$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Text     = 'Cancel'
$btnStop.Location = New-Object System.Drawing.Point(320, 86)
$btnStop.Size     = New-Object System.Drawing.Size(75, 24)
$btnStop.Add_Click({ $script:cancelRequested = $true })
$status.Controls.Add($btnStop)

function Set-Status([string]$text) {
    $statusLabel.Text = $text
    [System.Windows.Forms.Application]::DoEvents()
}

function Enter-Busy([string]$text, [bool]$cancellable = $false) {
    $script:cancelRequested = $false
    $btnStop.Visible = $cancellable
    $form.Enabled = $false
    $status.Show($form)
    Set-Status $text
}

function Exit-Busy {
    $status.Hide()
    $form.Enabled = $true
    [void]$form.Activate()
}

function Show-Message([string]$text, [string]$icon) {
    [void][System.Windows.Forms.MessageBox]::Show($form, $text, $appTitle, 'OK', $icon)
}

# Starts a process and keeps the UI alive with an elapsed timer until it exits.
function Invoke-WithProgress([string]$file, [string]$arguments, [string]$workDir, [string]$windowStyle, [string]$label) {
    $p = @{ FilePath = $file; PassThru = $true; WindowStyle = $windowStyle }
    if ($arguments) { $p.ArgumentList = $arguments }
    if ($workDir)   { $p.WorkingDirectory = $workDir }
    $proc = Start-Process @p
    $null = $proc.Handle   # cache handle so ExitCode is readable after exit
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not $proc.HasExited) {
        Set-Status ("{0}`nElapsed: {1:mm\:ss}" -f $label, $sw.Elapsed)
        Start-Sleep -Milliseconds 250
    }
    return $proc.ExitCode
}

# =====================================================================
#  Tab wiring (modularized)
# =====================================================================
$enterBusyAction = {
    param([string]$text, [bool]$cancellable = $false)
    Enter-Busy $text $cancellable
}
$exitBusyAction = {
    Exit-Busy
}
$showMessageAction = {
    param([string]$text, [string]$icon)
    Show-Message $text $icon
}
$setStatusAction = {
    param([string]$text)
    Set-Status $text
}
$invokeWithProgressAction = {
    param([string]$file, [string]$arguments, [string]$workDir, [string]$windowStyle, [string]$label)
    Invoke-WithProgress $file $arguments $workDir $windowStyle $label
}

Initialize-LogMeInTab -Tab $tabLmi -CsvPath $CsvPath -EmbeddedCsv $EmbeddedCsv `
    -EnterBusy $enterBusyAction -ExitBusy $exitBusyAction -ShowMessage $showMessageAction `
    -InvokeWithProgress $invokeWithProgressAction

Initialize-CanfieldCaptureTab -Tab $tabUsb -Tabs $tabs -SilentArgs $SilentArgs `
    -EnterBusy $enterBusyAction -ExitBusy $exitBusyAction -ShowMessage $showMessageAction `
    -SetStatus $setStatusAction -InvokeWithProgress $invokeWithProgressAction

Initialize-DeviceStatusTab -Tab $tabStatus -Form $form -ScriptDir $scriptDir `
    -EnterBusy $enterBusyAction -ExitBusy $exitBusyAction -ShowMessage $showMessageAction

[void]$form.ShowDialog()
