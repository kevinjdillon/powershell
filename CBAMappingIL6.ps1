<#
.SYNOPSIS
    Maps a certificate's Principal Name to an Entra ID user's certificateUserIds attribute and adds user to CBA Test group.

.DESCRIPTION
    This script prompts the user to manually enter a certificate's Principal Name, formats it according to Entra ID requirements,
    and updates a cloud-only Entra ID user account's AuthorizationInfo.CertificateUserIDs attribute. If the certificate mapping
    is successful, the script also adds the user to the "CBA Test" Entra security group.

.NOTES
    Requirements:
    - Microsoft.Graph PowerShell module (Microsoft.Graph.Users, Microsoft.Graph.Groups)
    - Permissions: User.ReadWrite.All, GroupMember.ReadWrite.All
    - IL6 updates: -Environment USGovDoD
#>

#Requires -Modules Microsoft.Graph.Users, Microsoft.Graph.Groups

function Test-Prerequisites {
    <#
    .SYNOPSIS
        Validates that required modules are installed and Graph connection is established.
    #>
    Write-Host "`n=== Checking Prerequisites ===" -ForegroundColor Cyan
    
    # Check for Microsoft.Graph.Users module
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Users)) {
        Write-Error "Microsoft.Graph.Users module is not installed. Install it using: Install-Module Microsoft.Graph.Users"
        return $false
    }
    
    Write-Host "[OK] Microsoft.Graph.Users module is installed" -ForegroundColor Green
    
    # Check for Microsoft.Graph.Groups module
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Groups)) {
        Write-Error "Microsoft.Graph.Groups module is not installed. Install it using: Install-Module Microsoft.Graph.Groups"
        return $false
    }
    
    Write-Host "[OK] Microsoft.Graph.Groups module is installed" -ForegroundColor Green
    return $true
}

function Connect-ToMicrosoftGraph {
    <#
    .SYNOPSIS
        Connects to Microsoft Graph with required permissions.
    #>
    Write-Host "`n=== Connecting to Microsoft Graph ===" -ForegroundColor Cyan
    
    try {
        $requiredScopes = @("User.ReadWrite.All", "GroupMember.ReadWrite.All")
        
        # Check if already connected
        $context = Get-MgContext
        if ($context) {
            Write-Host "[OK] Already connected to Microsoft Graph" -ForegroundColor Green
            Write-Host "    Account: $($context.Account)" -ForegroundColor Gray
            Write-Host "    Tenant: $($context.TenantId)" -ForegroundColor Gray
            
            # Verify required scopes
            $missingScopes = $requiredScopes | Where-Object { $context.Scopes -notcontains $_ }
            if ($missingScopes) {
                Write-Warning "Current connection is missing required scopes: $($missingScopes -join ', '). Reconnecting..."
                Disconnect-MgGraph | Out-Null
                Connect-MgGraph -Environment USGov -Scopes $requiredScopes -NoWelcome
            }
        }
        else {
            Connect-MgGraph -Environment USGov -Scopes $requiredScopes -NoWelcome
            Write-Host "[OK] Connected to Microsoft Graph" -ForegroundColor Green
        }
        return $true
    }
    catch {
        Write-Error "Failed to connect to Microsoft Graph: $_"
        return $false
    }
}

function Get-ManualPrincipalName {
    <#
    .SYNOPSIS
        Prompts the user to manually enter the certificate's Principal Name.
    .OUTPUTS
        String containing the Principal Name
    #>
    Write-Host "`n=== Enter Certificate Principal Name ===" -ForegroundColor Cyan
    Write-Host "Please enter the Principal Name value from the certificate." -ForegroundColor Gray
    Write-Host "Example format: 1234567890@mil" -ForegroundColor Gray
    
    do {
        Write-Host "`nPrincipal Name: " -ForegroundColor Cyan -NoNewline
        $principalName = Read-Host
        
        if ([string]::IsNullOrWhiteSpace($principalName)) {
            Write-Warning "Principal Name cannot be empty. Please try again."
            continue
        }
        
        # Basic validation - ensure it's not just whitespace and has reasonable length
        $principalName = $principalName.Trim()
        if ($principalName.Length -lt 3) {
            Write-Warning "Principal Name seems too short. Please verify and try again."
            continue
        }
        
        Write-Host "[OK] Principal Name entered: $principalName" -ForegroundColor Green
        return $principalName
    } while ($true)
}

