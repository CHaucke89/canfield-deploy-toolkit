# Tab: Canfield Capture

$tabUsb = New-Object System.Windows.Forms.TabPage; $tabUsb.Text = 'Canfield Capture'
[void]$tabs.TabPages.Add($tabUsb)

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
        $label = "Installing from '{0}' silently, please wait." -f (Split-Path -Leaf $choice.Folder)
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
