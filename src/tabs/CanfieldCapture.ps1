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
$usbInfo.Size     = New-Object System.Drawing.Size(480, 18)
$tabUsb.Controls.Add($usbInfo)

$list = New-Object System.Windows.Forms.ListBox
$list.Location      = New-Object System.Drawing.Point(15, 48)
$list.Size          = New-Object System.Drawing.Size(580, 330)
$list.HorizontalScrollbar = $true
$list.DisplayMember = 'Display'
$tabUsb.Controls.Add($list)

$btnRcg = New-Object System.Windows.Forms.Button
$btnRcg.Text     = 'Open Response Code Generator'
$btnRcg.Location = New-Object System.Drawing.Point(15, 390)
$btnRcg.Size     = New-Object System.Drawing.Size(200, 30)
$btnRcg.Enabled  = $false
$tabUsb.Controls.Add($btnRcg)

$btnUsb = New-Object System.Windows.Forms.Button
$btnUsb.Text     = 'Install Selected'
$btnUsb.Location = New-Object System.Drawing.Point(475, 390)
$btnUsb.Size     = New-Object System.Drawing.Size(120, 30)
$btnUsb.Enabled  = $false
$tabUsb.Controls.Add($btnUsb)

$script:usbScanned = $false
$script:responseCodeGenerator = $null   # ResponseCodeGenerator.exe found by the last scan

function Invoke-UsbScan {
    $script:usbScanned = $true
    $list.Items.Clear()
    $btnUsb.Enabled = $false
    $btnRcg.Enabled = $false
    $script:responseCodeGenerator = $null

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
            $rcg = Join-Path $dir 'ResponseCodeGenerator.exe'
            if (-not $script:responseCodeGenerator -and [System.IO.File]::Exists($rcg)) { $script:responseCodeGenerator = $rcg }
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

    $btnRcg.Enabled = [bool]$script:responseCodeGenerator
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

    if (-not (Test-Path -LiteralPath $setup)) {
        Show-Message "Installer is no longer available:`n$setup`nWas the USB drive removed?" 'Error'
        return
    }
    $installed = @(Get-CaptureInstalls)
    if ($installed.Count -gt 0) {
        $names = ($installed | ForEach-Object { $_.Display }) -join ', '
        $again = [System.Windows.Forms.MessageBox]::Show($form,
            "Canfield Capture is already installed ($names).`nInstall '$(Split-Path -Leaf $choice.Folder)' as well?",
            $appTitle, 'YesNo', 'Question')
        if ($again -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    }

    Enter-Busy "Starting installer...`n$($choice.Folder)"
    try {
        $label = "Installing from '{0}' silently, please wait." -f (Split-Path -Leaf $choice.Folder)
        # Normal window style: if an installer ignores the switches and shows UI, the user can see it.
        $code = Invoke-WithProgress $setup $SilentArgs $choice.Folder 'Normal' $label
        Exit-Busy
        switch ($code) {
            0       { Show-Message "Installation completed successfully." 'Information' }
            { $_ -in 1641, 3010 } { Show-Message "Installation completed. A reboot is required to finish." 'Information' }
            default { Show-Message "The installer exited with code $code.`nIf nothing was installed, run setup.exe from the USB drive manually." 'Warning' }
        }
    } catch {
        Exit-Busy
        Show-Message "Could not run the installer:`n$($_.Exception.Message)" 'Error'
    }
})

$btnRcg.Add_Click({
    $exe = $script:responseCodeGenerator
    if (-not $exe -or -not (Test-Path -LiteralPath $exe)) {
        $btnRcg.Enabled = $false
        Show-Message "ResponseCodeGenerator.exe was not found on the USB drive.`nInsert the drive and click Scan USB." 'Warning'
        return
    }
    try { Start-Process -FilePath $exe -WorkingDirectory (Split-Path -Parent $exe) }
    catch { Show-Message "Could not open the Response Code Generator:`n$($_.Exception.Message)" 'Error' }
})
