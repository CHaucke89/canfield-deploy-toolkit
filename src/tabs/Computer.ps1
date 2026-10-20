# Tab: Computer (computer name, Site Photographer password, date/time, Windows Update)

$tabComputer = New-Object System.Windows.Forms.TabPage; $tabComputer.Text = 'Computer'
[void]$tabs.TabPages.Add($tabComputer)

# --- Computer name ---
$grpName = New-Group $tabComputer 'Computer name' 8 95

$nameCurrent = New-Object System.Windows.Forms.Label
$nameCurrent.Text     = "Current computer name: $env:COMPUTERNAME"
$nameCurrent.Location = New-Object System.Drawing.Point(12, 22)
$nameCurrent.Size     = New-Object System.Drawing.Size(566, 18)
$grpName.Controls.Add($nameCurrent)

$nameBox = New-Object System.Windows.Forms.TextBox
$nameBox.MaxLength = 15
$nameBox.Location  = New-Object System.Drawing.Point(12, 52)
$nameBox.Size      = New-Object System.Drawing.Size(440, 22)
$grpName.Controls.Add($nameBox)

$btnName = New-Object System.Windows.Forms.Button
$btnName.Text     = 'Rename Computer'
$btnName.Location = New-Object System.Drawing.Point(460, 49)
$btnName.Size     = New-Object System.Drawing.Size(118, 28)
$btnName.Enabled  = $false
$grpName.Controls.Add($btnName)

$nameHint = New-Object System.Windows.Forms.Label
$nameHint.Text     = 'Max 15 letters, digits or hyphens.'
$nameHint.Location = New-Object System.Drawing.Point(12, 76)
$nameHint.AutoSize = $true
$grpName.Controls.Add($nameHint)

$nameBox.Add_TextChanged({
    $btnName.Enabled = ($nameBox.Text.Trim().Length -gt 0 -and $nameBox.Text.Trim() -ne $env:COMPUTERNAME)
})

$btnName.Add_Click({
    $newName = $nameBox.Text.Trim()
    if (-not (Test-ComputerName $newName)) {
        Show-Message "'$newName' is not a valid computer name.`nUse 1-15 letters, digits or hyphens; no leading/trailing hyphen, and not only digits." 'Warning'
        return
    }
    $confirm = [System.Windows.Forms.MessageBox]::Show($form,
        "Rename this computer from '$env:COMPUTERNAME' to '$newName'?`nA restart is required for the change to take effect.",
        $appTitle, 'YesNo', 'Question')
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    try {
        Rename-Computer -NewName $newName -Force -ErrorAction Stop
    } catch {
        Show-Message "Could not rename the computer:`n$($_.Exception.Message)" 'Error'
        return
    }

    $nameCurrent.Text = "Current computer name: $env:COMPUTERNAME (will be '$newName' after restart)"
    $nameBox.Clear()
    $restart = [System.Windows.Forms.MessageBox]::Show($form,
        "Computer renamed to '$newName'.`nRestart now to finish?",
        $appTitle, 'YesNo', 'Question')
    if ($restart -eq [System.Windows.Forms.DialogResult]::Yes) {
        try { Restart-Computer -Force -ErrorAction Stop }
        catch { Show-Message "Could not restart the computer:`n$($_.Exception.Message)" 'Error' }
    }
})

# --- Site Photographer password ---
$grpPhoto = New-Group $tabComputer "Site Photographer password" 110 95

$photoLabel = New-Object System.Windows.Forms.Label
$photoLabel.Text     = "New password for the 'Site Photographer' account:"
$photoLabel.Location = New-Object System.Drawing.Point(12, 22)
$photoLabel.AutoSize = $true
$grpPhoto.Controls.Add($photoLabel)

$photoBox = New-Object System.Windows.Forms.TextBox
$photoBox.Location = New-Object System.Drawing.Point(12, 46)
$photoBox.Size     = New-Object System.Drawing.Size(440, 22)
$grpPhoto.Controls.Add($photoBox)

