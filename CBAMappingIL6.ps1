<#
.SYNOPSIS
    Maps a smart card certificate's Principal Name to an Entra ID user's certificateUserIds attribute.

.DESCRIPTION
    This script reads the Principal Name from a certificate's Subject Alternate Name on a smart card device, formats it according to Entra ID requirements,
    and updates a cloud-only Entra ID user account's AuthorizationInfo.CertificateUserIDs attribute. The script allows 
    searching for users by UserPrincipalName and handles duplicate checking before adding the mapping.

.NOTES
    Requirements:
    - Microsoft.Graph PowerShell module (Microsoft.Graph.Users)
    - Permissions: User.ReadWrite.All
    - Smart card with certificate installed
#>

#Requires -Modules Microsoft.Graph.Users

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
    return $true
}

function Connect-ToMicrosoftGraph {
    <#
    .SYNOPSIS
        Connects to Microsoft Graph with required permissions.
    #>
    Write-Host "`n=== Connecting to Microsoft Graph ===" -ForegroundColor Cyan
    
    try {
        # Check if already connected
        $context = Get-MgContext
        if ($context) {
            Write-Host "[OK] Already connected to Microsoft Graph" -ForegroundColor Green
            Write-Host "    Account: $($context.Account)" -ForegroundColor Gray
            Write-Host "    Tenant: $($context.TenantId)" -ForegroundColor Gray
            
            # Verify User.ReadWrite.All scope
            if ($context.Scopes -notcontains "User.ReadWrite.All") {
                Write-Warning "Current connection may not have User.ReadWrite.All scope. Reconnecting..."
                Disconnect-MgGraph | Out-Null
                Connect-MgGraph -Environment USGov -Scopes "User.ReadWrite.All" -NoWelcome
            }
        }
        else {
            Connect-MgGraph -Environment USGov -Scopes "User.ReadWrite.All" -NoWelcome
            Write-Host "[OK] Connected to Microsoft Graph" -ForegroundColor Green
        }
        return $true
    }
    catch {
        Write-Error "Failed to connect to Microsoft Graph: $_"
        return $false
    }
}

