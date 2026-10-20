# Pure input helpers (no UI).

# 1-15 letters/digits/hyphens, no leading/trailing hyphen, not only digits.
function Test-ComputerName([string]$Name) {
    return ($Name -match '^(?!\d+$)[A-Za-z0-9](?:[A-Za-z0-9-]{0,13}[A-Za-z0-9])?$')
}

# Site Photographer passwords are letters only, lower-case.
function ConvertTo-PhotographerPassword([string]$Text) {
    return ($Text.ToLower() -replace '[^a-z]', '')
}

# Site user names: first initial + last name, letters only, lower case (Jane O'Neil -> joneil).
function ConvertTo-SiteUsername([string]$First, [string]$Last) {
    $f = $First -replace '[^A-Za-z]', ''
    $l = $Last -replace '[^A-Za-z]', ''
    if (-not $f -or -not $l) { return '' }
    return ($f.Substring(0, 1) + $l).ToLower()
}
