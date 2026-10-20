# Tab: Summary (machine status, installed protocols, QC report)

$tabSummary = New-Object System.Windows.Forms.TabPage; $tabSummary.Text = 'Summary'
[void]$tabs.TabPages.Add($tabSummary)

function New-ListView([int]$Y, [int]$Height, [object[]]$Columns) {
    $lv = New-Object System.Windows.Forms.ListView
    $lv.View          = 'Details'
    $lv.FullRowSelect = $true
    $lv.HeaderStyle   = 'Nonclickable'
    $lv.Location      = New-Object System.Drawing.Point(10, $Y)
    $lv.Size          = New-Object System.Drawing.Size(590, $Height)
    foreach ($c in $Columns) { [void]$lv.Columns.Add($c[0], $c[1]) }
    $tabSummary.Controls.Add($lv)
    return $lv
}

$statusView   = New-ListView 8 190 @(@('Check', 150), @('Result', 415))
$protocolView = New-ListView 204 100 @(@('Protocol', 220), @('Version', 120), @('Site ID', 150), @('SSO', 75))

$initialsLabel = New-Object System.Windows.Forms.Label
$initialsLabel.Text     = 'Technician initials:'
$initialsLabel.Location = New-Object System.Drawing.Point(10, 315)
$initialsLabel.AutoSize = $true
$tabSummary.Controls.Add($initialsLabel)

$initialsBox = New-Object System.Windows.Forms.TextBox
$initialsBox.Location = New-Object System.Drawing.Point(125, 312)
$initialsBox.Size     = New-Object System.Drawing.Size(80, 22)
$tabSummary.Controls.Add($initialsBox)

$commentsLabel = New-Object System.Windows.Forms.Label
$commentsLabel.Text     = 'Comments:'
$commentsLabel.Location = New-Object System.Drawing.Point(10, 343)
$commentsLabel.AutoSize = $true
$tabSummary.Controls.Add($commentsLabel)

$commentsBox = New-Object System.Windows.Forms.TextBox
$commentsBox.Multiline  = $true
$commentsBox.ScrollBars = 'Vertical'
$commentsBox.Location   = New-Object System.Drawing.Point(125, 340)
$commentsBox.Size       = New-Object System.Drawing.Size(475, 40)
$tabSummary.Controls.Add($commentsBox)

$btnSummaryRefresh = New-Object System.Windows.Forms.Button
$btnSummaryRefresh.Text     = 'Refresh'
$btnSummaryRefresh.Location = New-Object System.Drawing.Point(10, 388)
$btnSummaryRefresh.Size     = New-Object System.Drawing.Size(90, 28)
$tabSummary.Controls.Add($btnSummaryRefresh)

$btnReport = New-Object System.Windows.Forms.Button
$btnReport.Text     = 'Save Report'
$btnReport.Location = New-Object System.Drawing.Point(480, 388)
$btnReport.Size     = New-Object System.Drawing.Size(120, 28)
$tabSummary.Controls.Add($btnReport)

function Update-Summary {
    Enter-Busy 'Checking this computer...'
    try {
        $info     = Get-MachineInfo
        $installs = @(Get-CaptureInstalls)
        $users    = @(try { Get-SiteUsers } catch { })
        $rows = [ordered]@{
            'Computer name'    = $env:COMPUTERNAME
            'Service tag'      = $info.ServiceTag
            'Model'            = $info.Model
            'Date and time'    = Get-Date -Format 'dd MMM yyyy HH:mm'
            'Time zone'        = (Get-TimeZone).DisplayName
            'Wi-Fi'            = Get-WifiStatus
            'BitLocker'        = Get-BitLockerSummary
            'LogMeIn'          = if (Test-LogMeInInstalled) { 'Installed' } else { 'Not installed' }
            'Resolve MDM'      = if (Test-ResolveMdmEnrolled) { 'Enrolled' } else { 'Not enrolled' }
            'Canfield Capture' = if ($installs.Count) { ($installs | ForEach-Object { $_.Display }) -join ', ' } else { 'Not installed' }
            'Site users'       = '{0} in the SSCT group' -f $users.Count
        }
        $statusView.Items.Clear()
        foreach ($k in $rows.Keys) {
            $item = New-Object System.Windows.Forms.ListViewItem($k)
            [void]$item.SubItems.Add([string]$rows[$k])
            [void]$statusView.Items.Add($item)
        }

        $protocolView.Items.Clear()
        foreach ($p in (Get-CaptureProtocols -WithSiteId)) {
            $item = New-Object System.Windows.Forms.ListViewItem($p.Protocol)
            [void]$item.SubItems.Add($p.Version)
            [void]$item.SubItems.Add($(if ($p.SiteID) { $p.SiteID } else { 'Not set' }))
            [void]$item.SubItems.Add($(if ($p.SSO) { 'Yes' } else { 'No' }))
            [void]$protocolView.Items.Add($item)
        }
    } finally {
        Exit-Busy
    }
}

# Text version of everything on this tab.
function Get-SummaryText {
    $lines = @("QC report - $env:COMPUTERNAME", '')
    foreach ($item in $statusView.Items) { $lines += '{0}: {1}' -f $item.Text, $item.SubItems[1].Text }
    $lines += '', 'Protocols:'
    if ($protocolView.Items.Count -eq 0) { $lines += '  None installed' }
    foreach ($item in $protocolView.Items) {
        $lines += '  {0} ({1}) - Site ID: {2}, SSO: {3}' -f $item.Text, $item.SubItems[1].Text, $item.SubItems[2].Text, $item.SubItems[3].Text
    }
    $lines += '', "Technician: $($initialsBox.Text.Trim())", "Comments: $($commentsBox.Text.Trim())"
    return ($lines -join "`r`n")
}

$btnSummaryRefresh.Add_Click({ Update-Summary })
$tabs.Add_SelectedIndexChanged({
    if ($tabs.SelectedTab -eq $tabSummary) { Update-Summary }
})

# Saves a JPG picture of the window and a .txt with the same name.
$btnReport.Add_Click({
    if (-not $initialsBox.Text.Trim()) {
        Show-Message 'Enter your initials before saving the report.' 'Warning'
        [void]$initialsBox.Focus()
        return
    }
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Filter   = 'JPEG image (*.jpg)|*.jpg'
    $dlg.FileName = 'QC_{0}_{1}' -f $env:COMPUTERNAME, (Get-Date -Format 'ddMMMyyyyHHmmss')
    $dlg.InitialDirectory = [Environment]::GetFolderPath('Desktop')
    if ($dlg.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) { return }

    try {
        $form.Refresh()
        $bmp = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
        $form.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
        $bmp.Save($dlg.FileName, [System.Drawing.Imaging.ImageFormat]::Jpeg)
        $bmp.Dispose()
        $txt = [System.IO.Path]::ChangeExtension($dlg.FileName, '.txt')
        Set-Content -LiteralPath $txt -Value (Get-SummaryText) -Encoding UTF8
        Show-Message "Report saved:`n$($dlg.FileName)`n$txt" 'Information'
    } catch {
        Show-Message "Report NOT saved:`n$($_.Exception.Message)" 'Error'
    }
})
