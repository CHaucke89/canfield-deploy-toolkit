# Shared progress window and busy/message helpers. Requires $form and $appTitle (see MainWindow.ps1).

$status = New-Object System.Windows.Forms.Form
$status.Text            = $appTitle
$status.ClientSize      = New-Object System.Drawing.Size(410, 120)
$status.StartPosition   = 'CenterParent'
$status.FormBorderStyle = 'FixedDialog'
$status.ControlBox      = $false
$status.ShowInTaskbar   = $false
$status.TopMost         = $true

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = New-Object System.Drawing.Point(15, 12)
$statusLabel.Size     = New-Object System.Drawing.Size(380, 40)
$status.Controls.Add($statusLabel)

$bar = New-Object System.Windows.Forms.ProgressBar
$bar.Style    = 'Marquee'
$bar.Location = New-Object System.Drawing.Point(15, 58)
$bar.Size     = New-Object System.Drawing.Size(380, 18)
$status.Controls.Add($bar)

$script:cancelRequested = $false
$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Text     = 'Cancel'
$btnStop.Location = New-Object System.Drawing.Point(320, 86)
$btnStop.Size     = New-Object System.Drawing.Size(75, 24)
$btnStop.Add_Click({ $script:cancelRequested = $true })
$status.Controls.Add($btnStop)

function Set-Status([string]$text) {
    $statusLabel.Text = $text
    [System.Windows.Forms.Application]::DoEvents()
}

function Enter-Busy([string]$text, [bool]$cancellable = $false) {
    $script:cancelRequested = $false
    $btnStop.Visible = $cancellable
    $form.Enabled = $false
    $status.Show($form)
    Set-Status $text
}

function Exit-Busy {
    $status.Hide()
    $form.Enabled = $true
    [void]$form.Activate()
}

function Show-Message([string]$text, [string]$icon) {
    [void][System.Windows.Forms.MessageBox]::Show($form, $text, $appTitle, 'OK', $icon)
}

# Starts a process and keeps the UI alive with an elapsed timer until it exits.
function Invoke-WithProgress([string]$file, [string]$arguments, [string]$workDir, [string]$windowStyle, [string]$label) {
    $p = @{ FilePath = $file; PassThru = $true; WindowStyle = $windowStyle }
    if ($arguments) { $p.ArgumentList = $arguments }
    if ($workDir)   { $p.WorkingDirectory = $workDir }
    $proc = Start-Process @p
    $null = $proc.Handle   # cache handle so ExitCode is readable after exit
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not $proc.HasExited) {
        Set-Status ("{0}`nElapsed: {1:mm\:ss}" -f $label, $sw.Elapsed)
        Start-Sleep -Milliseconds 250
    }
    return $proc.ExitCode
}
