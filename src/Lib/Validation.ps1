# Pure input helpers (no UI).

# 1-15 letters/digits/hyphens, no leading/trailing hyphen, not only digits.
function Test-ComputerName([string]$Name) {
    return ($Name -match '^(?!\d+$)[A-Za-z0-9](?:[A-Za-z0-9-]{0,13}[A-Za-z0-9])?$')
}

# Site Photographer passwords are letters only, lower-case.
function ConvertTo-PhotographerPassword([string]$Text) {
    return ($Text.ToLower() -replace '[^a-z]', '')
}
