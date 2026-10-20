# Read-only machine checks used by the Summary and Remote Access tabs, plus the Canfield scripts and
# Resolve MDM package (ported from CST.ps1). Requires CaptureCleanup.ps1 (Canfield Capture paths).

function Get-MachineInfo {
    $product = Get-CimInstance Win32_ComputerSystemProduct -ErrorAction SilentlyContinue
    $bios    = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
    # Lenovo keeps the readable model name in Version; other vendors use Name.
    $model = if ($product.Vendor -like 'Lenovo*') { $product.Version } else { $product.Name }
    return [pscustomobject]@{ ServiceTag = $bios.SerialNumber; Model = $model }
}

function Get-WifiStatus {
    $conn = Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
        Where-Object { $_.PhysicalMediaType -eq 'Native 802.11' -and $_.Status -eq 'Up' } |
        Get-NetConnectionProfile -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($conn) { return "Connected ($($conn.Name))" }
    return 'Not connected'
}

function Get-BitLockerSummary {
    try { $vol = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop }
    catch { return 'Unknown' }
    $hasRecovery = @($vol.KeyProtector | Where-Object { "$($_.KeyProtectorType)" -eq 'RecoveryPassword' }).Count -gt 0
    switch ("$($vol.VolumeStatus)") {
        'FullyEncrypted' {
            if ("$($vol.ProtectionStatus)" -ne 'On') { return 'Encrypted, protection off' }
            if (-not $hasRecovery) { return 'Encrypted, no recovery key' }
            return 'Encrypted'
        }
        'EncryptionInProgress' { return "Encrypting ($($vol.EncryptionPercentage)%)" }
        'DecryptionInProgress' { return "Decrypting ($($vol.EncryptionPercentage)%)" }
        default                { return 'Not encrypted' }
    }
}

function Test-LogMeInInstalled {
    $keys = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
              'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')
    return [bool](Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq 'LogMeIn' })
}

# Resolve MDM (Miradore) enrollment, read from the Windows MDM enrollment keys.
function Test-ResolveMdmEnrolled {
    foreach ($key in @(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction SilentlyContinue)) {
        $p = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
        if ($p.ProviderID -eq 'MiradoreMDM' -or $p.DiscoveryServiceFullURL -like 'https://gateway.miradore.com/*' -or
            $p.UPN -like '*@mdm.gotoresolve.com') { return $true }
    }
    return $false
}

# Site ID that Canfield Capture last logged for a protocol (newest log first). Empty when none is logged;
# the Cleanup Tool renames a cleaned version's logs, so a cleaned version shows no Site ID until it is set again.
function Get-SiteIdFromLogs([string]$VersionName, [string]$Protocol) {
    $pattern = "Center ID set to (\S+) for '{0}'" -f [regex]::Escape($Protocol)
    $logs = Get-ChildItem -LiteralPath 'C:\ProgramData\Canfield\DiagLib' -Filter "$VersionName*.log" -ErrorAction SilentlyContinue
    foreach ($log in @($logs | Sort-Object LastWriteTime -Descending)) {
        $hit = Select-String -LiteralPath $log.FullName -Pattern $pattern -ErrorAction SilentlyContinue | Select-Object -Last 1
        if ($hit) { return $hit.Matches[0].Groups[1].Value }
    }
    return ''
}

# Installed protocols (Studies) per Canfield Capture version. SSO = the version has study_web_configs.sdf.
function Get-CaptureProtocols([switch]$WithSiteId) {
    return @(foreach ($v in (Get-CaptureVersions)) {
        $sso = Test-Path -LiteralPath (Join-Path $v.Path 'study_web_configs.sdf')
        foreach ($study in @(Get-ChildItem -LiteralPath (Join-Path $v.Path 'Studies') -ErrorAction SilentlyContinue)) {
            $siteId = if ($WithSiteId) { Get-SiteIdFromLogs $v.Name $study.Name } else { '' }
            [pscustomobject]@{ Protocol = $study.Name; Version = $v.Display; SiteID = $siteId; SSO = $sso }
        }
    })
}

# Canfield helper scripts: scheduled task name and installer path (relative to the Scripts folder).
$script:CanfieldScripts = @(
    [pscustomobject]@{ Name = 'Reboot script';         Task = 'RebootShutdown'; Installer = 'Reboot Script\wtrbt.bat' }
    [pscustomobject]@{ Name = 'BGInfo';                Task = 'BginfoDesktop';  Installer = 'bginfo\bginfosetup.bat' }
    [pscustomobject]@{ Name = 'Windows Update script'; Task = 'WindowsUpdate';  Installer = 'WindowsUpdate\WindowsUpdate\WindowsUpdate.bat' }
)
$script:MdmPackage = 'ResolveMDM\CanfieldScientific.ppkg'

# Looks in a Scripts folder next to the script/exe first, then the old Canfield Setup Tool location.
function Find-ScriptsFile([string]$RelPath) {
    foreach ($root in @((Join-Path $scriptDir 'Scripts'), 'C:\tools\Canfield_Setup_Tool\Scripts')) {
        $path = Join-Path $root $RelPath
        if (Test-Path -LiteralPath $path) { return $path }
    }
    return $null
}

# 'Not installed', 'On' or 'Off'.
function Get-CanfieldTaskState([string]$Task) {
    $t = Get-ScheduledTask -TaskName $Task -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $t) { return 'Not installed' }
    if ("$($t.State)" -eq 'Disabled') { return 'Off' }
    return 'On'
}

function Set-CanfieldTaskEnabled([string]$Task, [bool]$Enabled) {
    $t = Get-ScheduledTask -TaskName $Task -ErrorAction Stop | Select-Object -First 1
    if ($Enabled) { $t | Enable-ScheduledTask -ErrorAction Stop | Out-Null }
    else          { $t | Disable-ScheduledTask -ErrorAction Stop | Out-Null }
}
