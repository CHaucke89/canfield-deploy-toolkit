function Get-ResolveMdmStatus {
    [CmdletBinding()]
    param()

    $result = [pscustomobject]@{
        Enrolled   = $false
        ProviderID = $null
        ServerUrl  = $null
        UPN        = $null
        Guid       = $null
        HivePath   = $null
    }

    $base = 'HKLM:\SOFTWARE\Microsoft\Enrollments'
    if (-not (Test-Path -LiteralPath $base)) { return $result }

    foreach ($sub in Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue) {
        try {
            $p = Get-ItemProperty -LiteralPath $sub.PSPath -ErrorAction Stop
        } catch {
            continue
        }

        $provider = $p.ProviderID
        $discUrl  = $p.DiscoveryServiceFullURL
        $upn      = $p.UPN

        $isResolve =
            ($provider -eq 'MiradoreMDM') -or
            ($discUrl -like 'https://gateway.miradore.com/*') -or
            ($upn -like '*@mdm.gotoresolve.com')

        if ($isResolve) {
            $result.Enrolled   = $true
            $result.ProviderID = $provider
            $result.ServerUrl  = $discUrl
            $result.UPN        = $upn
            $result.Guid       = (Split-Path -Leaf $sub.Name)
            $result.HivePath   = $sub.PSPath
            return $result
        }
    }

    return $result
}

function Get-ToolkitStatePath {
    [CmdletBinding()]
    param()

    $base = Join-Path $env:ProgramData 'CanfieldDeployToolkit'
    return (Join-Path $base 'state.json')
}

function Get-ToolkitState {
    [CmdletBinding()]
    param()

    $defaultState = [pscustomobject]@{
        ResolveMdm = [pscustomobject]@{
            EnrollConfirmed = $false
            LastConfirmedAt = $null
        }
    }

    $path = Get-ToolkitStatePath
    if (-not (Test-Path -LiteralPath $path)) {
        return $defaultState
    }

    try {
        $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $defaultState
        }

        $state = $raw | ConvertFrom-Json -ErrorAction Stop
        if (-not $state.ResolveMdm) {
            $state | Add-Member -MemberType NoteProperty -Name ResolveMdm -Value ([pscustomobject]@{
                EnrollConfirmed = $false
                LastConfirmedAt = $null
            }) -Force
        }
        if ($state.ResolveMdm.PSObject.Properties.Name -notcontains 'EnrollConfirmed') {
            $state.ResolveMdm | Add-Member -MemberType NoteProperty -Name EnrollConfirmed -Value $false -Force
        }
        if ($state.ResolveMdm.PSObject.Properties.Name -notcontains 'LastConfirmedAt') {
            $state.ResolveMdm | Add-Member -MemberType NoteProperty -Name LastConfirmedAt -Value $null -Force
        }
        return $state
    } catch {
        return $defaultState
    }
}

function Save-ToolkitState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$State
    )

    $path = Get-ToolkitStatePath
    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }

    $json = $State | ConvertTo-Json -Depth 5
    Set-Content -LiteralPath $path -Value $json -Encoding UTF8
}

