# Sponsor list loading (Sponsor,DeployID). An external CSV wins over the copy embedded at build time.

function Get-Sponsors([string]$Path, [string]$EmbeddedCsv) {
    $rows = $null
    if (Test-Path -LiteralPath $Path) { $rows = Import-Csv -LiteralPath $Path }
    elseif ($EmbeddedCsv)             { $rows = $EmbeddedCsv | ConvertFrom-Csv }

    return @($rows | Where-Object { $_.Sponsor -and $_.DeployID } | ForEach-Object {
        [pscustomobject]@{ Sponsor = $_.Sponsor.Trim(); DeployID = $_.DeployID.Trim() }
    } | Sort-Object Sponsor)
}
