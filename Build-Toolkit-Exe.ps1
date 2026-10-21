<#
.SYNOPSIS
    Packages Install-Toolkit.ps1 plus the src\ files (inlined) into a single CDT.exe using PS2EXE (run on Windows).
    Run from the folder containing Install-Toolkit.ps1, src\ and sponsors.csv.
    If assets\ResponseCodeGenerator.exe is present it is embedded too.
    If blocked by execution policy: powershell -ExecutionPolicy Bypass -File .\Build-Toolkit-Exe.ps1

.PARAMETER Version
    Version stamped into the exe (file and product version). Accepts a release tag such as 'v1.2.0';
    a leading 'v' is dropped and missing parts are filled with 0 (v1.2.0 -> 1.2.0.0). Defaults to 1.0.0.0.
#>
[CmdletBinding()]
param(
    [string]$Version = '1.0.0.0'
)
$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'Install-Toolkit.ps1'
$csv = Join-Path $PSScriptRoot 'sponsors.csv'
$rcg = Join-Path $PSScriptRoot 'assets\ResponseCodeGenerator.exe'
$tmp = Join-Path $PSScriptRoot 'Install-Toolkit.build.ps1'
$out = Join-Path $PSScriptRoot 'build\CDT.exe'
$icon = Join-Path $PSScriptRoot 'assets\toolkit.ico'

# PS2EXE needs a 4-part numeric version (major.minor.build.revision).
$parsed = $null
if (-not [version]::TryParse(($Version -replace '^[vV]', ''), [ref]$parsed)) {
    throw "Version '$Version' is not a valid version (expected e.g. v1.2.0 or 1.2.0.0)."
}
$exeVersion = '{0}.{1}.{2}.{3}' -f $parsed.Major, $parsed.Minor, [math]::Max($parsed.Build, 0), [math]::Max($parsed.Revision, 0)

if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'build'))) {
    New-Item -ItemType Directory -Path (Join-Path $PSScriptRoot 'build') | Out-Null
}

if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Install-Module ps2exe -Scope CurrentUser -Force
}
Import-Module ps2exe

# Inline the src\ files (in LoadOrder.ps1 order) in place of the dot-source block, so the exe is self-contained.
$srcDir = Join-Path $PSScriptRoot 'src'
$parts  = foreach ($rel in (& (Join-Path $srcDir 'LoadOrder.ps1'))) {
    "# ---- src\$rel ----`r`n" + (Get-Content -LiteralPath (Join-Path $srcDir $rel) -Raw)
}
$inlined = $parts -join "`r`n"

# Embed a snapshot of the CSV as a fallback (an external CSV beside the exe still takes priority).
$content = Get-Content -LiteralPath $src -Raw
$begin = $content.IndexOf('# __SOURCES_BEGIN__')
$endMarker = '# __SOURCES_END__'
$end = $content.IndexOf($endMarker)
if ($begin -lt 0 -or $end -lt $begin) { throw 'Source markers not found in Install-Toolkit.ps1.' }
$content = $content.Substring(0, $begin) + $inlined + $content.Substring($end + $endMarker.Length)
if (Test-Path -LiteralPath $csv) {
    $csvText = (Get-Content -LiteralPath $csv -Raw).TrimEnd()
    $embed   = "`$EmbeddedCsv = @'`r`n$csvText`r`n'@"
    $content = $content.Replace('$EmbeddedCsv = $null # __EMBEDDED_CSV__', $embed)
} else {
    Write-Warning "sponsors.csv not found; building without an embedded sponsor list."
}
# Embed ResponseCodeGenerator.exe (base64) so the exe can run it without the USB drive.
if (Test-Path -LiteralPath $rcg) {
    $b64     = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($rcg))
    $content = $content.Replace('$EmbeddedRcg = $null # __EMBEDDED_RCG__', "`$EmbeddedRcg = '$b64'")
} else {
    Write-Warning "assets\ResponseCodeGenerator.exe not found; building without an embedded Response Code Generator."
}
Set-Content -LiteralPath $tmp -Value $content -Encoding UTF8

try {
    Invoke-ps2exe -inputFile $tmp -outputFile $out `
        -noConsole -requireAdmin -STA -iconFile $icon `
        -title 'Canfield Deployment Toolkit' -product 'Canfield Deployment Toolkit' -version $exeVersion
} finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}
Write-Host "Built: $out (version $exeVersion)"
