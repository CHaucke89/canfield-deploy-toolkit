# USB drive discovery.

function Get-UsbDriveRoots {
    $roots = @()
    try {
        $roots = @(Get-Disk -ErrorAction Stop | Where-Object { $_.BusType -eq 'USB' } |
            Get-Partition -ErrorAction SilentlyContinue |
            Where-Object { $_.DriveLetter -match '[A-Za-z]' } |
            ForEach-Object { '{0}:\' -f $_.DriveLetter })
    } catch { }
    if ($roots.Count -eq 0) {   # fallback: removable media
        $roots = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=2' |
            ForEach-Object { '{0}\' -f $_.DeviceID })
    }
    return @($roots | Where-Object { Test-Path -LiteralPath $_ } | Sort-Object -Unique)
}
