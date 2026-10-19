# Tab: Computer Name

$tabName = New-Object System.Windows.Forms.TabPage; $tabName.Text = 'Computer Name'
[void]$tabs.TabPages.Add($tabName)

$nameCurrent = New-Object System.Windows.Forms.Label
$nameCurrent.Text     = "Current computer name: $env:COMPUTERNAME"
$nameCurrent.Location = New-Object System.Drawing.Point(15, 20)
$nameCurrent.AutoSize = $true
$tabName.Controls.Add($nameCurrent)

$nameLabel = New-Object System.Windows.Forms.Label
$nameLabel.Text     = 'New computer name (max 15 letters, digits or hyphens):'
$nameLabel.Location = New-Object System.Drawing.Point(15, 55)
$nameLabel.AutoSize = $true
$tabName.Controls.Add($nameLabel)

$nameBox = New-Object System.Windows.Forms.TextBox
$nameBox.MaxLength = 15
$nameBox.Location  = New-Object System.Drawing.Point(15, 80)
$nameBox.Size      = New-Object System.Drawing.Size(480, 22)
$tabName.Controls.Add($nameBox)

$btnName = New-Object System.Windows.Forms.Button
$btnName.Text     = 'Rename Computer'
$btnName.Location = New-Object System.Drawing.Point(375, 120)
$btnName.Size     = New-Object System.Drawing.Size(120, 30)
$btnName.Enabled  = $false
$tabName.Controls.Add($btnName)

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
