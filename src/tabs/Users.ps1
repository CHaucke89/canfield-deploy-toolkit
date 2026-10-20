# Tab: Users (SSCT site users and the SharedAdmin account)

$tabUsers = New-Object System.Windows.Forms.TabPage; $tabUsers.Text = 'Users'
[void]$tabs.TabPages.Add($tabUsers)

function Add-Field($Parent, [string]$Label, [int]$Y) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text     = $Label
    $l.Location = New-Object System.Drawing.Point(12, $Y)
    $l.AutoSize = $true
    $Parent.Controls.Add($l)
    $t = New-Object System.Windows.Forms.TextBox
    $t.Location = New-Object System.Drawing.Point(12, ($Y + 18))
    $t.Size     = New-Object System.Drawing.Size(265, 22)
    $Parent.Controls.Add($t)
    return $t
}

# --- Create user (left) ---
$grpCreate = New-Object System.Windows.Forms.GroupBox
$grpCreate.Text     = 'Create site user'
$grpCreate.Location = New-Object System.Drawing.Point(10, 8)
$grpCreate.Size     = New-Object System.Drawing.Size(290, 400)
$tabUsers.Controls.Add($grpCreate)

$userPrefix = Add-Field $grpCreate 'Prefix (optional, e.g. Dr.):' 22
$userFirst  = Add-Field $grpCreate 'First name:' 68
$userLast   = Add-Field $grpCreate 'Last name:' 114
$userName   = Add-Field $grpCreate 'Username (filled in automatically):' 160
$userPass   = Add-Field $grpCreate 'Temporary password:' 206
$userPass.Text = $script:DefaultUserPassword

$userNote = New-Object System.Windows.Forms.Label
$userNote.Text     = 'The user is added to the SSCT group and must choose a new password at first sign-in.'
$userNote.Location = New-Object System.Drawing.Point(12, 254)
$userNote.Size     = New-Object System.Drawing.Size(265, 32)
$grpCreate.Controls.Add($userNote)

$btnCreateUser = New-Object System.Windows.Forms.Button
$btnCreateUser.Text     = 'Create User'
$btnCreateUser.Location = New-Object System.Drawing.Point(157, 292)
$btnCreateUser.Size     = New-Object System.Drawing.Size(120, 30)
$grpCreate.Controls.Add($btnCreateUser)

$ssoNote = New-Object System.Windows.Forms.Label
$ssoNote.Text      = 'Only SSO protocols are installed. Their users sign in with SSO, so local users are usually not needed.'
$ssoNote.ForeColor = [System.Drawing.Color]::Firebrick
$ssoNote.Location  = New-Object System.Drawing.Point(12, 332)
$ssoNote.Size      = New-Object System.Drawing.Size(265, 48)
$ssoNote.Visible   = $false
$grpCreate.Controls.Add($ssoNote)

$updateUsername = { $userName.Text = ConvertTo-SiteUsername $userFirst.Text $userLast.Text }
$userFirst.Add_TextChanged($updateUsername)
$userLast.Add_TextChanged($updateUsername)

# --- Existing users (right) ---
$grpList = New-Object System.Windows.Forms.GroupBox
$grpList.Text     = 'Site users (SSCT group)'
$grpList.Location = New-Object System.Drawing.Point(310, 8)
$grpList.Size     = New-Object System.Drawing.Size(290, 400)
$tabUsers.Controls.Add($grpList)

$userList = New-Object System.Windows.Forms.ListBox
$userList.Location      = New-Object System.Drawing.Point(12, 22)
$userList.Size          = New-Object System.Drawing.Size(265, 225)
$userList.DisplayMember = 'Display'
$userList.HorizontalScrollbar = $true
$grpList.Controls.Add($userList)

function New-UserButton([string]$Text, [int]$X, [int]$Y, [int]$Width = 130) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text     = $Text
    $b.Location = New-Object System.Drawing.Point($X, $Y)
    $b.Size     = New-Object System.Drawing.Size($Width, 28)
    $grpList.Controls.Add($b)
    return $b
}
$btnResetPass  = New-UserButton 'Reset Password' 12 255
$btnRenameUser = New-UserButton 'Change Name' 147 255
$btnDeleteUser = New-UserButton 'Delete User' 12 289
$btnUserReload = New-UserButton 'Refresh' 147 289
$btnSharedAdmin = New-UserButton 'Create SharedAdmin Account' 12 358 265

function Update-UserButtons {
    $sel = $userList.SelectedItem
    $btnResetPass.Enabled  = ($null -ne $sel)
    $btnRenameUser.Enabled = ($null -ne $sel)
    $btnDeleteUser.Enabled = ($null -ne $sel) -and -not (Test-ProtectedUser $sel.Name)
}