function Format-PrincipalNameForEntraID {
    <#
    .SYNOPSIS
        Formats the Principal Name into the Entra ID certificateUserIds format.
    .PARAMETER PrincipalName
        String containing the Principal Name
    .OUTPUTS
        Formatted string in the format "X509:<PN>xxxx"
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$PrincipalName
    )
    
    Write-Host "`n=== Formatting Principal Name for Entra ID ===" -ForegroundColor Cyan
    
    try {
        # Format as X509:<PN>principalname
        $formattedPN = "X509:<PN>$PrincipalName"
        
        Write-Host "[OK] Formatted Principal Name: $formattedPN" -ForegroundColor Green
        return $formattedPN
    }
    catch {
        Write-Error "Failed to format Principal Name: $_"
        return $null
    }
}

function Search-EntraIDUser {
    <#
    .SYNOPSIS
        Searches for an Entra ID user by UserPrincipalName.
    .OUTPUTS
        Selected user object
    #>
    Write-Host "`n=== Search for Entra ID User ===" -ForegroundColor Cyan
    
    do {
        Write-Host "`nEnter UserPrincipalName (or partial UPN to search): " -ForegroundColor Cyan -NoNewline
        $searchTerm = Read-Host
        
        if ([string]::IsNullOrWhiteSpace($searchTerm)) {
            Write-Warning "Search term cannot be empty."
            continue
        }
        
        try {
            # First try exact match
            $exactMatch = Get-MgUser -UserId $searchTerm -ErrorAction SilentlyContinue
            
            if ($exactMatch) {
                Write-Host "[OK] Found exact match: $($exactMatch.UserPrincipalName)" -ForegroundColor Green
                
                # Confirm selection
                Write-Host "`n=== Confirm User Selection ===" -ForegroundColor Yellow
                Write-Host "UserPrincipalName: $($exactMatch.UserPrincipalName)" -ForegroundColor Cyan
                Write-Host "Display Name     : $($exactMatch.DisplayName)" -ForegroundColor Cyan
                Write-Host "`nIs this the correct account? (Y/N): " -ForegroundColor Yellow -NoNewline
                $confirm = Read-Host
                
                if ($confirm -eq 'Y' -or $confirm -eq 'y') {
                    Write-Host "[OK] User confirmed" -ForegroundColor Green
                    return $exactMatch
                }
                else {
                    Write-Host "User not confirmed. Please search again." -ForegroundColor Gray
                    continue
                }
            }
            
            # If no exact match, try startswith filter
            Write-Host "Searching for users with UPN starting with '$searchTerm'..." -ForegroundColor Gray
            $users = Get-MgUser -Filter "startswith(userPrincipalName,'$searchTerm')" -All
            
            if ($users.Count -eq 0) {
                Write-Warning "No users found matching '$searchTerm'."
                Write-Host "Try again? (Y/N): " -ForegroundColor Cyan -NoNewline
                $retry = Read-Host
                if ($retry -ne 'Y' -and $retry -ne 'y') {
                    return $null
                }
                continue
            }
            elseif ($users.Count -eq 1) {
                Write-Host "[OK] Found 1 user: $($users.UserPrincipalName)" -ForegroundColor Green
                
                # Confirm selection
                Write-Host "`n=== Confirm User Selection ===" -ForegroundColor Yellow
                Write-Host "UserPrincipalName: $($users.UserPrincipalName)" -ForegroundColor Cyan
                Write-Host "Display Name     : $($users.DisplayName)" -ForegroundColor Cyan
                Write-Host "`nIs this the correct account? (Y/N): " -ForegroundColor Yellow -NoNewline
                $confirm = Read-Host
                
                if ($confirm -eq 'Y' -or $confirm -eq 'y') {
                    Write-Host "[OK] User confirmed" -ForegroundColor Green
                    return $users
                }
                else {
                    Write-Host "User not confirmed. Please search again." -ForegroundColor Gray
                    continue
                }
            }
            else {
                # Multiple matches - show selection menu
                Write-Host "`nFound $($users.Count) matching users:" -ForegroundColor Yellow
                
                for ($i = 0; $i -lt $users.Count; $i++) {
                    Write-Host "[$($i + 1)] $($users[$i].UserPrincipalName) - $($users[$i].DisplayName)" -ForegroundColor Gray
                }
                
                do {
                    Write-Host "`nEnter user number (1-$($users.Count)) or 0 to search again: " -ForegroundColor Cyan -NoNewline
                    $selection = Read-Host
                    
                    if ($selection -eq '0') {
                        break
                    }
                    
                    if ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $users.Count) {
                        $selectedUser = $users[[int]$selection - 1]
                        Write-Host "[OK] Selected user: $($selectedUser.UserPrincipalName)" -ForegroundColor Green
                        
                        # Confirm selection
                        Write-Host "`n=== Confirm User Selection ===" -ForegroundColor Yellow
                        Write-Host "UserPrincipalName: $($selectedUser.UserPrincipalName)" -ForegroundColor Cyan
                        Write-Host "Display Name     : $($selectedUser.DisplayName)" -ForegroundColor Cyan
                        Write-Host "`nIs this the correct account? (Y/N): " -ForegroundColor Yellow -NoNewline
                        $confirm = Read-Host
                        
                        if ($confirm -eq 'Y' -or $confirm -eq 'y') {
                            Write-Host "[OK] User confirmed" -ForegroundColor Green
                            return $selectedUser
                        }
                        else {
                            Write-Host "User not confirmed. Returning to search." -ForegroundColor Gray
                            break
                        }
                    }
                    else {
                        Write-Warning "Invalid selection."
                    }
                } while ($true)
            }
        }
        catch {
            Write-Error "Error searching for users: $_"
            return $null
        }
    } while ($true)
}

