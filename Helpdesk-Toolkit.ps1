<#
.SYNOPSIS
    Tier 1 / Tier 2 Helpdesk Support Automation Toolkit
.DESCRIPTION
    Automates daily Active Directory administrative workflows, account unlocks, 
    password resets, group access management, and remote workstation diagnostics.
.AUTHOR
    Keven Flores
#>

# Ensure script runs with elevated Administrator privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Please run this script as an Administrator!"
    Break
}

# ==========================================
# 1. ACCOUNT STATUS & UNLOCK FUNCTION
# ==========================================
function Check-UserStatusAndUnlock {
    Clear-Host
    Write-Host "--- ACCOUNT STATUS & UNLOCK TOOL ---" -ForegroundColor Cyan
    $username = Read-Host "Enter the sAMAccountName (username)"

    if ([string]::IsNullOrWhiteSpace($username)) {
        Write-Warning "Username cannot be blank."
        Pause
        return
    }

    try {
        # Query Active Directory with extended properties
        $adUser = Get-ADUser -Identity $username -Properties LockedOut, BadLogonCount, PasswordLastSet, Enabled, AccountLockoutTime -ErrorAction Stop

        Write-Host "`nAccount Details for: $($adUser.SamAccountName)" -ForegroundColor Yellow
        Write-Host "----------------------------------------"
        Write-Host "Display Name       : $($adUser.Name)"
        Write-Host "Account Enabled    : $($adUser.Enabled)"
        Write-Host "Locked Out         : $($adUser.LockedOut)" -ForegroundColor $(if ($adUser.LockedOut) { "Red" } else { "Green" })
        Write-Host "Bad Password Count : $($adUser.BadLogonCount)"
        Write-Host "Password Last Set  : $($adUser.PasswordLastSet)"
        Write-Host "Lockout Timestamp  : $($adUser.AccountLockoutTime)"
        Write-Host "----------------------------------------"

        # If the account is locked, offer an immediate unlock prompt
        if ($adUser.LockedOut) {
            $unlockChoice = Read-Host "`nAccount is locked! Do you want to unlock it now? (Y/N)"
            if ($unlockChoice.ToUpper() -eq "Y") {
                Unlock-ADAccount -Identity $username
                Write-Host "`n[SUCCESS] Account '$username' has been unlocked." -ForegroundColor Green
            } else {
                Write-Host "`n[INFO] Account left locked." -ForegroundColor Gray
            }
        } else {
            Write-Host "`n[INFO] Account is currently in good standing (Not locked)." -ForegroundColor Green
        }
    }
    catch {
        Write-Host "`n[ERROR] User '$username' was not found in Active Directory." -ForegroundColor Red
    }

    Write-Host ""
    Pause
}

# ==========================================
# 2. PASSWORD RESET FUNCTION
# ==========================================
function Reset-UserPasswordTool {
    Clear-Host
    Write-Host "--- ACTIVE DIRECTORY PASSWORD RESET TOOL ---" -ForegroundColor Cyan
    $username = Read-Host "Enter the sAMAccountName (username)"

    if ([string]::IsNullOrWhiteSpace($username)) {
        Write-Warning "Username cannot be blank."
        Pause
        return
    }

    try {
        # Verify account exists first
        $adUser = Get-ADUser -Identity $username -ErrorAction Stop

        Write-Host "`nTarget User: $($adUser.Name) ($($adUser.SamAccountName))" -ForegroundColor Yellow
        $newPasswordPlain = Read-Host "Enter Temporary Password"

        if ([string]::IsNullOrWhiteSpace($newPasswordPlain)) {
            Write-Warning "Password cannot be blank."
            Pause
            return
        }

        # Convert plaintext string to required SecureString format
        $securePassword = ConvertTo-SecureString $newPasswordPlain -AsPlainText -Force

        # Apply new password and force change at next logon
        Set-ADAccountPassword -Identity $username -NewPassword $securePassword -Reset
        Set-ADUser -Identity $username -ChangePasswordAtLogon $true

        # Auto-unlock in case account was locked from bad password attempts
        Unlock-ADAccount -Identity $username

        Write-Host "`n[SUCCESS] Password successfully reset for '$username'." -ForegroundColor Green
        Write-Host "[INFO] User MUST change password at next login." -ForegroundColor Yellow
        Write-Host "[INFO] Account has been automatically unlocked." -ForegroundColor Gray
    }
    catch {
        Write-Host "`n[ERROR] Failed to reset password for '$username'. Verify account existence and password complexity requirements." -ForegroundColor Red
    }

    Write-Host ""
    Pause
}