function Update-UsersTab {
    $userList.Items.Clear()
    try {
        foreach ($u in (Get-SiteUsers)) { [void]$userList.Items.Add($u) }
    } catch {
        Show-Message "Could not list the SSCT users:`n$($_.Exception.Message)" 'Warning'
    }
    Update-UserButtons
    $btnSharedAdmin.Enabled = -not (Get-LocalUser -Name 'SharedAdmin' -ErrorAction SilentlyContinue)
    $protocols = @(Get-CaptureProtocols)
    $ssoNote.Visible = ($protocols.Count -gt 0 -and @($protocols | Where-Object { -not $_.SSO }).Count -eq 0)
}

$userList.Add_SelectedIndexChanged({ Update-UserButtons })
$btnUserReload.Add_Click({ Update-UsersTab })
$tabs.Add_SelectedIndexChanged({
    if ($tabs.SelectedTab -eq $tabUsers) { Update-UsersTab }
})

$btnCreateUser.Add_Click({
    $first = $userFirst.Text.Trim(); $last = $userLast.Text.Trim()
    $username = $userName.Text.Trim(); $pass = $userPass.Text
    if (-not $first -or -not $last -or -not $username -or -not $pass) {
        Show-Message 'Enter a first name, last name, username and password.' 'Warning'
        return
    }
    if ($ssoNote.Visible) {
        $go = [System.Windows.Forms.MessageBox]::Show($form,
            "Only SSO protocols are installed, so a local user is usually not needed.`nCreate '$username' anyway?",
            $appTitle, 'YesNo', 'Question')
        if ($go -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    }
    $fullName = (@($userPrefix.Text.Trim(), $first, $last) | Where-Object { $_ }) -join ' '
    try {
        New-SiteUser $username $fullName $pass
        Show-Message "User '$username' ($fullName) created.`nTemporary password: $pass" 'Information'
        $userPrefix.Clear(); $userFirst.Clear(); $userLast.Clear()
        $userPass.Text = $script:DefaultUserPassword
        [void]$userFirst.Focus()
    } catch {
        Show-Message "User NOT created:`n$($_.Exception.Message)" 'Error'
    }
    Update-UsersTab
})

$btnResetPass.Add_Click({
    $u = $userList.SelectedItem
    if ($null -eq $u) { return }
    $pass = Read-Text "New temporary password for '$($u.Name)' (they must change it at next sign-in):" $script:DefaultUserPassword
    if (-not $pass) { return }
    try {
        Reset-SiteUserPassword $u.Name $pass
        Show-Message "Password for '$($u.Name)' reset to '$pass'.`nThey must change it at next sign-in." 'Information'
    } catch {
        Show-Message "Password NOT reset:`n$($_.Exception.Message)" 'Error'
    }
})

$btnRenameUser.Add_Click({
    $u = $userList.SelectedItem
    if ($null -eq $u) { return }
    $name = Read-Text "Full name for '$($u.Name)':" $u.FullName
    if (-not $name -or $name -eq $u.FullName) { return }
    try {
        Set-LocalUser -Name $u.Name -FullName $name -ErrorAction Stop
    } catch {
        Show-Message "Name NOT changed:`n$($_.Exception.Message)" 'Error'
    }
    Update-UsersTab
})

# The only place in the toolkit that deletes a Windows account: one selected user, after a Yes/No naming it.
$btnDeleteUser.Add_Click({
    $u = $userList.SelectedItem
    if ($null -eq $u -or (Test-ProtectedUser $u.Name)) { return }
    $confirm = [System.Windows.Forms.MessageBox]::Show($form,
        "Delete the Windows account '$($u.Display.Trim())'?`n`nThis cannot be undone.",
        $appTitle, 'YesNo', 'Warning', 'Button2')
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    try {
        Remove-SiteUser $u.Name
        Show-Message "'$($u.Name)' deleted." 'Information'
    } catch {
        Show-Message "User NOT deleted:`n$($_.Exception.Message)" 'Error'
    }
    Update-UsersTab
})

$btnSharedAdmin.Add_Click({
    $pass = Read-Text "Password for the new SharedAdmin administrator account:" ''
    if (-not $pass) { return }
    try {
        New-SharedAdmin $pass
        Show-Message 'SharedAdmin account created.' 'Information'
    } catch {
        Show-Message "SharedAdmin account NOT created:`n$($_.Exception.Message)" 'Error'
    }
    Update-UsersTab
})