function Get-BitLockerStatus {
    [CmdletBinding()]
    param()

    function Test-CommandExists([string]$Name) {
        return [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue)
    }

    function ConvertTo-ConversionStatus([string]$vs) {
        switch -Regex ($vs) {
            '^FullyEncrypted$'       { 'FullyEncrypted'; break }
            '^EncryptionInProgress$' { 'EncryptionInProgress'; break }
            '^DecryptionInProgress$' { 'DecryptionInProgress'; break }
            '^FullyDecrypted$'       { 'FullyDecrypted'; break }
            default                  { 'Unknown' }
        }
    }

    function ConvertTo-ProtectionStatus([string]$ps) {
        switch -Regex ($ps) {
            '^On$'   { 'On'; break }
            '^Off$'  { 'Off'; break }
            default  { 'Unknown' }
        }
    }

    function ConvertTo-LockStatus([string]$ls) {
        switch -Regex ($ls) {
            '^Locked$'   { 'Locked'; break }
            '^Unlocked$' { 'Unlocked'; break }
            default      { 'Unknown' }
        }
    }

    function ConvertTo-NormalizedDrive([string]$d) {
        if ([string]::IsNullOrWhiteSpace($d)) { return $null }
        $d = $d.Trim()
        if ($d.Length -ge 2 -and $d[1] -eq ':') { return $d.Substring(0, 2) }
        return $d
    }

    function ConvertTo-KeyProtectorTypeName([string]$s) {
        $t = ($s -as [string]).Trim()
        switch -Regex ($t) {
            '^Numerical Password$'             { 'RecoveryPassword'; break }
            '^Recovery Password$'              { 'RecoveryPassword'; break }
            '^TPM$'                            { 'Tpm'; break }
            '^TPM And PIN$'                    { 'TpmPin'; break }
            '^TPM And Startup Key$'            { 'TpmStartupKey'; break }
            '^TPM And PIN And Startup Key$'    { 'TpmPinAndStartupKey'; break }
            '^Password$'                       { 'Password'; break }
            '^(External Key|Startup Key)$'     { 'ExternalKey'; break }
            '^Public Key$'                     { 'PublicKey'; break }
            default                            { if ($t) { $t } else { $null } }
        }
    }

    $osDrive = try {
        ConvertTo-NormalizedDrive -d (Get-CimInstance Win32_OperatingSystem | Select-Object -ExpandProperty SystemDrive)
    } catch {
        $null
    }

    $result = [ordered]@{
        OsDrive               = $osDrive
        ProtectionStatus      = 'Unknown'
        ConversionStatus      = 'Unknown'
        EncryptionPercentage  = $null
        LockStatus            = 'Unknown'
        KeyProtectorTypes     = @()
        HasRecoveryKey        = $false
        TpmPresent            = $null
        TpmReady              = $null
        TpmOwned              = $null
        AdminRequired         = $false
        Source                = $null
    }

    try {
        if (Test-CommandExists 'Get-Tpm') {
            $tpm = Get-Tpm -ErrorAction SilentlyContinue
            if ($tpm) {
                $result.TpmPresent = [bool]$tpm.TpmPresent
                $result.TpmReady   = [bool]$tpm.TpmReady
                $result.TpmOwned   = [bool]$tpm.TpmOwned
            }
        }
    } catch {
    }

    if ($osDrive -and (Test-CommandExists 'Get-BitLockerVolume')) {
        try {
            $blv = Get-BitLockerVolume -MountPoint $osDrive -ErrorAction Stop
            if ($blv) {
                $result.Source = 'Get-BitLockerVolume'
                $result.ProtectionStatus = ConvertTo-ProtectionStatus $blv.ProtectionStatus
                $result.LockStatus       = ConvertTo-LockStatus $blv.LockStatus
                $result.ConversionStatus = ConvertTo-ConversionStatus $blv.VolumeStatus
                $hasEncryptionPercentage = $blv.PSObject.Properties.Name -contains 'EncryptionPercentage'
                $encryptionPctIsSet = -not [object]::ReferenceEquals($blv.EncryptionPercentage, $null)
                if ($hasEncryptionPercentage -and $encryptionPctIsSet) {
                    try {
                        $result.EncryptionPercentage = [int][math]::Round([double]$blv.EncryptionPercentage)
                    } catch {
                        $result.EncryptionPercentage = $null
                    }
                }

                $kp = @()
                if ($blv.KeyProtector) {
                    foreach ($k in $blv.KeyProtector) {
                        if ($k -and ($k.PSObject.Properties.Name -contains 'KeyProtectorType')) {
                            $kp += [string]$k.KeyProtectorType
                        }
                    }
                }
                $result.KeyProtectorTypes = @($kp | Where-Object { $_ -ne $null })
                $result.HasRecoveryKey = @($result.KeyProtectorTypes | Where-Object { $_ -match '^RecoveryPassword$' -or $_ -match '^Recovery Key$' }).Count -gt 0

                return [pscustomobject]$result
            }
        } catch {
            if ($_.Exception.Message -match 'Access.*denied') { $result.AdminRequired = $true }
        }
    }

    if ($osDrive) {
        try {
            $raw = & manage-bde -status $osDrive 2>&1
            $text = ($raw | Out-String)
            $lines = $text -split "`r?`n"

            $result.Source = 'manage-bde'

            $protLine = $lines | Where-Object { $_ -match '^\s*Protection Status:\s*(.+)$' } | Select-Object -First 1
            if ($protLine) {
                if ($protLine -match 'Protection\s+On') { $result.ProtectionStatus = 'On' }
                elseif ($protLine -match 'Protection\s+Off') { $result.ProtectionStatus = 'Off' }
            }

            $lockLine = $lines | Where-Object { $_ -match '^\s*Lock Status:\s*(.+)$' } | Select-Object -First 1
            if ($lockLine) {
                if ($lockLine -match 'Locked') { $result.LockStatus = 'Locked' }
                elseif ($lockLine -match 'Unlocked') { $result.LockStatus = 'Unlocked' }
            }

            $convLine = $lines | Where-Object { $_ -match '^\s*Conversion Status:\s*(.+)$' } | Select-Object -First 1
            if ($convLine) {
                if ($convLine -match 'Fully\s+Encrypted') { $result.ConversionStatus = 'FullyEncrypted' }
                elseif ($convLine -match 'Encryption\s+in\s+Progress') { $result.ConversionStatus = 'EncryptionInProgress' }
                elseif ($convLine -match 'Decryption\s+in\s+Progress') { $result.ConversionStatus = 'DecryptionInProgress' }
                elseif ($convLine -match 'Fully\s+Decrypted') { $result.ConversionStatus = 'FullyDecrypted' }
            }

            $pctLine = $lines | Where-Object { $_ -match '^\s*Percentage Encrypted:\s*(.+)$' } | Select-Object -First 1
            if ($pctLine -and ($pctLine -match '([0-9]+)\s*%')) {
                try { $result.EncryptionPercentage = [int]$Matches[1] } catch { $result.EncryptionPercentage = $null }
            }

            $kpStart = ($lines | Select-String -Pattern '^\s*Key Protectors:\s*$' | Select-Object -First 1)
            $kpTypes = @()
            if ($kpStart) {
                $startIndex = $kpStart.LineNumber
                for ($i = $startIndex; $i -lt $lines.Count; $i++) {
                    $ln = $lines[$i]
                    if ($i -eq $startIndex) { continue }
                    if ([string]::IsNullOrWhiteSpace($ln)) { break }

                    if ($ln -match '^\s+([A-Za-z ]+):?\s*$') {
                        $mapped = ConvertTo-KeyProtectorTypeName $Matches[1]
                        if ($mapped) { $kpTypes += $mapped }
                    } elseif ($ln -match '^\s+\{[0-9A-Fa-f-]+\}') {
                    } else {
                        if ($ln -match '^\s*\w[^:]+:\s') { break }
                    }
                }
            }
            $result.KeyProtectorTypes = @($kpTypes | Select-Object -Unique)
            $result.HasRecoveryKey = @($result.KeyProtectorTypes | Where-Object { $_ -eq 'RecoveryPassword' }).Count -gt 0

            return [pscustomobject]$result
        } catch {
            if ($_.Exception.Message -match 'Access.*denied') { $result.AdminRequired = $true }
        }
    }

    return [pscustomobject]$result
}

