<#
.SYNOPSIS
    Deploy Toolkit: one window with two tabs.
      1) LogMeIn      - pick a sponsor from the CSV; installs LogMeIn silently with that Deploy ID.
      2) Canfield Capture Installer - finds setup.exe on connected USB drive(s); installs the chosen one silently.

.PARAMETER CsvPath
    Sponsor CSV (Sponsor,DeployID). Defaults to LogMeInDeploy.csv next to the script/exe.
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
if (-not $CsvPath) { $CsvPath = Join-Path $scriptDir 'LogMeInDeploy.csv' }

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
#  Main window
# =====================================================================
$form = New-Object System.Windows.Forms.Form
$form.Text            = $appTitle
$form.ClientSize      = New-Object System.Drawing.Size(540, 430)
$form.StartPosition   = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox     = $false

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = New-Object System.Drawing.Point(10, 10)
$tabs.Size     = New-Object System.Drawing.Size(520, 370)
$form.Controls.Add($tabs)

$tabLmi = New-Object System.Windows.Forms.TabPage; $tabLmi.Text = 'LogMeIn'
$tabUsb = New-Object System.Windows.Forms.TabPage; $tabUsb.Text = 'Canfield Capture'
$tabs.TabPages.Add($tabLmi); $tabs.TabPages.Add($tabUsb)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text         = 'Close'
$btnClose.Location     = New-Object System.Drawing.Point(445, 390)
$btnClose.Size         = New-Object System.Drawing.Size(85, 28)
$btnClose.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
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
#  Tab 1: LogMeIn
# =====================================================================
$rows = $null
if (Test-Path -LiteralPath $CsvPath)  { $rows = Import-Csv -LiteralPath $CsvPath }
elseif ($EmbeddedCsv)                 { $rows = $EmbeddedCsv | ConvertFrom-Csv }

$sponsors = @($rows | Where-Object { $_.Sponsor -and $_.DeployID } | ForEach-Object {
    [pscustomobject]@{ Sponsor = $_.Sponsor.Trim(); DeployID = $_.DeployID.Trim() }
} | Sort-Object Sponsor)

$lmiLabel = New-Object System.Windows.Forms.Label
$lmiLabel.Text     = 'Select the sponsor for this machine:'
$lmiLabel.Location = New-Object System.Drawing.Point(15, 20)
$lmiLabel.AutoSize = $true
$tabLmi.Controls.Add($lmiLabel)

$combo = New-Object System.Windows.Forms.ComboBox
$combo.DropDownStyle = 'DropDownList'
$combo.Location      = New-Object System.Drawing.Point(15, 45)
$combo.Size          = New-Object System.Drawing.Size(480, 24)
$combo.DisplayMember = 'Sponsor'
foreach ($s in $sponsors) { [void]$combo.Items.Add($s) }
$tabLmi.Controls.Add($combo)

$btnLmi = New-Object System.Windows.Forms.Button
$btnLmi.Text     = 'Install LogMeIn'
$btnLmi.Location = New-Object System.Drawing.Point(375, 90)
$btnLmi.Size     = New-Object System.Drawing.Size(120, 30)
$btnLmi.Enabled  = $false
$tabLmi.Controls.Add($btnLmi)

if ($sponsors.Count -eq 0) {
    $combo.Enabled = $false
    $lmiNote = New-Object System.Windows.Forms.Label
    $lmiNote.Text      = "No sponsors available. CSV not found or empty:`n$CsvPath"
    $lmiNote.ForeColor = [System.Drawing.Color]::Firebrick
    $lmiNote.Location  = New-Object System.Drawing.Point(15, 135)
    $lmiNote.Size      = New-Object System.Drawing.Size(480, 40)
    $tabLmi.Controls.Add($lmiNote)
}

$combo.Add_SelectedIndexChanged({ $btnLmi.Enabled = ($null -ne $combo.SelectedItem) })