function Get-SmartCardCertificates {
    <#
    .SYNOPSIS
        Retrieves DoD certificates from the current user's certificate store.
    .OUTPUTS
        Array of certificate objects
    #>
    Write-Host "`n=== Retrieving Certificates ===" -ForegroundColor Cyan
    
    try {
        $certificates = Get-ChildItem -Path Cert:\CurrentUser\My | Where-Object { 
            $_.HasPrivateKey -and `
            $_.Issuer -like "*DOD*" -and `
            $_.Issuer -notlike "*DOD EMAIL*" -and `
            $_.Subject -like "CN=*"
        }
        
        if ($certificates.Count -eq 0) {
            Write-Warning "No DoD certificates with private keys found in the Current User store."
            return $null
        }
        
        Write-Host "[OK] Found $($certificates.Count) DoD certificate(s) with private keys" -ForegroundColor Green
        return $certificates
    }
    catch {
        Write-Error "Failed to retrieve certificates: $_"
        return $null
    }
}

function Show-CertificateMenu {
    <#
    .SYNOPSIS
        Displays a menu of certificates and allows user selection.
    .PARAMETER Certificates
        Array of certificate objects to display
    .OUTPUTS
        Selected certificate object
    #>
    param (
        [Parameter(Mandatory = $true)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2[]]$Certificates
    )
    
    Write-Host "`n=== Select Certificate ===" -ForegroundColor Cyan
    
    for ($i = 0; $i -lt $Certificates.Count; $i++) {
        $cert = $Certificates[$i]
        Write-Host "`n[$($i + 1)] " -ForegroundColor Yellow -NoNewline
        Write-Host "Certificate Details:"
        Write-Host "    Subject    : $($cert.Subject)" -ForegroundColor Gray
        Write-Host "    Issuer     : $($cert.Issuer)" -ForegroundColor Gray
        Write-Host "    Thumbprint : $($cert.Thumbprint)" -ForegroundColor Gray
        Write-Host "    Expires    : $($cert.NotAfter.ToString('yyyy-MM-dd'))" -ForegroundColor Gray
    }
    
    do {
        Write-Host "`nEnter certificate number (1-$($Certificates.Count)): " -ForegroundColor Cyan -NoNewline
        $selection = Read-Host
        
        if ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $Certificates.Count) {
            $selectedCert = $Certificates[[int]$selection - 1]
            Write-Host "[OK] Selected certificate: $($selectedCert.Subject)" -ForegroundColor Green
            return $selectedCert
        }
        else {
            Write-Warning "Invalid selection. Please enter a number between 1 and $($Certificates.Count)."
        }
    } while ($true)
}

function Get-CertificatePrincipalName {
    <#
    .SYNOPSIS
        Extracts the Principal Name from a certificate's Subject Alternate Name extension.
    .PARAMETER Certificate
        The certificate object to extract Principal Name from
    .OUTPUTS
        String containing the Principal Name
    #>
    param (
        [Parameter(Mandatory = $true)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
    )
    
    Write-Host "`n=== Extracting Principal Name from Subject Alternate Name ===" -ForegroundColor Cyan
    
    try {
        # Find the Subject Alternative Name extension
        $sanExtension = $Certificate.Extensions | Where-Object { 
            $_.Oid.Value -eq "2.5.29.17"  # Subject Alternative Name OID
        }
        
        if (-not $sanExtension) {
            Write-Error "Certificate does not contain a Subject Alternate Name extension."
            return $null
        }
        
        # Decode the SAN extension
        $san = New-Object System.Security.Cryptography.AsnEncodedData($sanExtension.Oid, $sanExtension.RawData)
        $sanString = $san.Format($false)
        
        # Look for Principal Name (typically shown as "Other Name:")
        # Principal Name OID is 1.3.6.1.4.1.311.20.2.3
        $principalName = $null
        
        # Try to extract from the formatted string
        if ($sanString -match "Principal Name=([^,\r\n]+)") {
            $principalName = $matches[1].Trim()
        }
        elseif ($sanString -match "Other Name:([^,\r\n]+)") {
            # Sometimes it appears as "Other Name"
            $principalName = $matches[1].Trim()
        }
        
        if (-not $principalName) {
            Write-Error "Could not find Principal Name in Subject Alternate Name extension."
            Write-Host "SAN Content: $sanString" -ForegroundColor Gray
            return $null
        }
        
        Write-Host "[OK] Extracted Principal Name: $principalName" -ForegroundColor Green
        return $principalName
    }
    catch {
        Write-Error "Failed to extract Principal Name: $_"
        return $null
    }
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
                return $exactMatch
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
                return $users
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
                        return $selectedUser
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

# ============================================
# MAIN SCRIPT EXECUTION
# ============================================

Write-Host "************************************************************" -ForegroundColor Cyan
Write-Host "*  Certificate-Based Authentication Mapping Tool          *" -ForegroundColor Cyan
Write-Host "*  Maps Smart Card Certificate PN to Entra ID User        *" -ForegroundColor Cyan
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

# Step 3: Get certificates
$certificates = Get-SmartCardCertificates
if (-not $certificates) {
    Write-Host "`n[FAILED] No certificates found. Exiting..." -ForegroundColor Red
    exit 1
}

# Step 4: Select certificate
$selectedCertificate = Show-CertificateMenu -Certificates $certificates
if (-not $selectedCertificate) {
    Write-Host "`n[FAILED] No certificate selected. Exiting..." -ForegroundColor Red
    exit 1
}

# Step 5: Extract Principal Name
$principalName = Get-CertificatePrincipalName -Certificate $selectedCertificate
if (-not $principalName) {
    Write-Host "`n[FAILED] Could not extract Principal Name. Exiting..." -ForegroundColor Red
    exit 1
}

# Step 6: Format Principal Name
$formattedPN = Format-PrincipalNameForEntraID -PrincipalName $principalName
if (-not $formattedPN) {
    Write-Host "`n[FAILED] Could not format Principal Name. Exiting..." -ForegroundColor Red
    exit 1
}

# Step 7: Search for user
$targetUser = Search-EntraIDUser
if (-not $targetUser) {
    Write-Host "`n[FAILED] No user selected. Exiting..." -ForegroundColor Red
    exit 1
}

# Step 8: Update user certificate mapping
$success = Update-UserCertificateMapping -UserId $targetUser.Id -FormattedPN $formattedPN

# Final summary
Write-Host "`n************************************************************" -ForegroundColor Cyan
Write-Host "*  SUMMARY                                                 *" -ForegroundColor Cyan
Write-Host "************************************************************" -ForegroundColor Cyan
Write-Host "Certificate: $($selectedCertificate.Subject)" -ForegroundColor Gray
Write-Host "User       : $($targetUser.UserPrincipalName)" -ForegroundColor Gray
Write-Host "PN Mapping : $formattedPN" -ForegroundColor Gray

if ($success) {
    Write-Host "`n[SUCCESS] Certificate mapping completed successfully!" -ForegroundColor Green
}
else {
    Write-Host "`n[FAILED] Certificate mapping failed." -ForegroundColor Red
    exit 1
}

Write-Host ""