function Update-UserCertificateMapping {
    <#
    .SYNOPSIS
        Updates the user's certificateUserIds attribute with the formatted Principal Name.
    .PARAMETER UserId
        The user's ID or UserPrincipalName
    .PARAMETER FormattedPN
        The formatted Principal Name string
    .OUTPUTS
        Boolean indicating success
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$UserId,
        
        [Parameter(Mandatory = $true)]
        [string]$FormattedPN
    )
    
    Write-Host "`n=== Updating User Certificate Mapping ===" -ForegroundColor Cyan
    
    try {
        # Get current certificateUserIds from AuthorizationInfo
        $userInfo = Get-MgUser -UserId $UserId -Property AuthorizationInfo -ErrorAction Stop
        
        $currentMappings = @()
        if ($userInfo.AuthorizationInfo.certificateUserIds) {
            $currentMappings = @($userInfo.AuthorizationInfo.certificateUserIds)
            Write-Host "Current certificate mappings: $($currentMappings.Count)" -ForegroundColor Gray
            $currentMappings | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
        }
        else {
            Write-Host "No existing certificate mappings found." -ForegroundColor Gray
        }
        
        # Check for duplicate
        if ($currentMappings -contains $FormattedPN) {
            Write-Warning "The Principal Name mapping already exists for this user. No update needed."
            return $true
        }
        
        # Add new mapping to existing ones
        $updatedMappings = $currentMappings + $FormattedPN
        
        # Update user authorization info with new certificate mappings
        Write-Host "Adding new certificate mapping..." -ForegroundColor Gray
        
        $userInfo.AuthorizationInfo.certificateUserIds = $updatedMappings
        Update-MgUser -UserId $UserId -AuthorizationInfo $userInfo.AuthorizationInfo -ErrorAction Stop
        
        Write-Host "[OK] Successfully updated certificateUserIds" -ForegroundColor Green
        Write-Host "    Added: $FormattedPN" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Failed to update user certificate mapping: $_"
        return $false
    }
}

function Add-UserToEntraGroup {
    <#
    .SYNOPSIS
        Adds the user to the "CBA Test" Entra security group.
    .PARAMETER UserId
        The user's ID
    .OUTPUTS
        Boolean indicating success
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$UserId
    )
    
    Write-Host "`n=== Adding User to CBA Test Group ===" -ForegroundColor Cyan
    
    try {
        # Search for the group by display name
        Write-Host "Searching for 'CBA Test' group..." -ForegroundColor Gray
        $group = Get-MgGroup -Filter "displayName eq 'CBA Test'" -ErrorAction Stop
        
        if (-not $group) {
            Write-Error "Could not find 'CBA Test' group. Please verify the group exists."
            return $false
        }
        
        if ($group.Count -gt 1) {
            Write-Warning "Multiple groups found with name 'CBA Test'. Using the first one."
            $group = $group[0]
        }
        
        Write-Host "[OK] Found group: $($group.DisplayName) (ID: $($group.Id))" -ForegroundColor Green
        
        # Check if user is already a member
        Write-Host "Checking current group membership..." -ForegroundColor Gray
        $members = Get-MgGroupMember -GroupId $group.Id -All -ErrorAction Stop
        
        if ($members.Id -contains $UserId) {
            Write-Host "[OK] User is already a member of 'CBA Test' group. No action needed." -ForegroundColor Green
            return $true
        }
        
        # Add user to group
        Write-Host "Adding user to group..." -ForegroundColor Gray
        New-MgGroupMember -GroupId $group.Id -DirectoryObjectId $UserId -ErrorAction Stop
        
        Write-Host "[OK] Successfully added user to 'CBA Test' group" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Failed to add user to group: $_"
        return $false
    }
}

