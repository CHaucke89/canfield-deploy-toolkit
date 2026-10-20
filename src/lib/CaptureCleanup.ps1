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

# Files the cleanup must never delete, wherever they sit under Databases.
$script:CaptureProtectedFiles = @('Registered_Users.sdf')

# Deletes everything under $Dir except protected files. A folder is removed whole only when nothing
# protected lives anywhere inside it; otherwise it is emptied around the protected files.
# Filters by name in the pipeline: Windows PowerShell 5.1 ignores -Exclude when used with -LiteralPath.
function Remove-CaptureDataExceptProtected([string]$Dir) {
    foreach ($item in @(Get-ChildItem -LiteralPath $Dir -Force)) {
        if ($item.PSIsContainer) {
            $hasProtected = @(Get-ChildItem -LiteralPath $item.FullName -Recurse -File -Force |
                Where-Object { $script:CaptureProtectedFiles -contains $_.Name }).Count -gt 0
            if ($hasProtected) { Remove-CaptureDataExceptProtected $item.FullName }
            else { Remove-Item -LiteralPath $item.FullName -Recurse -Force }
        } elseif ($script:CaptureProtectedFiles -notcontains $item.Name) {
            Remove-Item -LiteralPath $item.FullName -Force
        }
    }
}

# Deletes a version's site data. Registered_Users.sdf is always kept.
function Clear-CaptureDatabase([string]$VersionName) {
    $root = Join-Path $script:CaptureDataRoot $VersionName
    Get-ChildItem -Path (Join-Path $root 'SSCT_System_Data*.sdf') -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force
    if (Test-Path -LiteralPath (Join-Path $root 'Temp')) {
        Remove-Item -LiteralPath (Join-Path $root 'Temp') -Recurse -Force
    }
    if (Test-Path -LiteralPath (Join-Path $root 'Databases')) {
        Remove-CaptureDataExceptProtected (Join-Path $root 'Databases')
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

# Installed Canfield Capture programs (version folders under Program Files that contain the exe).
function Get-CaptureInstalls {
    if (-not (Test-Path -LiteralPath $script:CaptureProgramRoot)) { return @() }
    return @(Get-ChildItem -LiteralPath $script:CaptureProgramRoot -Directory -Filter 'Canfield Capture v*' -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'Canfield Capture.exe') } |
        Sort-Object Name | ForEach-Object {
            [pscustomobject]@{
                Name    = $_.Name
                Display = $_.Name -replace '^Canfield Capture ', 'CC '
                Exe     = Join-Path $_.FullName 'Canfield Capture.exe'
            }
        })
}

# Copies Registered_Users.sdf from the first listed version that has one to the versions that have none,
# so every version knows the site's users. An existing Registered_Users.sdf is never overwritten.
# Returns the names of the versions it copied to.
function Copy-RegisteredUsers([string[]]$VersionNames) {
    $files  = @($VersionNames | ForEach-Object { Join-Path $script:CaptureDataRoot "$_\Databases\Registered_Users.sdf" })
    $source = $files | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $source) { return @() }
    $copied = @()
    for ($i = 0; $i -lt $files.Count; $i++) {
        if (Test-Path -LiteralPath $files[$i]) { continue }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $files[$i]) | Out-Null
        Copy-Item -LiteralPath $source -Destination $files[$i] -ErrorAction Stop
        $copied += $VersionNames[$i]
    }
    return $copied
}
