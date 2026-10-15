function Initialize-LogMeInTab {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.TabPage]$Tab,

        [Parameter(Mandatory = $true)]
        [string]$CsvPath,

        [AllowNull()]
        [string]$EmbeddedCsv,

        [Parameter(Mandatory = $true)]
        [scriptblock]$EnterBusy,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ExitBusy,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ShowMessage,

        [Parameter(Mandatory = $true)]
        [scriptblock]$InvokeWithProgress
    )

    $rows = $null
    if (Test-Path -LiteralPath $CsvPath)  { $rows = Import-Csv -LiteralPath $CsvPath }
    elseif ($EmbeddedCsv)                 { $rows = $EmbeddedCsv | ConvertFrom-Csv }

    $sponsors = @($rows | Where-Object { $_.Sponsor -and $_.DeployID } | ForEach-Object {
        [pscustomobject]@{ Sponsor = $_.Sponsor.Trim(); DeployID = $_.DeployID.Trim() }
    } | Sort-Object Sponsor)

    $lmiLabel = New-Object System.Windows.Forms.Label
    $lmiLabel.Text     = 'Select the sponsor for this machine:'
    $lmiLabel.Location = New-Object System.Drawing.Point(15, 20)
    $lmiLabel.AutoSize = $true
    $Tab.Controls.Add($lmiLabel)

    $combo = New-Object System.Windows.Forms.ComboBox
    $combo.DropDownStyle = 'DropDownList'
    $combo.Location      = New-Object System.Drawing.Point(15, 45)
    $combo.Size          = New-Object System.Drawing.Size(480, 24)
    $combo.DisplayMember = 'Sponsor'
    foreach ($s in $sponsors) { [void]$combo.Items.Add($s) }
    $combo.Anchor = 'Top,Left,Right'
    $Tab.Controls.Add($combo)

    $btnLmi = New-Object System.Windows.Forms.Button
    $btnLmi.Text     = 'Install LogMeIn'
    $btnLmi.Location = New-Object System.Drawing.Point(375, 90)
    $btnLmi.Size     = New-Object System.Drawing.Size(120, 30)
    $btnLmi.Enabled  = $false
    $btnLmi.Anchor = 'Top,Right'
    $Tab.Controls.Add($btnLmi)

    if ($sponsors.Count -eq 0) {
        $combo.Enabled = $false
        $lmiNote = New-Object System.Windows.Forms.Label
        $lmiNote.Text      = "No sponsors available. CSV not found or empty:`n$CsvPath"
        $lmiNote.ForeColor = [System.Drawing.Color]::Firebrick
        $lmiNote.Location  = New-Object System.Drawing.Point(15, 135)
        $lmiNote.Size      = New-Object System.Drawing.Size(480, 40)
        $lmiNote.Anchor = 'Top,Left,Right'
        $Tab.Controls.Add($lmiNote)
    }

    $combo.Add_SelectedIndexChanged({ $btnLmi.Enabled = ($null -ne $combo.SelectedItem) })

    $btnLmi.Add_Click({
        $choice = $combo.SelectedItem
        if ($null -eq $choice) { return }

        $msi = Join-Path $env:TEMP 'LogMeIn.msi'
        & $EnterBusy "Downloading latest LogMeIn installer..."
        try {
            $curlArgs = '-sS --fail -L https://secure.logmein.com/logmein.msi -o "{0}"' -f $msi
            $code = & $InvokeWithProgress 'curl.exe' $curlArgs $null 'Hidden' 'Downloading latest LogMeIn installer...'
            if ($code -ne 0) {
                & $ExitBusy
                & $ShowMessage "Download failed (curl exit code $code). Check the network connection and try again." 'Error'
                return
            }

            $msiArgs = '/i "{0}" /quiet DEPLOYID={1} INSTALLMETHOD=5 FQDNDESC=1' -f $msi, $choice.DeployID
            $code = & $InvokeWithProgress 'msiexec.exe' $msiArgs $null 'Hidden' "Installing LogMeIn for $($choice.Sponsor)..."
            & $ExitBusy
            switch ($code) {
                0       { & $ShowMessage "All done! LogMeIn installed for $($choice.Sponsor)." 'Information' }
                { $_ -in 1641, 3010 } { & $ShowMessage "LogMeIn installed for $($choice.Sponsor). A reboot is required to finish." 'Information' }
                default { & $ShowMessage "Installation failed (msiexec exit code $code)." 'Error' }
            }
        } catch {
            & $ExitBusy
            & $ShowMessage "Unexpected error:`n$($_.Exception.Message)" 'Error'
        } finally {
            Remove-Item -LiteralPath $msi -Force -ErrorAction SilentlyContinue
        }
    })
}