function New-BitLockerTooltipText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Status
    )

    $lines = @()

    if ($Status.OsDrive) {
        $lines += "Drive: $($Status.OsDrive)"
    }
    $lines += "Protection: $($Status.ProtectionStatus)"
    $lines += "Conversion: $($Status.ConversionStatus)"

    if (-not [object]::ReferenceEquals($Status.EncryptionPercentage, $null)) {
        $lines += "Encrypted: $($Status.EncryptionPercentage)%"
    }

    if ($Status.KeyProtectorTypes -and $Status.KeyProtectorTypes.Count -gt 0) {
        $lines += 'Key Protectors:'
        foreach ($kp in $Status.KeyProtectorTypes) {
            $lines += "  - $kp"
        }
    } else {
        $lines += 'Key Protectors: None detected'
    }

    $lines += "Recovery Key Present: $($Status.HasRecoveryKey)"

    if (-not [object]::ReferenceEquals($Status.TpmPresent, $null)) {
        $lines += "TPM Present: $($Status.TpmPresent)"
        $lines += "TPM Ready: $($Status.TpmReady)"
        $lines += "TPM Owned: $($Status.TpmOwned)"
    }

    if ($Status.AdminRequired) {
        $lines += 'Admin rights required for full status'
    }

    if ($Status.Source) {
        $lines += "Source: $($Status.Source)"
    }

    return ($lines -join "`r`n")
}