# ==========================================
# 3. GROUP MEMBERSHIP MANAGEMENT FUNCTION
# ==========================================
function Manage-ADGroupMembership {
    Clear-Host
    Write-Host "--- ACTIVE DIRECTORY GROUP MANAGEMENT TOOL ---" -ForegroundColor Cyan
    $username = Read-Host "Enter the sAMAccountName (username)"

    if ([string]::IsNullOrWhiteSpace($username)) {
        Write-Warning "Username cannot be blank."
        Pause
        return
    }

    try {
        # Verify account exists
        $adUser = Get-ADUser -Identity $username -ErrorAction Stop
        
        Write-Host "`nCurrent Security Groups for: $($adUser.Name)" -ForegroundColor Yellow
        Write-Host "--------------------------------------------------"
        $currentGroups = Get-ADPrincipalGroupMembership -Identity $username | Select-Object -ExpandProperty Name
        $currentGroups | ForEach-Object { Write-Host "  * $_" -ForegroundColor Green }
        Write-Host "--------------------------------------------------"

        Write-Host "`nActions:"
        Write-Host " [A] Add User to a Group"
        Write-Host " [R] Remove User from a Group"
        Write-Host " [B] Back to Main Menu"
        
        $action = Read-Host "`nChoose an action [A, R, B]"

        switch ($action.ToUpper()) {
            "A" {
                $groupName = Read-Host "`nEnter the exact Group Name to add"
                if (-not [string]::IsNullOrWhiteSpace($groupName)) {
                    Add-ADGroupMember -Identity $groupName -Members $username -ErrorAction Stop
                    Write-Host "`n[SUCCESS] Added '$username' to group '$groupName'." -ForegroundColor Green
                }
            }
            "R" {
                $groupName = Read-Host "`nEnter the exact Group Name to remove"
                if (-not [string]::IsNullOrWhiteSpace($groupName)) {
                    Remove-ADGroupMember -Identity $groupName -Members $username -Confirm:$false -ErrorAction Stop
                    Write-Host "`n[SUCCESS] Removed '$username' from group '$groupName'." -ForegroundColor Green
                }
            }
            "B" {
                return
            }
            Default {
                Write-Warning "Invalid selection."
            }
        }
    }
    catch {
        Write-Host "`n[ERROR] Operation failed: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ""
    Pause
}

# ==========================================
# 4. REMOTE WORKSTATION DIAGNOSTIC FUNCTION
# ==========================================
function Test-WorkstationDiagnostic {
    Clear-Host
    Write-Host "--- WORKSTATION NETWORK & DNS DIAGNOSTIC TOOL ---" -ForegroundColor Cyan
    $target = Read-Host "Enter Target Computer Name or IP Address"
    if ([string]::IsNullOrWhiteSpace($target)) {
        Write-Warning "Target cannot be blank."
        Pause
        return
    }

    Write-Host "`nRunning diagnostics against: $target" -ForegroundColor Yellow
    Write-Host "--------------------------------------------------"

    # 1. ICMP Ping Reachability Test
    Write-Host "[1/3] Testing ICMP Reachability (Ping)..." -NoNewline
    $pingTest = Test-Connection -ComputerName $target -Count 2 -Quiet

    if ($pingTest) {
        Write-Host " [ONLINE]" -ForegroundColor Green
    } else {
        Write-Host " [OFFLINE / UNREACHABLE]" -ForegroundColor Red
    }

    # 2. DNS Resolution Verification
    Write-Host "[2/3] Resolving DNS Records..." -NoNewline
    try {
        $dnsRecord = Resolve-DnsName -Name $target -ErrorAction Stop | Select-Object -First 1
        $resolvedIP = if ($dnsRecord.IPAddress) { $dnsRecord.IPAddress } else { $dnsRecord.NameHost }
        Write-Host " [RESOLVED -> $resolvedIP]" -ForegroundColor Green
    }
    catch {
        Write-Host " [DNS RESOLUTION FAILED]" -ForegroundColor Red
    }

    # 3. System Uptime Query (via CIM/WMI)
    Write-Host "[3/3] Querying System Uptime & OS Information..."
    try {
        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $target -OperationTimeoutSec 3 -ErrorAction Stop
        $lastBoot = $osInfo.LastBootUpTime
        $uptime = (Get-Date) - $lastBoot

        Write-Host "  * OS Name   : $($osInfo.Caption)" -ForegroundColor Gray
        Write-Host "  * Last Boot : $lastBoot" -ForegroundColor Gray
        Write-Host "  * Uptime    : $($uptime.Days) Days, $($uptime.Hours) Hours, $($uptime.Minutes) Mins" -ForegroundColor Green
    }
    catch {
        Write-Host "  * [INFO] Remote WMI/CIM query unavailable (Remote host offline or WinRM firewalled)." -ForegroundColor DarkGray
    }

    Write-Host "--------------------------------------------------"
    Write-Host ""
    Pause
}

# ==========================================
# MAIN INTERACTIVE MENU LOOP
# ==========================================
function Show-MainMenu {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "       HELPDESK AUTOMATION TOOLKIT        " -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host " [1] Check Account Status & Unlock User"
    Write-Host " [2] Reset User Password"
    Write-Host " [3] View / Modify AD Group Memberships"
    Write-Host " [4] Remote Workstation Diagnostic (Ping/DNS)"
    Write-Host " [Q] Quit"
    Write-Host "==========================================" -ForegroundColor Cyan
}

# Main Execution Loop
do {
    Show-MainMenu
    $choice = Read-Host "Select an option [1-4, Q]"

    switch ($choice.ToUpper()) {
        "1" { 
            Check-UserStatusAndUnlock 
        }
        "2" { 
            Reset-UserPasswordTool 
        }
        "3" { 
            Manage-ADGroupMembership 
        }
        "4" { 
            Test-WorkstationDiagnostic 
        }
        "Q" { 
            Write-Host "`nExiting Toolkit. Goodbye!" -ForegroundColor Cyan
            Start-Sleep -Seconds 1
        }
        Default { 
            Write-Warning "Invalid choice. Please select 1-4 or Q."
            Start-Sleep -Seconds 2
        }
    }
} while ($choice.ToUpper() -ne "Q")
