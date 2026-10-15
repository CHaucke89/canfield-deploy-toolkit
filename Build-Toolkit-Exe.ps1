<#
.SYNOPSIS
    Packages Install-Toolkit.ps1 into DeployToolkit.exe using PS2EXE (run on Windows).
    Also stages required module files and ResolveMDM assets beside the exe.
    Run from the folder containing Install-Toolkit.ps1 and LogMeInDeploy.csv.
    If blocked by execution policy: powershell -ExecutionPolicy Bypass -File .\Build-Toolkit-Exe.ps1
#>
$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'Install-Toolkit.ps1'
$csv = Join-Path $PSScriptRoot 'LogMeInDeploy.csv'
$tmp = Join-Path $PSScriptRoot 'Install-Toolkit.build.ps1'
$stageRoot = Join-Path $PSScriptRoot 'DeployToolkit-Package'
$out = Join-Path $stageRoot 'DeployToolkit.exe'

$moduleFiles = @(
    'Install-LogMeIn.ps1',
    'Install-CanfieldCapture.ps1',
    'Install-DeviceStatus.ps1'
)

$resolveSourceDir = Join-Path $PSScriptRoot 'Scripts\ResolveMDM'
$resolveTargetDir = Join-Path $stageRoot 'Scripts\ResolveMDM'

if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Install-Module ps2exe -Scope CurrentUser -Force
}
Import-Module ps2exe

if (-not (Test-Path -LiteralPath $stageRoot)) {
    New-Item -Path $stageRoot -ItemType Directory | Out-Null
}

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

    foreach ($module in $moduleFiles) {
        $modulePath = Join-Path $PSScriptRoot $module
        if (-not (Test-Path -LiteralPath $modulePath)) {
            throw "Required module file not found: $modulePath"
        }
        Copy-Item -LiteralPath $modulePath -Destination $stageRoot -Force
    }

    if (Test-Path -LiteralPath $resolveSourceDir) {
        New-Item -Path $resolveTargetDir -ItemType Directory -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $resolveSourceDir '*') -Destination $resolveTargetDir -Recurse -Force
    } else {
        Write-Warning "ResolveMDM assets folder not found: $resolveSourceDir"
    }
} finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}
Write-Host "Built and staged: $stageRoot"
