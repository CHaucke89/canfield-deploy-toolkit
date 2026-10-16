<#
.SYNOPSIS
    Packages Install-Toolkit.ps1 into a single DeployToolkit.exe using PS2EXE (run on Windows).
    Run from the folder containing Install-Toolkit.ps1 and LogMeInDeploy.csv.
    If blocked by execution policy: powershell -ExecutionPolicy Bypass -File .\Build-Toolkit-Exe.ps1
#>
$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'Install-Toolkit.ps1'
$csv = Join-Path $PSScriptRoot 'LogMeInDeploy.csv'
$tmp = Join-Path $PSScriptRoot 'Install-Toolkit.build.ps1'
$out = Join-Path $PSScriptRoot 'build\DeployToolkit.exe'

if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'build'))) {
    New-Item -ItemType Directory -Path (Join-Path $PSScriptRoot 'build') | Out-Null
}

if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Install-Module ps2exe -Scope CurrentUser -Force
}
Import-Module ps2exe

# Embed a snapshot of the CSV as a fallback (an external CSV beside the exe still takes priority).
$content = Get-Content -LiteralPath $src -Raw
if (Test-Path -LiteralPath $csv) {
    $csvText = (Get-Content -LiteralPath $csv -Raw).TrimEnd()
    $embed   = "`$EmbeddedCsv = @'`r`n$csvText`r`n'@"
    $content = $content.Replace('$EmbeddedCsv = $null # __EMBEDDED_CSV__', $embed)
} else {
    Write-Warning "LogMeInDeploy.csv not found; building without an embedded sponsor list."
}
Set-Content -LiteralPath $tmp -Value $content -Encoding UTF8

try {
    Invoke-ps2exe -inputFile $tmp -outputFile $out `
        -noConsole -requireAdmin -STA `
        -title 'Deploy Toolkit' -product 'Deploy Toolkit' -version '1.0.0.0'
} finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}
Write-Host "Built: $out"
