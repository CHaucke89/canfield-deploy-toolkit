# Tab: Cleanup Tool

$tabClean = New-Object System.Windows.Forms.TabPage; $tabClean.Text = 'Cleanup Tool'
[void]$tabs.TabPages.Add($tabClean)

$cleanDirtyLabel = New-Object System.Windows.Forms.Label
$cleanDirtyLabel.Text     = 'Needs cleanup:'
$cleanDirtyLabel.Location = New-Object System.Drawing.Point(15, 15)
$cleanDirtyLabel.AutoSize = $true
$tabClean.Controls.Add($cleanDirtyLabel)

$dirtyList = New-Object System.Windows.Forms.ListBox
$dirtyList.Location      = New-Object System.Drawing.Point(15, 38)
$dirtyList.Size          = New-Object System.Drawing.Size(235, 190)
$dirtyList.SelectionMode = 'MultiExtended'
$dirtyList.DisplayMember = 'Display'
$tabClean.Controls.Add($dirtyList)

$cleanCleanLabel = New-Object System.Windows.Forms.Label
$cleanCleanLabel.Text     = 'Already clean:'
$cleanCleanLabel.Location = New-Object System.Drawing.Point(260, 15)
$cleanCleanLabel.AutoSize = $true
$tabClean.Controls.Add($cleanCleanLabel)

$cleanList = New-Object System.Windows.Forms.ListBox
$cleanList.Location      = New-Object System.Drawing.Point(260, 38)
$cleanList.Size          = New-Object System.Drawing.Size(235, 190)
$cleanList.DisplayMember = 'Display'
$cleanList.SelectionMode = 'None'
$tabClean.Controls.Add($cleanList)

$cleanNote = New-Object System.Windows.Forms.Label
$cleanNote.Text     = "Deletes the selected versions' site data (Registered_Users.sdf is kept), opens each version so the Site ID can be set, then forces SSCT group members to change their password at next logon."
$cleanNote.Location = New-Object System.Drawing.Point(15, 238)
$cleanNote.Size     = New-Object System.Drawing.Size(480, 48)
$tabClean.Controls.Add($cleanNote)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text     = 'Refresh'
$btnRefresh.Location = New-Object System.Drawing.Point(15, 300)
$btnRefresh.Size     = New-Object System.Drawing.Size(90, 30)
$tabClean.Controls.Add($btnRefresh)

$btnClean = New-Object System.Windows.Forms.Button
$btnClean.Text     = 'Clean Selected'
$btnClean.Location = New-Object System.Drawing.Point(375, 300)
$btnClean.Size     = New-Object System.Drawing.Size(120, 30)
$btnClean.Enabled  = $false
$tabClean.Controls.Add($btnClean)

function Update-CleanupLists {
    $dirtyList.Items.Clear()
    $cleanList.Items.Clear()
    foreach ($v in (Get-CaptureVersions)) {
        if ($v.Dirty) { [void]$dirtyList.Items.Add($v) } else { [void]$cleanList.Items.Add($v) }
    }
    # Preselect everything that needs cleaning.
    for ($i = 0; $i -lt $dirtyList.Items.Count; $i++) { $dirtyList.SetSelected($i, $true) }
    $btnClean.Enabled = ($dirtyList.SelectedItems.Count -gt 0)
}

$btnRefresh.Add_Click({ Update-CleanupLists })
$dirtyList.Add_SelectedIndexChanged({ $btnClean.Enabled = ($dirtyList.SelectedItems.Count -gt 0) })
$tabs.Add_SelectedIndexChanged({
    if ($tabs.SelectedTab -eq $tabClean) { Update-CleanupLists }
})

$btnClean.Add_Click({
    $selected = @($dirtyList.SelectedItems)
    if ($selected.Count -eq 0) { return }

    $names = ($selected | ForEach-Object { $_.Display }) -join "`n"
    $confirm = [System.Windows.Forms.MessageBox]::Show($form,
        "Clean the database for:`n$names`n`nThis deletes site data and cannot be undone.",
        $appTitle, 'YesNo', 'Warning')
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    try {
        foreach ($v in $selected) {
            Enter-Busy "Cleaning $($v.Display)..."
            Clear-CaptureDatabase $v.Name
            Rename-CaptureLogFiles $v.Name
            Exit-Busy

            $exe = Join-Path $script:CaptureProgramRoot "$($v.Name)\Canfield Capture.exe"
            if (-not (Test-Path -LiteralPath $exe)) {
                Show-Message "Cleaned $($v.Display), but Canfield Capture was not found at:`n$exe`nSet the Site ID manually." 'Warning'
                continue
            }
            Show-Message "Site ID MUST be set. Click OK to open $($v.Display)." 'Warning'
            Enter-Busy "Waiting for $($v.Display) to close..."
            [void](Invoke-WithProgress $exe $null (Split-Path -Parent $exe) 'Normal' "Waiting for $($v.Display) to close...")
            Exit-Busy
        }

        try {
            Set-SsctPasswordExpired
            Show-Message 'Cleanup complete. SSCT group members must change their password at next logon.' 'Information'
        } catch {
            Show-Message "Databases cleaned, but SSCT passwords were NOT expired:`n$($_.Exception.Message)" 'Warning'
        }
    } catch {
        Exit-Busy
        Show-Message "Cleanup failed:`n$($_.Exception.Message)" 'Error'
    }
    Update-CleanupLists
})
