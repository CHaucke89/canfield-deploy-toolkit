# Main window: form, tab control and Close button. Tabs add their own TabPage to $tabs (see src\Tabs).

$form = New-Object System.Windows.Forms.Form
$form.Text            = $appTitle
$form.ClientSize      = New-Object System.Drawing.Size(540, 430)
$form.StartPosition   = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox     = $false
# Use the exe's embedded icon (set by Build-Toolkit-Exe.ps1) for the window and taskbar.
if ($isExe) { $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($procPath) }

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = New-Object System.Drawing.Point(10, 10)
$tabs.Size     = New-Object System.Drawing.Size(520, 370)
$form.Controls.Add($tabs)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text         = 'Close'
$btnClose.Location     = New-Object System.Drawing.Point(445, 390)
$btnClose.Size         = New-Object System.Drawing.Size(85, 28)
$btnClose.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
$form.Controls.Add($btnClose)
$form.CancelButton = $btnClose