$btnLmi.Add_Click({
    $choice = $combo.SelectedItem
    if ($null -eq $choice) { return }

    $msi = Join-Path $env:TEMP 'LogMeIn.msi'
    Enter-Busy "Downloading latest LogMeIn installer..."
    try {
        $curlArgs = '-sS --fail -L https://secure.logmein.com/logmein.msi -o "{0}"' -f $msi
        $code = Invoke-WithProgress 'curl.exe' $curlArgs $null 'Hidden' 'Downloading latest LogMeIn installer...'
        if ($code -ne 0) {
            Exit-Busy
            Show-Message "Download failed (curl exit code $code). Check the network connection and try again." 'Error'
            return
        }

        $msiArgs = '/i "{0}" /quiet DEPLOYID={1} INSTALLMETHOD=5 FQDNDESC=1' -f $msi, $choice.DeployID
        $code = Invoke-WithProgress 'msiexec.exe' $msiArgs $null 'Hidden' "Installing LogMeIn for $($choice.Sponsor)..."
        Exit-Busy
        switch ($code) {
            0       { Show-Message "All done! LogMeIn installed for $($choice.Sponsor)." 'Information' }
            { $_ -in 1641, 3010 } { Show-Message "LogMeIn installed for $($choice.Sponsor). A reboot is required to finish." 'Information' }
            default { Show-Message "Installation failed (msiexec exit code $code)." 'Error' }
        }
    } catch {
        Exit-Busy
        Show-Message "Unexpected error:`n$($_.Exception.Message)" 'Error'
    } finally {
        Remove-Item -LiteralPath $msi -Force -ErrorAction SilentlyContinue
    }
})