# ============================================
# MAIN SCRIPT EXECUTION
# ============================================

Write-Host "************************************************************" -ForegroundColor Cyan
Write-Host "*  Certificate-Based Authentication Mapping Tool          *" -ForegroundColor Cyan
Write-Host "*  Maps Certificate PN to Entra ID User & Adds to Group   *" -ForegroundColor Cyan
Write-Host "************************************************************" -ForegroundColor Cyan

# Step 1: Check prerequisites
if (-not (Test-Prerequisites)) {
    Write-Host "`n[FAILED] Prerequisites check failed. Exiting..." -ForegroundColor Red
    exit 1
}

# Step 2: Connect to Microsoft Graph
if (-not (Connect-ToMicrosoftGraph)) {
    Write-Host "`n[FAILED] Could not connect to Microsoft Graph. Exiting..." -ForegroundColor Red
    exit 1
}

# Step 3: Get Principal Name from user input
$principalName = Get-ManualPrincipalName
if (-not $principalName) {
    Write-Host "`n[FAILED] No Principal Name provided. Exiting..." -ForegroundColor Red
    exit 1
}

# Step 4: Format Principal Name
$formattedPN = Format-PrincipalNameForEntraID -PrincipalName $principalName
if (-not $formattedPN) {
    Write-Host "`n[FAILED] Could not format Principal Name. Exiting..." -ForegroundColor Red
    exit 1
}

# Step 5: Search for user
$targetUser = Search-EntraIDUser
if (-not $targetUser) {
    Write-Host "`n[FAILED] No user selected. Exiting..." -ForegroundColor Red
    exit 1
}

# Step 6: Update user certificate mapping
$mappingSuccess = Update-UserCertificateMapping -UserId $targetUser.Id -FormattedPN $formattedPN

# Step 7: Add user to CBA Test group (only if mapping was successful)
$groupSuccess = $false
if ($mappingSuccess) {
    $groupSuccess = Add-UserToEntraGroup -UserId $targetUser.Id
}
else {
    Write-Host "`n[SKIPPED] User will not be added to 'CBA Test' group due to certificate mapping failure." -ForegroundColor Yellow
}

# Final summary
Write-Host "`n************************************************************" -ForegroundColor Cyan
Write-Host "*  SUMMARY                                                 *" -ForegroundColor Cyan
Write-Host "************************************************************" -ForegroundColor Cyan
Write-Host "User             : $($targetUser.UserPrincipalName)" -ForegroundColor Gray
Write-Host "PN Mapping       : $formattedPN" -ForegroundColor Gray
Write-Host "Mapping Status   : $(if ($mappingSuccess) { 'SUCCESS' } else { 'FAILED' })" -ForegroundColor $(if ($mappingSuccess) { 'Green' } else { 'Red' })
Write-Host "Group Membership : $(if ($groupSuccess) { 'ADDED' } elseif ($mappingSuccess) { 'FAILED' } else { 'SKIPPED' })" -ForegroundColor $(if ($groupSuccess) { 'Green' } elseif ($mappingSuccess) { 'Red' } else { 'Yellow' })

if ($mappingSuccess -and $groupSuccess) {
    Write-Host "`n[SUCCESS] Certificate mapping and group membership completed successfully!" -ForegroundColor Green
}
elseif ($mappingSuccess -and -not $groupSuccess) {
    Write-Host "`n[PARTIAL SUCCESS] Certificate mapping completed but group membership failed." -ForegroundColor Yellow
}
else {
    Write-Host "`n[FAILED] Certificate mapping failed." -ForegroundColor Red
    exit 1
}

Write-Host ""