function Update-ResolveMdmStatusControls {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.Label]$StatusLabel,

        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.Label]$DetailLabel,

        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.Button]$EnrollButton,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$ToolkitState
    )

    $status = Get-ResolveMdmStatus
    $persistedConfirmed = [bool]$ToolkitState.ResolveMdm.EnrollConfirmed

    if ($status.Enrolled) {
        $StatusLabel.Text = 'Connected to ResolveMDM'
        $StatusLabel.ForeColor = [System.Drawing.Color]::ForestGreen

        $details = @()
        if ($status.ServerUrl) { $details += "Server: $($status.ServerUrl)" }
        if ($status.UPN) { $details += "User: $($status.UPN)" }
        if ($status.ProviderID) { $details += "Provider: $($status.ProviderID)" }
        if ($ToolkitState.ResolveMdm.LastConfirmedAt) { $details += "Confirmed: $($ToolkitState.ResolveMdm.LastConfirmedAt)" }
        $DetailLabel.Text = ($details -join "`r`n")
        $EnrollButton.Enabled = $false
    } else {
        $StatusLabel.Text = 'Not connected to ResolveMDM'
        $StatusLabel.ForeColor = [System.Drawing.Color]::Firebrick
        if ($persistedConfirmed) {
            $DetailLabel.Text = 'Enrollment previously confirmed for this toolkit. Re-run enrollment from the source setup tool if needed.'
            $EnrollButton.Enabled = $false
        } else {
            $DetailLabel.Text = 'Click Enroll to install the Resolve MDM provisioning package.'
            $EnrollButton.Enabled = $true
        }
    }

    return $status
}

function Update-BitLockerStatusControls {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.Label]$SummaryLabel,

        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.TextBox]$DetailTextBox
    )

    $status = Get-BitLockerStatus

    $text = 'Status unknown'
    $color = [System.Drawing.Color]::DarkGoldenrod

    $protOn  = ($status.ProtectionStatus -eq 'On')
    $fullEnc = ($status.ConversionStatus -eq 'FullyEncrypted')
    $encing  = ($status.ConversionStatus -eq 'EncryptionInProgress')
    $decin   = ($status.ConversionStatus -eq 'DecryptionInProgress')
    $hasPct  = -not [object]::ReferenceEquals($status.EncryptionPercentage, $null)
    $hasRK   = [bool]$status.HasRecoveryKey

    if ($protOn -and $fullEnc -and $hasRK) {
        $text = 'Encrypted TPM'
        $color = [System.Drawing.Color]::ForestGreen
    } elseif ($encing -or $decin -or ($hasPct -and $status.EncryptionPercentage -gt 0 -and -not $fullEnc)) {
        if ($decin) {
            if ($hasPct) { $text = "Decrypting $($status.EncryptionPercentage)%" }
            else { $text = 'Decrypting' }
        } else {
            if ($hasPct) { $text = "Encrypting $($status.EncryptionPercentage)%" }
            else { $text = 'Encrypting' }
        }
        $color = [System.Drawing.Color]::DarkGoldenrod
    } elseif ($protOn -and $fullEnc -and -not $hasRK) {
        $text = 'Encrypted TPM only'
        $color = [System.Drawing.Color]::DarkGoldenrod
    } else {
        $text = 'Not encrypted'
        $color = [System.Drawing.Color]::Firebrick
    }

    $SummaryLabel.Text = $text
    $SummaryLabel.ForeColor = $color
    $DetailTextBox.Text = New-BitLockerTooltipText -Status $status
}

