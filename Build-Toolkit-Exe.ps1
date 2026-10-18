<#
.SYNOPSIS
    Packages Install-Toolkit.ps1 plus the src\ files (inlined) into a single DeployToolkit.exe using PS2EXE (run on Windows).
    Run from the folder containing Install-Toolkit.ps1, src\ and sponsors.csv.
    If blocked by execution policy: powershell -ExecutionPolicy Bypass -File .\Build-Toolkit-Exe.ps1
#>
$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'Install-Toolkit.ps1'
$csv = Join-Path $PSScriptRoot 'sponsors.csv'
$tmp = Join-Path $PSScriptRoot 'Install-Toolkit.build.ps1'
$out = Join-Path $PSScriptRoot 'build\DeployToolkit.exe'
$icon = Join-Path $PSScriptRoot 'assets\toolkit.ico'

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
Set-Content -LiteralPath $tmp -Value $content -Encoding UTF8

try {
    Invoke-ps2exe -inputFile $tmp -outputFile $out `
        -noConsole -requireAdmin -STA -iconFile $icon `
        -title 'Deploy Toolkit' -product 'Deploy Toolkit' -version '1.0.0.0'
} finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}
Write-Host "Built: $out"
