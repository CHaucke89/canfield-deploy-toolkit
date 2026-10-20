# Local Windows accounts: SSCT site users and the SharedAdmin account (ported from CST.ps1).
# Accounts are only ever deleted by Remove-SiteUser, which the Users tab calls after an explicit confirmation.

$script:SiteUserGroup       = 'SSCT'
$script:DefaultUserPassword = 'Photo321'   # temporary: new users must change it at first logon
$script:ProtectedUsers      = @('Site Photographer', 'SharedAdmin', 'Administrator')

function Test-ProtectedUser([string]$Name) {
    return ($script:ProtectedUsers -contains $Name) -or ($Name -eq $env:USERNAME)
}

# Local user accounts in the SSCT group.
function Get-SiteUsers {
    if (-not (Get-LocalGroup -Name $script:SiteUserGroup -ErrorAction SilentlyContinue)) { return @() }
    return @(Get-LocalGroupMember -Group $script:SiteUserGroup -ErrorAction Stop |
        Where-Object { "$($_.ObjectClass)" -eq 'User' } |
        ForEach-Object { Get-LocalUser -Name ($_.Name -replace '^.*\\', '') -ErrorAction SilentlyContinue } |
        Sort-Object Name | ForEach-Object {
            $display = if ($_.FullName) { '{0}    ({1})' -f $_.Name, $_.FullName } else { $_.Name }
            [pscustomobject]@{ Name = $_.Name; FullName = $_.FullName; Display = $display }
        })
}

function Set-UserPasswordExpired([string]$Name) {
    $usr = [ADSI]("WinNT://$env:COMPUTERNAME/$Name,user")
    $usr.PasswordExpired = 1
    $usr.SetInfo()
}

# Creates the user, adds it to SSCT (creating the group if needed) and forces a password change at first logon.
function New-SiteUser([string]$Username, [string]$FullName, [string]$Password) {
    if (-not (Get-LocalGroup -Name $script:SiteUserGroup -ErrorAction SilentlyContinue)) {
        New-LocalGroup -Name $script:SiteUserGroup -ErrorAction Stop | Out-Null
    }
    $secure = ConvertTo-SecureString $Password -AsPlainText -Force
    New-LocalUser -Name $Username -FullName $FullName -Password $secure -ErrorAction Stop | Out-Null
    try {
        Add-LocalGroupMember -Group $script:SiteUserGroup -Member $Username -ErrorAction Stop
        Set-UserPasswordExpired $Username
    } catch {
        throw "User '$Username' was created, but setup did not finish: $($_.Exception.Message)"
    }
}

# Sets a new password that the user must change at next logon.
function Reset-SiteUserPassword([string]$Name, [string]$Password) {
    Set-LocalUser -Name $Name -Password (ConvertTo-SecureString $Password -AsPlainText -Force) -ErrorAction Stop
    Set-UserPasswordExpired $Name
}

function Remove-SiteUser([string]$Name) {
    if (Test-ProtectedUser $Name) { throw "'$Name' is protected and cannot be deleted." }
    Remove-LocalUser -Name $Name -ErrorAction Stop
}

function New-SharedAdmin([string]$Password) {
    $secure = ConvertTo-SecureString $Password -AsPlainText -Force
    New-LocalUser -Name 'SharedAdmin' -FullName 'Shared Administrator' -Description 'Administrator Account for Site Usage.' `
        -Password $secure -PasswordNeverExpires -UserMayNotChangePassword -ErrorAction Stop | Out-Null
    Add-LocalGroupMember -SID 'S-1-5-32-544' -Member 'SharedAdmin' -ErrorAction Stop   # Administrators, any language
}