function Resolve-MdmPackagePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptDir
    )

    $candidates = @(
        (Join-Path $ScriptDir 'Scripts\ResolveMDM\CanfieldScientific.ppkg'),
        'C:\tools\Canfield_Setup_Tool\Scripts\ResolveMDM\CanfieldScientific.ppkg'
    )

    foreach ($path in $candidates) {
        if (Test-Path -LiteralPath $path) {
            return $path
        }
    }

    return $null
}

function Initialize-DeviceStatusTab {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.TabPage]$Tab,

        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.Form]$Form,

        [Parameter(Mandatory = $true)]
        [string]$ScriptDir,

        [Parameter(Mandatory = $true)]
        [scriptblock]$EnterBusy,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ExitBusy,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ShowMessage
    )

    $grpMdm = New-Object System.Windows.Forms.GroupBox
    $grpMdm.Text = 'ResolveMDM'
    $grpMdm.Location = New-Object System.Drawing.Point(15, 15)
    $grpMdm.Size = New-Object System.Drawing.Size(480, 145)
    $grpMdm.Anchor = 'Top,Left,Right'
    $Tab.Controls.Add($grpMdm)

    $mdmStatusLabel = New-Object System.Windows.Forms.Label
    $mdmStatusLabel.Text = 'Checking status...'
    $mdmStatusLabel.Location = New-Object System.Drawing.Point(15, 28)
    $mdmStatusLabel.Size = New-Object System.Drawing.Size(320, 20)
    $grpMdm.Controls.Add($mdmStatusLabel)

    $mdmDetailsLabel = New-Object System.Windows.Forms.Label
    $mdmDetailsLabel.Text = ''
    $mdmDetailsLabel.Location = New-Object System.Drawing.Point(15, 52)
    $mdmDetailsLabel.Size = New-Object System.Drawing.Size(450, 55)
    $grpMdm.Controls.Add($mdmDetailsLabel)

    $btnMdmRefresh = New-Object System.Windows.Forms.Button
    $btnMdmRefresh.Text = 'Refresh'
    $btnMdmRefresh.Location = New-Object System.Drawing.Point(285, 111)
    $btnMdmRefresh.Size = New-Object System.Drawing.Size(85, 24)
    $grpMdm.Controls.Add($btnMdmRefresh)

    $btnMdmEnroll = New-Object System.Windows.Forms.Button
    $btnMdmEnroll.Text = 'Enroll'
    $btnMdmEnroll.Location = New-Object System.Drawing.Point(380, 111)
    $btnMdmEnroll.Size = New-Object System.Drawing.Size(85, 24)
    $grpMdm.Controls.Add($btnMdmEnroll)

    $grpBitLocker = New-Object System.Windows.Forms.GroupBox
    $grpBitLocker.Text = 'BitLocker'
    $grpBitLocker.Location = New-Object System.Drawing.Point(15, 170)
    $grpBitLocker.Size = New-Object System.Drawing.Size(480, 175)
    $grpBitLocker.Anchor = 'Top,Bottom,Left,Right'
    $Tab.Controls.Add($grpBitLocker)

    $bitlockerSummaryLabel = New-Object System.Windows.Forms.Label
    $bitlockerSummaryLabel.Text = 'Checking status...'
    $bitlockerSummaryLabel.Location = New-Object System.Drawing.Point(15, 30)
    $bitlockerSummaryLabel.Size = New-Object System.Drawing.Size(260, 20)
    $grpBitLocker.Controls.Add($bitlockerSummaryLabel)

    $btnBitLockerRefresh = New-Object System.Windows.Forms.Button
    $btnBitLockerRefresh.Text = 'Refresh'
    $btnBitLockerRefresh.Location = New-Object System.Drawing.Point(380, 25)
    $btnBitLockerRefresh.Size = New-Object System.Drawing.Size(85, 24)
    $grpBitLocker.Controls.Add($btnBitLockerRefresh)

    $bitlockerDetailsBox = New-Object System.Windows.Forms.TextBox
    $bitlockerDetailsBox.Location = New-Object System.Drawing.Point(15, 58)
    $bitlockerDetailsBox.Size = New-Object System.Drawing.Size(450, 105)
    $bitlockerDetailsBox.Anchor = 'Top,Bottom,Left,Right'
    $bitlockerDetailsBox.Multiline = $true
    $bitlockerDetailsBox.ScrollBars = 'Vertical'
    $bitlockerDetailsBox.ReadOnly = $true
    $grpBitLocker.Controls.Add($bitlockerDetailsBox)

    $state = Get-ToolkitState

    $updateAll = {
        Update-ResolveMdmStatusControls -StatusLabel $mdmStatusLabel -DetailLabel $mdmDetailsLabel -EnrollButton $btnMdmEnroll -ToolkitState $state | Out-Null
        Update-BitLockerStatusControls -SummaryLabel $bitlockerSummaryLabel -DetailTextBox $bitlockerDetailsBox
    }

    $btnMdmRefresh.Add_Click({
        & $updateAll
    })

    $btnBitLockerRefresh.Add_Click({
        Update-BitLockerStatusControls -SummaryLabel $bitlockerSummaryLabel -DetailTextBox $bitlockerDetailsBox
    })

    $btnMdmEnroll.Add_Click({
        $ppkgPath = Resolve-MdmPackagePath -ScriptDir $ScriptDir
        if (-not $ppkgPath) {
            & $ShowMessage 'Resolve MDM package not found. Expected Scripts\ResolveMDM\CanfieldScientific.ppkg next to this toolkit, or in C:\tools\Canfield_Setup_Tool\Scripts\ResolveMDM\.' 'Error'
            return
        }

        if (-not (Get-Command -Name Install-ProvisioningPackage -ErrorAction SilentlyContinue)) {
            & $ShowMessage 'Install-ProvisioningPackage is not available on this system.' 'Error'
            return
        }

        & $EnterBusy 'Enrolling in Resolve MDM...'
        try {
            Install-ProvisioningPackage -PackagePath $ppkgPath -QuietInstall -ErrorAction Stop

            $state.ResolveMdm.EnrollConfirmed = $true
            $state.ResolveMdm.LastConfirmedAt = (Get-Date).ToString('s')
            Save-ToolkitState -State $state

            & $ExitBusy
            & $ShowMessage 'Resolve MDM enrollment successful.' 'Information'
            & $updateAll
        } catch {
            & $ExitBusy
            & $ShowMessage "Resolve MDM enrollment failed.`n$($_.Exception.Message)" 'Error'
        }
    })

    # Auto-refresh while this tab is selected.
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 3000
    $timer.Add_Tick({
        if ($Tab.Parent -and $Tab.Parent.SelectedTab -eq $Tab) {
            & $updateAll
        }
    })
    $timer.Start()

    $Form.Add_FormClosing({
        if ($timer) {
            $timer.Stop()
            $timer.Dispose()
        }
    })

    & $updateAll
}