$btnPhoto = New-Object System.Windows.Forms.Button
$btnPhoto.Text     = 'Set Password'
$btnPhoto.Location = New-Object System.Drawing.Point(460, 43)
$btnPhoto.Size     = New-Object System.Drawing.Size(118, 28)
$btnPhoto.Enabled  = $false
$grpPhoto.Controls.Add($btnPhoto)

$photoNote = New-Object System.Windows.Forms.Label
$photoNote.Text     = 'Symbols, spaces and numbers are removed and the password is converted to lower case.'
$photoNote.Location = New-Object System.Drawing.Point(12, 72)
$photoNote.AutoSize = $true
$grpPhoto.Controls.Add($photoNote)

$photoBox.Add_TextChanged({ $btnPhoto.Enabled = ($photoBox.Text.Trim().Length -gt 0) })

$btnPhoto.Add_Click({
    $pass = ConvertTo-PhotographerPassword $photoBox.Text
    $photoBox.Text = $pass
    if (-not $pass) {
        Show-Message 'The password must contain at least one letter.' 'Warning'
        return
    }
    try {
        $secure = ConvertTo-SecureString $pass -AsPlainText -Force
        Set-LocalUser -Name 'Site Photographer' -Password $secure -PasswordNeverExpires $true `
            -UserMayChangePassword $false -ErrorAction Stop
        Show-Message "Site Photographer password updated to '$pass'." 'Information'
    } catch {
        Show-Message "Site Photographer password NOT updated:`n$($_.Exception.Message)" 'Error'
    }
})

# --- Date, time and time zone ---
$grpTime = New-Group $tabComputer 'Date, time and time zone' 212 75

$timeInfo = New-Object System.Windows.Forms.Label
$timeInfo.Location = New-Object System.Drawing.Point(12, 22)
$timeInfo.Size     = New-Object System.Drawing.Size(440, 40)
$grpTime.Controls.Add($timeInfo)

$btnTime = New-Object System.Windows.Forms.Button
$btnTime.Text     = 'Open Settings'
$btnTime.Location = New-Object System.Drawing.Point(460, 26)
$btnTime.Size     = New-Object System.Drawing.Size(118, 28)
$grpTime.Controls.Add($btnTime)

function Update-TimeInfo {
    $timeInfo.Text = "Time zone: $((Get-TimeZone).DisplayName)`nDate and time: $(Get-Date -Format 'dd MMM yyyy HH:mm')"
}
Update-TimeInfo

$btnTime.Add_Click({
    Enter-Busy 'Waiting for Date and Time settings to close...'
    try {
        [void](Invoke-WithProgress 'rundll32.exe' 'shell32.dll,Control_RunDLL timedate.cpl' $null 'Normal' 'Waiting for Date and Time settings to close...')
    } catch {
        Show-Message "Could not open Date and Time settings:`n$($_.Exception.Message)" 'Error'
    }
    Exit-Busy
    Update-TimeInfo
})

# --- Windows Update ---
$grpUpdate = New-Group $tabComputer 'Windows Update' 294 65

$updateInfo = New-Object System.Windows.Forms.Label
$updateInfo.Text     = 'Opens Windows Update in Settings so you can install updates.'
$updateInfo.Location = New-Object System.Drawing.Point(12, 28)
$updateInfo.AutoSize = $true
$grpUpdate.Controls.Add($updateInfo)

$btnUpdate = New-Object System.Windows.Forms.Button
$btnUpdate.Text     = 'Open Settings'
$btnUpdate.Location = New-Object System.Drawing.Point(460, 22)
$btnUpdate.Size     = New-Object System.Drawing.Size(118, 28)
$grpUpdate.Controls.Add($btnUpdate)

$btnUpdate.Add_Click({
    try { Start-Process 'ms-settings:windowsupdate' }
    catch { Show-Message "Could not open Windows Update:`n$($_.Exception.Message)" 'Error' }
})

$tabs.Add_SelectedIndexChanged({
    if ($tabs.SelectedTab -eq $tabComputer) { Update-TimeInfo }
})
