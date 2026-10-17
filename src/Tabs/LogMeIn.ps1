# Tab: LogMeIn

$tabLmi = New-Object System.Windows.Forms.TabPage; $tabLmi.Text = 'LogMeIn'
[void]$tabs.TabPages.Add($tabLmi)

$sponsors = @(Get-Sponsors $CsvPath $EmbeddedCsv)

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
