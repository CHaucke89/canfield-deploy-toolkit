# Files loaded by Install-Toolkit.ps1, in order (paths relative to src\).
# Build-Toolkit-Exe.ps1 reads this same list to inline the files into the single-file exe.
# Tab order in the window follows the order of the Tabs\ entries.
@(
    'Lib\Validation.ps1'
    'Lib\Sponsors.ps1'
    'Lib\Usb.ps1'
    'Lib\CaptureCleanup.ps1'
    'Ui\MainWindow.ps1'
    'Ui\Progress.ps1'
    'Tabs\ComputerName.ps1'
    'Tabs\SitePhotographer.ps1'
    'Tabs\LogMeIn.ps1'
    'Tabs\CanfieldCapture.ps1'
    'Tabs\CleanupTool.ps1'
)
