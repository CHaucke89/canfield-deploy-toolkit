# Canfield Capture database cleanup (ported from the Cleanup Tool in CST.ps1).

$script:CaptureDataRoot = 'C:\ProgramData\Canfield'
$script:CaptureProgramRoot = 'C:\Program Files (x86)\Canfield Scientific Inc'
$script:VectraCalVersions = @('v3.4.0', 'v3.4.1', 'v3.5.0', 'v3.5.1')

# Installed versions (folders 'Canfield Capture v*' under ProgramData\Canfield). A version is dirty when
# any protocol database folder with a one-character name (the site/PID folders) exists.
function Get-CaptureVersions {
    if (-not (Test-Path -LiteralPath $script:CaptureDataRoot)) { return @() }
    return @(Get-ChildItem -LiteralPath $script:CaptureDataRoot -Directory -Filter 'Canfield Capture v*' -ErrorAction SilentlyContinue |
        Sort-Object Name | ForEach-Object {
            [pscustomobject]@{
                Name    = $_.Name
                Display = $_.Name -replace '^Canfield Capture ', 'CC '
                Path    = $_.FullName
                Dirty   = [bool](Test-Path -Path (Join-Path $_.FullName 'Databases\*\?\'))
            }
        })
}

# Deletes a version's site data. Registered_Users.sdf is kept.
function Clear-CaptureDatabase([string]$VersionName) {
    $root = Join-Path $script:CaptureDataRoot $VersionName
    Get-ChildItem -Path (Join-Path $root 'SSCT_System_Data*.sdf') -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force
    if (Test-Path -LiteralPath (Join-Path $root 'Temp')) {
        Remove-Item -LiteralPath (Join-Path $root 'Temp') -Recurse -Force
    }
    if (Test-Path -LiteralPath (Join-Path $root 'Databases')) {
        Get-ChildItem -LiteralPath (Join-Path $root 'Databases') -Exclude 'Registered_Users.sdf' -Force |
            Remove-Item -Recurse -Force
    }
    if (Test-Path -Path 'C:\Calibration Report\*.*') {
        Remove-Item -Path 'C:\Calibration Report\*.*' -Recurse -Force
    }
    $vectra = 'C:\ProgramData\Canfield\Vectra Calibration\VectraM3 Calibration\data\'
    if ((Test-Path -LiteralPath $vectra) -and ($script:VectraCalVersions -contains ($VersionName -replace '^Canfield Capture ', ''))) {
        Remove-Item -LiteralPath $vectra -Recurse -Force
    }
}

# Marks the version's diagnostic logs as cleaned by prefixing them with 'CU-'.
function Rename-CaptureLogFiles([string]$VersionName) {
    $dir = 'C:\ProgramData\Canfield\DiagLib'
    if (-not (Test-Path -LiteralPath $dir)) { return }
    Get-ChildItem -LiteralPath $dir -Filter "$VersionName*.log" -ErrorAction SilentlyContinue |
        ForEach-Object { Rename-Item -LiteralPath $_.FullName -NewName "CU-$($_.Name)" -ErrorAction SilentlyContinue }
}

# Forces every member of the local SSCT group to change their password at next logon.
function Set-SsctPasswordExpired {
    foreach ($member in @(Get-LocalGroupMember -Group 'SSCT' -ErrorAction Stop)) {
        $usr = [ADSI]('WinNT://' + ($member.Name -replace '\\', '/'))
        $usr.PasswordExpired = 1
        $usr.SetInfo()
    }
}
