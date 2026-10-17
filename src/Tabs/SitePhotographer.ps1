# Tab: Site Photographer

$tabPhoto = New-Object System.Windows.Forms.TabPage; $tabPhoto.Text = 'Site Photographer'
[void]$tabs.TabPages.Add($tabPhoto)

$photoLabel = New-Object System.Windows.Forms.Label
$photoLabel.Text     = "New password for the local 'Site Photographer' account:"
$photoLabel.Location = New-Object System.Drawing.Point(15, 20)
$photoLabel.AutoSize = $true
$tabPhoto.Controls.Add($photoLabel)

$photoBox = New-Object System.Windows.Forms.TextBox
$photoBox.Location = New-Object System.Drawing.Point(15, 45)
$photoBox.Size     = New-Object System.Drawing.Size(480, 22)
$tabPhoto.Controls.Add($photoBox)

$photoNote = New-Object System.Windows.Forms.Label
$photoNote.Text     = 'Symbols, spaces and numbers are removed and the password is converted to lower case.'
$photoNote.Location = New-Object System.Drawing.Point(15, 72)
$photoNote.Size     = New-Object System.Drawing.Size(480, 18)
$tabPhoto.Controls.Add($photoNote)

$btnPhoto = New-Object System.Windows.Forms.Button
$btnPhoto.Text     = 'Set Password'
$btnPhoto.Location = New-Object System.Drawing.Point(375, 105)
$btnPhoto.Size     = New-Object System.Drawing.Size(120, 30)
$btnPhoto.Enabled  = $false
$tabPhoto.Controls.Add($btnPhoto)

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
