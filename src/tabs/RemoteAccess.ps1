# Tab: Remote Access (LogMeIn, Resolve MDM)

$tabRemote = New-Object System.Windows.Forms.TabPage; $tabRemote.Text = 'Remote Access'
[void]$tabs.TabPages.Add($tabRemote)

# --- LogMeIn ---
$grpLmi = New-Group $tabRemote 'LogMeIn' 8 115

$sponsors = @(Get-Sponsors $CsvPath $EmbeddedCsv)

$lmiStatus = New-Object System.Windows.Forms.Label
$lmiStatus.Location = New-Object System.Drawing.Point(12, 22)
$lmiStatus.AutoSize = $true
$grpLmi.Controls.Add($lmiStatus)

$lmiLabel = New-Object System.Windows.Forms.Label
$lmiLabel.Text     = 'Select the sponsor to install LogMeIn for:'
$lmiLabel.Location = New-Object System.Drawing.Point(12, 44)
$lmiLabel.AutoSize = $true
$grpLmi.Controls.Add($lmiLabel)

$combo = New-Object System.Windows.Forms.ComboBox
$combo.DropDownStyle = 'DropDownList'
$combo.Location      = New-Object System.Drawing.Point(12, 64)
$combo.Size          = New-Object System.Drawing.Size(440, 24)
$combo.DisplayMember = 'Sponsor'
foreach ($s in $sponsors) { [void]$combo.Items.Add($s) }
$grpLmi.Controls.Add($combo)

$btnLmi = New-Object System.Windows.Forms.Button
$btnLmi.Text     = 'Install LogMeIn'
$btnLmi.Location = New-Object System.Drawing.Point(460, 62)
$btnLmi.Size     = New-Object System.Drawing.Size(118, 28)
$btnLmi.Enabled  = $false
$grpLmi.Controls.Add($btnLmi)

if ($sponsors.Count -eq 0) {
    $combo.Enabled = $false
    $lmiNote = New-Object System.Windows.Forms.Label
    $lmiNote.Text      = "No sponsors available. CSV not found or empty: $CsvPath"
    $lmiNote.ForeColor = [System.Drawing.Color]::Firebrick
    $lmiNote.Location  = New-Object System.Drawing.Point(12, 92)
    $lmiNote.Size      = New-Object System.Drawing.Size(566, 18)
    $grpLmi.Controls.Add($lmiNote)
}

$combo.Add_SelectedIndexChanged({ $btnLmi.Enabled = ($null -ne $combo.SelectedItem) })

$btnLmi.Add_Click({
    $choice = $combo.SelectedItem
    if ($null -eq $choice) { return }
    if (Test-LogMeInInstalled) {
        $again = [System.Windows.Forms.MessageBox]::Show($form,
            "LogMeIn is already installed. Install it again for $($choice.Sponsor)?",
            $appTitle, 'YesNo', 'Question')
        if ($again -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    }

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
        Update-RemoteTab
    }
})

# --- Resolve MDM ---
$grpMdm = New-Group $tabRemote 'Resolve MDM' 130 65

$mdmStatus = New-Object System.Windows.Forms.Label
$mdmStatus.Location = New-Object System.Drawing.Point(12, 28)
$mdmStatus.Size     = New-Object System.Drawing.Size(440, 18)
$grpMdm.Controls.Add($mdmStatus)

$btnMdm = New-Object System.Windows.Forms.Button
$btnMdm.Text     = 'Enroll'
$btnMdm.Location = New-Object System.Drawing.Point(460, 22)
$btnMdm.Size     = New-Object System.Drawing.Size(118, 28)
$grpMdm.Controls.Add($btnMdm)

$btnMdm.Add_Click({
    $ppkg = Find-ScriptsFile $script:MdmPackage
    if (-not $ppkg) { return }
    Enter-Busy 'Enrolling in Resolve MDM...'
    try {
        Install-ProvisioningPackage -PackagePath $ppkg -QuietInstall -ErrorAction Stop | Out-Null
        Exit-Busy
        Show-Message 'Resolve MDM enrollment started. The status shows Enrolled once Windows finishes (this can take a minute; click the tab again to refresh).' 'Information'
    } catch {
        Exit-Busy
        Show-Message "Resolve MDM enrollment failed:`n$($_.Exception.Message)" 'Error'
    }
    Update-RemoteTab
})

function Update-RemoteTab {
    if (Test-LogMeInInstalled) { Set-StatusLabel $lmiStatus 'LogMeIn is installed.' $true }
    else                       { Set-StatusLabel $lmiStatus 'LogMeIn is not installed.' $false }

    $enrolled = Test-ResolveMdmEnrolled
    $ppkg = Find-ScriptsFile $script:MdmPackage
    if ($enrolled)  { Set-StatusLabel $mdmStatus 'Enrolled in Resolve MDM.' $true }
    elseif ($ppkg)  { Set-StatusLabel $mdmStatus 'Not enrolled.' $false }
    else            { Set-StatusLabel $mdmStatus 'Not enrolled. CanfieldScientific.ppkg not found in the Scripts folder.' $false }
    $btnMdm.Enabled = (-not $enrolled) -and [bool]$ppkg
}

$tabs.Add_SelectedIndexChanged({
    if ($tabs.SelectedTab -eq $tabRemote) { Update-RemoteTab }
})
