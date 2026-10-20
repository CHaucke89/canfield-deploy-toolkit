# Tab: Scripts (Canfield helper scripts installed as scheduled tasks)

$tabScripts = New-Object System.Windows.Forms.TabPage; $tabScripts.Text = 'Scripts'
[void]$tabs.TabPages.Add($tabScripts)

$grpScripts = New-Group $tabScripts 'Canfield scripts' 8 150

$scriptRows = foreach ($i in 0..($script:CanfieldScripts.Count - 1)) {
    $def = $script:CanfieldScripts[$i]
    $y = 24 + $i * 34
    $name = New-Object System.Windows.Forms.Label
    $name.Text     = $def.Name
    $name.Location = New-Object System.Drawing.Point(12, ($y + 6))
    $name.Size     = New-Object System.Drawing.Size(170, 18)
    $grpScripts.Controls.Add($name)

    $state = New-Object System.Windows.Forms.Label
    $state.Location = New-Object System.Drawing.Point(185, ($y + 6))
    $state.Size     = New-Object System.Drawing.Size(110, 18)
    $grpScripts.Controls.Add($state)

    $buttons = foreach ($b in @(@('Install', 310), @('Turn On', 400), @('Turn Off', 490))) {
        $btn = New-Object System.Windows.Forms.Button
        $btn.Text     = $b[0]
        $btn.Location = New-Object System.Drawing.Point($b[1], $y)
        $btn.Size     = New-Object System.Drawing.Size(88, 28)
        $btn.Tag      = $def
        $grpScripts.Controls.Add($btn)
        $btn
    }
    [pscustomobject]@{ Def = $def; State = $state; Install = $buttons[0]; On = $buttons[1]; Off = $buttons[2] }
}

$scriptsNote = New-Object System.Windows.Forms.Label
$scriptsNote.Text      = 'Script files not found. Put the Scripts folder next to CDT.exe to install them.'
$scriptsNote.ForeColor = [System.Drawing.Color]::Firebrick
$scriptsNote.Location  = New-Object System.Drawing.Point(12, 128)
$scriptsNote.Size      = New-Object System.Drawing.Size(566, 18)
$grpScripts.Controls.Add($scriptsNote)

foreach ($row in $scriptRows) {
    $row.Install.Add_Click({
        $def = $this.Tag
        $bat = Find-ScriptsFile $def.Installer
        if (-not $bat) { return }
        Enter-Busy "Installing $($def.Name)..."
        try {
            [void](Invoke-WithProgress $bat $null (Split-Path -Parent $bat) 'Normal' "Installing $($def.Name)...")
            Exit-Busy
        } catch {
            Exit-Busy
            Show-Message "Could not install $($def.Name):`n$($_.Exception.Message)" 'Error'
        }
        Update-ScriptsTab
    })
    $row.On.Add_Click({
        try { Set-CanfieldTaskEnabled $this.Tag.Task $true }
        catch { Show-Message "Could not turn on $($this.Tag.Name):`n$($_.Exception.Message)" 'Error' }
        Update-ScriptsTab
    })
    $row.Off.Add_Click({
        try { Set-CanfieldTaskEnabled $this.Tag.Task $false }
        catch { Show-Message "Could not turn off $($this.Tag.Name):`n$($_.Exception.Message)" 'Error' }
        Update-ScriptsTab
    })
}

function Update-ScriptsTab {
    $missing = $false
    foreach ($row in $scriptRows) {
        $state = Get-CanfieldTaskState $row.Def.Task
        $hasBat = [bool](Find-ScriptsFile $row.Def.Installer)
        if ($state -eq 'Not installed' -and -not $hasBat) { $missing = $true }
        Set-StatusLabel $row.State $state ($state -eq 'On')
        $row.Install.Enabled = ($state -eq 'Not installed') -and $hasBat
        $row.On.Enabled      = ($state -eq 'Off')
        $row.Off.Enabled     = ($state -eq 'On')
    }
    $scriptsNote.Visible = $missing
}

$tabs.Add_SelectedIndexChanged({
    if ($tabs.SelectedTab -eq $tabScripts) { Update-ScriptsTab }
})