# =====================================================================
#  Tab 2: Canfield Capture
# =====================================================================
function Get-UsbDriveRoots {
    $roots = @()
    try {
        $roots = @(Get-Disk -ErrorAction Stop | Where-Object { $_.BusType -eq 'USB' } |
            Get-Partition -ErrorAction SilentlyContinue |
            Where-Object { $_.DriveLetter -match '[A-Za-z]' } |
            ForEach-Object { '{0}:\' -f $_.DriveLetter })
    } catch { }
    if ($roots.Count -eq 0) {   # fallback: removable media
        $roots = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=2' |
            ForEach-Object { '{0}\' -f $_.DeviceID })
    }
    return @($roots | Where-Object { Test-Path -LiteralPath $_ } | Sort-Object -Unique)
}

$btnScan = New-Object System.Windows.Forms.Button
$btnScan.Text     = 'Scan USB'
$btnScan.Location = New-Object System.Drawing.Point(15, 12)
$btnScan.Size     = New-Object System.Drawing.Size(90, 26)
$tabUsb.Controls.Add($btnScan)

$usbInfo = New-Object System.Windows.Forms.Label
$usbInfo.Text     = 'Click Scan USB to look for setup.exe.'
$usbInfo.Location = New-Object System.Drawing.Point(115, 18)
$usbInfo.Size     = New-Object System.Drawing.Size(380, 18)
$tabUsb.Controls.Add($usbInfo)

$list = New-Object System.Windows.Forms.ListBox
$list.Location      = New-Object System.Drawing.Point(15, 48)
$list.Size          = New-Object System.Drawing.Size(480, 200)
$list.HorizontalScrollbar = $true
$list.DisplayMember = 'Display'
$tabUsb.Controls.Add($list)

$argLabel = New-Object System.Windows.Forms.Label
$argLabel.Text     = 'Silent install switches (leave default values if unsure):'
$argLabel.Location = New-Object System.Drawing.Point(15, 260)
$argLabel.AutoSize = $true
$tabUsb.Controls.Add($argLabel)

$argBox = New-Object System.Windows.Forms.TextBox
$argBox.Text     = $SilentArgs
$argBox.Location = New-Object System.Drawing.Point(15, 282)
$argBox.Size     = New-Object System.Drawing.Size(480, 22)
$tabUsb.Controls.Add($argBox)

$btnUsb = New-Object System.Windows.Forms.Button
$btnUsb.Text     = 'Install Selected'
$btnUsb.Location = New-Object System.Drawing.Point(375, 315)
$btnUsb.Size     = New-Object System.Drawing.Size(120, 30)
$btnUsb.Enabled  = $false
$tabUsb.Controls.Add($btnUsb)

$script:usbScanned = $false

function Invoke-UsbScan {
    $script:usbScanned = $true
    $list.Items.Clear()
    $btnUsb.Enabled = $false

    Enter-Busy "Looking for USB drives..." $true
    $roots = Get-UsbDriveRoots
    if ($roots.Count -eq 0) {
        Exit-Busy
        $usbInfo.Text = 'No USB drive detected. Insert one and click Scan USB.'
        return
    }

    $skipNames = @('$RECYCLE.BIN', 'System Volume Information')
    $found = New-Object System.Collections.Generic.List[string]
    $stack = New-Object System.Collections.Generic.Stack[string]
    foreach ($r in $roots) { $stack.Push($r) }

    $scanned = 0
    while ($stack.Count -gt 0 -and -not $script:cancelRequested) {
        $dir = $stack.Pop()
        $scanned++
        if ($scanned % 25 -eq 0) { Set-Status ("Searching USB drive for Canfield Capture installers...`n{0}" -f $dir) }
        else { [System.Windows.Forms.Application]::DoEvents() }
        try {
            if ([System.IO.File]::Exists((Join-Path $dir 'setup.exe'))) { $found.Add($dir) }
            foreach ($sub in [System.IO.Directory]::EnumerateDirectories($dir)) {
                if ($skipNames -contains (Split-Path -Leaf $sub)) { continue }
                # don't follow junctions/symlinks (avoids loops)
                if ([System.IO.File]::GetAttributes($sub) -band [System.IO.FileAttributes]::ReparsePoint) { continue }
                $stack.Push($sub)
            }
        } catch { }   # unreadable folder: skip
    }
    $cancelled = $script:cancelRequested
    Exit-Busy

    if ($cancelled) { $usbInfo.Text = 'Scan cancelled.'; return }
    if ($found.Count -eq 0) { $usbInfo.Text = 'No installer found on the USB drive.'; return }

    foreach ($f in ($found | Sort-Object)) {
        $name = Split-Path -Leaf $f
        if (-not $name) { $name = $f }   # setup.exe in the drive root
        $display = '{0}    ({1})' -f $name, $f
        [void]$list.Items.Add([pscustomobject]@{ Display = $display; Folder = $f })
    }
    $usbInfo.Text = 'Found installer(s) in {0} folder(s). Select one:' -f $found.Count
}

$btnScan.Add_Click({ Invoke-UsbScan })
$list.Add_SelectedIndexChanged({ $btnUsb.Enabled = ($null -ne $list.SelectedItem) })
$tabs.Add_SelectedIndexChanged({
    if ($tabs.SelectedTab -eq $tabUsb -and -not $script:usbScanned) { Invoke-UsbScan }
})

$btnUsb.Add_Click({
    $choice = $list.SelectedItem
    if ($null -eq $choice) { return }
    $setup  = Join-Path $choice.Folder 'setup.exe'
    $swArgs = $argBox.Text.Trim()

    if (-not (Test-Path -LiteralPath $setup)) {
        Show-Message "Installer is no longer available:`n$setup`nWas the USB drive removed?" 'Error'
        return
    }

    Enter-Busy "Starting installer...`n$($choice.Folder)"
    try {
        $label = "Installing from '{0}'... (running silently, please wait)" -f (Split-Path -Leaf $choice.Folder)
        # Normal window style: if an installer ignores the switches and shows UI, the user can see it.
        $code = Invoke-WithProgress $setup $swArgs $choice.Folder 'Normal' $label
        Exit-Busy
        switch ($code) {
            0       { Show-Message "Installation completed successfully." 'Information' }
            { $_ -in 1641, 3010 } { Show-Message "Installation completed. A reboot is required to finish." 'Information' }
            default { Show-Message "The installer exited with code $code.`nIf nothing was installed, the silent switches ('$swArgs') may not suit this installer." 'Warning' }
        }
    } catch {
        Exit-Busy
        Show-Message "Could not run the installer:`n$($_.Exception.Message)" 'Error'
    }
})

[void]$form.ShowDialog()
