function Get-UsbDriveRoots {
    $roots = @()
    try {
        $roots = @(Get-Disk -ErrorAction Stop | Where-Object { $_.BusType -eq 'USB' } |
            Get-Partition -ErrorAction SilentlyContinue |
            Where-Object { $_.DriveLetter -match '[A-Za-z]' } |
            ForEach-Object { '{0}:\' -f $_.DriveLetter })
    } catch { }
    if ($roots.Count -eq 0) {
        $roots = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=2' |
            ForEach-Object { '{0}\' -f $_.DeviceID })
    }
    return @($roots | Where-Object { Test-Path -LiteralPath $_ } | Sort-Object -Unique)
}

function Initialize-CanfieldCaptureTab {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.TabPage]$Tab,

        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.TabControl]$Tabs,

        [Parameter(Mandatory = $true)]
        [string]$SilentArgs,

        [Parameter(Mandatory = $true)]
        [scriptblock]$EnterBusy,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ExitBusy,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ShowMessage,

        [Parameter(Mandatory = $true)]
        [scriptblock]$SetStatus,

        [Parameter(Mandatory = $true)]
        [scriptblock]$InvokeWithProgress
    )

    $btnScan = New-Object System.Windows.Forms.Button
    $btnScan.Text     = 'Scan USB'
    $btnScan.Location = New-Object System.Drawing.Point(15, 12)
    $btnScan.Size     = New-Object System.Drawing.Size(90, 26)
    $Tab.Controls.Add($btnScan)

    $usbInfo = New-Object System.Windows.Forms.Label
    $usbInfo.Text     = 'Click Scan USB to look for Canfield Capture installers.'
    $usbInfo.Location = New-Object System.Drawing.Point(115, 18)
    $usbInfo.Size     = New-Object System.Drawing.Size(380, 18)
    $usbInfo.Anchor = 'Top,Left,Right'
    $Tab.Controls.Add($usbInfo)

    $list = New-Object System.Windows.Forms.ListBox
    $list.Location      = New-Object System.Drawing.Point(15, 48)
    $list.Size          = New-Object System.Drawing.Size(480, 195)
    $list.HorizontalScrollbar = $true
    $list.DisplayMember = 'Display'
    $list.Anchor = 'Top,Bottom,Left,Right'
    $Tab.Controls.Add($list)

    $argLabel = New-Object System.Windows.Forms.Label
    $argLabel.Text     = 'Silent install switches (leave as-is if unsure):'
    $argLabel.Location = New-Object System.Drawing.Point(15, 255)
    $argLabel.AutoSize = $true
    $argLabel.Anchor = 'Bottom,Left'
    $Tab.Controls.Add($argLabel)

    $argBox = New-Object System.Windows.Forms.TextBox
    $argBox.Text     = $SilentArgs
    $argBox.Location = New-Object System.Drawing.Point(15, 277)
    $argBox.Size     = New-Object System.Drawing.Size(480, 22)
    $argBox.Anchor = 'Bottom,Left,Right'
    $Tab.Controls.Add($argBox)

    $btnUsb = New-Object System.Windows.Forms.Button
    $btnUsb.Text     = 'Install Selected'
    $btnUsb.Location = New-Object System.Drawing.Point(375, 305)
    $btnUsb.Size     = New-Object System.Drawing.Size(120, 30)
    $btnUsb.Enabled  = $false
    $btnUsb.Anchor = 'Bottom,Right'
    $Tab.Controls.Add($btnUsb)

    $script:usbScanned = $false
    $script:cancelRequested = $false

    function Invoke-UsbScan {
        $script:usbScanned = $true
        $list.Items.Clear()
        $btnUsb.Enabled = $false

        & $EnterBusy "Looking for USB drives..." $true
        $roots = Get-UsbDriveRoots
        if ($roots.Count -eq 0) {
            & $ExitBusy
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
            if ($scanned % 25 -eq 0) { & $SetStatus ("Searching USB drive for Canfield Capture installers...`n{0}" -f $dir) }
            else { [System.Windows.Forms.Application]::DoEvents() }
            try {
                if ([System.IO.File]::Exists((Join-Path $dir 'setup.exe'))) { $found.Add($dir) }
                foreach ($sub in [System.IO.Directory]::EnumerateDirectories($dir)) {
                    if ($skipNames -contains (Split-Path -Leaf $sub)) { continue }
                    if ([System.IO.File]::GetAttributes($sub) -band [System.IO.FileAttributes]::ReparsePoint) { continue }
                    $stack.Push($sub)
                }
            } catch { }
        }
        $cancelled = $script:cancelRequested
        & $ExitBusy

        if ($cancelled) { $usbInfo.Text = 'Scan cancelled.'; return }
        if ($found.Count -eq 0) { $usbInfo.Text = 'No Canfield Capture installers found on the USB drive.'; return }

        foreach ($f in ($found | Sort-Object)) {
            $name = Split-Path -Leaf $f
            if (-not $name) { $name = $f }
            $display = '{0}    ({1})' -f $name, $f
            [void]$list.Items.Add([pscustomobject]@{ Display = $display; Folder = $f })
        }
        $usbInfo.Text = 'Found Canfield Capture installers in {0} folder(s). Select one:' -f $found.Count
    }

    $btnScan.Add_Click({ Invoke-UsbScan })
    $list.Add_SelectedIndexChanged({ $btnUsb.Enabled = ($null -ne $list.SelectedItem) })
    $Tabs.Add_SelectedIndexChanged({
        if ($Tabs.SelectedTab -eq $Tab -and -not $script:usbScanned) { Invoke-UsbScan }
    })

    $btnUsb.Add_Click({
        $choice = $list.SelectedItem
        if ($null -eq $choice) { return }
        $setup  = Join-Path $choice.Folder 'setup.exe'
        $swArgs = $argBox.Text.Trim()

        if (-not (Test-Path -LiteralPath $setup)) {
            & $ShowMessage "Canfield Capture installer is no longer available:`n$setup`nWas the USB drive removed?" 'Error'
            return
        }

        & $EnterBusy "Starting installer...`n$($choice.Folder)"
        try {
            $label = "Installing from '{0}'... (running silently, please wait)" -f (Split-Path -Leaf $choice.Folder)
            $code = & $InvokeWithProgress $setup $swArgs $choice.Folder 'Normal' $label
            & $ExitBusy
            switch ($code) {
                0       { & $ShowMessage 'Installation completed successfully.' 'Information' }
                { $_ -in 1641, 3010 } { & $ShowMessage 'Installation completed. A reboot is required to finish.' 'Information' }
                default { & $ShowMessage "The installer exited with code $code.`nIf nothing was installed, the silent switches ('$swArgs') may not suit this installer." 'Warning' }
            }
        } catch {
            & $ExitBusy
            & $ShowMessage "Could not run the installer:`n$($_.Exception.Message)" 'Error'
        }
    })
}
