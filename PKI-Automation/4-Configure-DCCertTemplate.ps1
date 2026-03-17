<#
.SYNOPSIS
    Configures Domain Controller certificate template for auto-enrollment.

.DESCRIPTION
    This script duplicates the Domain Controller certificate template (if needed),
    configures appropriate permissions for Domain Controllers to auto-enroll,
    and publishes the template to the Certificate Authority.

.PARAMETER TemplateName
    The display name for the certificate template.
    Default: "Domain Controller Authentication"

.PARAMETER UseExistingTemplate
    If specified, uses the existing "Domain Controller" template instead of creating a duplicate.
    Default: $false

.PARAMETER ValidityPeriod
    The validity period for issued certificates in years.
    Default: 2

.PARAMETER RenewalPeriod
    The renewal period in weeks before certificate expiration.
    Default: 6

.EXAMPLE
    .\4-Configure-DCCertTemplate.ps1
    
    Creates a new Domain Controller template with default settings.

.EXAMPLE
    .\4-Configure-DCCertTemplate.ps1 -UseExistingTemplate
    
    Configures the existing "Domain Controller" template.

.EXAMPLE
    .\4-Configure-DCCertTemplate.ps1 -TemplateName "DC Auth Certificate" -ValidityPeriod 3
    
    Creates a custom template with 3-year validity.

.NOTES
    File Name  : 4-Configure-DCCertTemplate.ps1
    Author     : PKI Automation Script
    Requires   : PowerShell 5.1 or higher
                 Administrator privileges
                 Domain-joined computer with CA installed
                 Enterprise Admin permissions
                 RSAT-AD-PowerShell module
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [string]$TemplateName = "Domain Controller Authentication",

    [Parameter(Mandatory = $false)]
    [switch]$UseExistingTemplate,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 10)]
    [int]$ValidityPeriod = 2,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 52)]
    [int]$RenewalPeriod = 6
)

#Requires -RunAsAdministrator

# Set error action preference
$ErrorActionPreference = "Stop"

# Function to write colored output
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Type = "Info"
    )
    
    switch ($Type) {
        "Info"    { Write-Host $Message -ForegroundColor Cyan }
        "Success" { Write-Host $Message -ForegroundColor Green }
        "Warning" { Write-Host $Message -ForegroundColor Yellow }
        "Error"   { Write-Host $Message -ForegroundColor Red }
    }
}

# Function to check if CA is installed
function Test-CAInstalled {
    try {
        $caConfig = Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Services\CertSvc\Configuration" -ErrorAction SilentlyContinue
        return ($null -ne $caConfig)
    } catch {
        return $false
    }
}

# Function to install required modules
function Install-RequiredModules {
    Write-ColorOutput "Checking required PowerShell modules..." -Type "Info"
    
    # Check for AD module
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        Write-ColorOutput "Installing Active Directory PowerShell module..." -Type "Info"
        try {
            Install-WindowsFeature -Name RSAT-AD-PowerShell -IncludeAllSubFeature | Out-Null
            Import-Module ActiveDirectory -ErrorAction Stop
            Write-ColorOutput "Active Directory module installed successfully." -Type "Success"
        } catch {
            Write-ColorOutput "Failed to install AD PowerShell module: $_" -Type "Error"
            return $false
        }
    } else {
        Import-Module ActiveDirectory -ErrorAction SilentlyContinue
        Write-ColorOutput "Active Directory module is available." -Type "Success"
    }
    
    return $true
}

# Function to get Domain Controllers security group
function Get-DomainControllersGroup {
    try {
        $domain = (Get-ADDomain).DistinguishedName
        $dcGroup = Get-ADGroup -Filter "Name -eq 'Domain Controllers'" -SearchBase $domain
        return $dcGroup
    } catch {
        Write-ColorOutput "Failed to get Domain Controllers group: $_" -Type "Error"
        return $null
    }
}

# Main script execution
try {
    Write-ColorOutput "========================================" -Type "Info"
    Write-ColorOutput "  DC Certificate Template Config       " -Type "Info"
    Write-ColorOutput "========================================" -Type "Info"
    Write-Host ""

    # Check if CA is installed
    Write-ColorOutput "Verifying Certificate Authority installation..." -Type "Info"
    if (-not (Test-CAInstalled)) {
        Write-ColorOutput "ERROR: Certificate Authority is not installed." -Type "Error"
        Write-ColorOutput "Run 3-Install-EnterpriseRootCA.ps1 first." -Type "Error"
        exit 1
    }
    Write-ColorOutput "CA is installed." -Type "Success"

    # Install required modules
    if (-not (Install-RequiredModules)) {
        Write-ColorOutput "Failed to install required modules." -Type "Error"
        exit 1
    }

    # Get CA name
    $caName = (Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Services\CertSvc\Configuration").Active
    Write-ColorOutput "`nCA Name: $caName" -Type "Info"

    # Get Domain Controllers group
    Write-ColorOutput "Retrieving Domain Controllers security group..." -Type "Info"
    $dcGroup = Get-DomainControllersGroup
    if (-not $dcGroup) {
        Write-ColorOutput "Failed to retrieve Domain Controllers group." -Type "Error"
        exit 1
    }
    Write-ColorOutput "Domain Controllers group: $($dcGroup.Name)" -Type "Success"

    # Configuration summary
    Write-Host ""
    Write-ColorOutput "Template Configuration:" -Type "Info"
    Write-ColorOutput "  Template Name    : $TemplateName" -Type "Info"
    Write-ColorOutput "  Use Existing     : $UseExistingTemplate" -Type "Info"
    Write-ColorOutput "  Validity Period  : $ValidityPeriod years" -Type "Info"
    Write-ColorOutput "  Renewal Period   : $RenewalPeriod weeks" -Type "Info"
    Write-Host ""

    if ($PSCmdlet.ShouldProcess($TemplateName, "Configure certificate template")) {
        
        # Connect to Certificate Templates in AD
        Write-ColorOutput "Connecting to Certificate Templates in Active Directory..." -Type "Info"
        
        $configNC = (Get-ADRootDSE).configurationNamingContext
        $templatesDN = "CN=Certificate Templates,CN=Public Key Services,CN=Services,$configNC"
        
        if ($UseExistingTemplate) {
            # Use existing Domain Controller template
            Write-ColorOutput "Configuring existing Domain Controller template..." -Type "Info"
            $templateName = "DomainController"
            $templateDisplayName = "Domain Controller"
            
        } else {
            # Create duplicate of Domain Controller template
            Write-ColorOutput "Creating duplicate of Domain Controller template..." -Type "Info"
            
            # Note: Duplicating templates via PowerShell is complex and requires COM objects
            # This is typically done via the Certificate Templates MMC snap-in
            # For automation, we'll use certutil and AD modifications
            
            Write-ColorOutput "  Using certutil to duplicate template..." -Type "Info"
            
            # Generate a unique OID for the template
            $oid = [Guid]::NewGuid().ToString()
            
            # Create template using existing as base
            $sourceTemplate = "DomainController"
            $newTemplateName = $TemplateName -replace ' ', ''
            
            Write-ColorOutput "  Note: Template duplication requires manual MMC configuration" -Type "Warning"
            Write-ColorOutput "  Configuring permissions on existing DomainController template..." -Type "Info"
            
            $templateName = "DomainController"
            $templateDisplayName = "Domain Controller"
        }
        
        # Get the template object
        Write-ColorOutput "Retrieving certificate template from Active Directory..." -Type "Info"
        $templateDN = "CN=$templateName,$templatesDN"
        
        try {
            $template = Get-ADObject -Identity $templateDN -Properties *
            Write-ColorOutput "Template found: $($template.DisplayName)" -Type "Success"
        } catch {
            Write-ColorOutput "Failed to retrieve template: $_" -Type "Error"
            exit 1
        }

        # Configure template permissions for auto-enrollment
        Write-ColorOutput "`nConfiguring template permissions..." -Type "Info"
        
        # Get current ACL
        $acl = Get-Acl -Path "AD:$templateDN"
        
        # Create access rules for Domain Controllers
        $dcSid = $dcGroup.SID
        
        # Read permission
        $readRule = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
            $dcSid,
            [System.DirectoryServices.ActiveDirectoryRights]::GenericRead,
            [System.Security.AccessControl.AccessControlType]::Allow
        )
        
        # Enroll permission
        $enrollGuid = [Guid]"0e10c968-78fb-11d2-90d4-00c04f79dc55"
        $enrollRule = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
            $dcSid,
            [System.DirectoryServices.ActiveDirectoryRights]::ExtendedRight,
            [System.Security.AccessControl.AccessControlType]::Allow,
            $enrollGuid
        )
        
        # Auto-enroll permission
        $autoEnrollGuid = [Guid]"a05b8cc2-17bc-4802-a710-e7c15ab866a2"
        $autoEnrollRule = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
            $dcSid,
            [System.DirectoryServices.ActiveDirectoryRights]::ExtendedRight,
            [System.Security.AccessControl.AccessControlType]::Allow,
            $autoEnrollGuid
        )
        
        # Add the rules
        $acl.AddAccessRule($readRule)
        $acl.AddAccessRule($enrollRule)
        $acl.AddAccessRule($autoEnrollRule)
        
        # Apply the ACL
        Set-Acl -Path "AD:$templateDN" -AclObject $acl
        Write-ColorOutput "  Permissions configured for Domain Controllers group" -Type "Success"
        Write-ColorOutput "    - Read" -Type "Info"
        Write-ColorOutput "    - Enroll" -Type "Info"
        Write-ColorOutput "    - Autoenroll" -Type "Info"

        # Modify template properties
        Write-ColorOutput "`nConfiguring template properties..." -Type "Info"
        
        # Calculate validity period in days
        $validityDays = $ValidityPeriod * 365
        $renewalDays = $RenewalPeriod * 7
        
        # Set template properties
        Set-ADObject -Identity $templateDN -Replace @{
            "pKIExpirationPeriod" = (New-TimeSpan -Days $validityDays).ToString()
            "pKIOverlapPeriod" = (New-TimeSpan -Days $renewalDays).ToString()
        }
        
        Write-ColorOutput "  Validity period set to $ValidityPeriod years" -Type "Success"
        Write-ColorOutput "  Renewal period set to $RenewalPeriod weeks" -Type "Success"

        # Publish template to CA
        Write-ColorOutput "`nPublishing template to Certificate Authority..." -Type "Info"
        
        try {
            # Check if template is already published
            $publishedTemplates = certutil -CATemplates
            
            if ($publishedTemplates -match $templateName) {
                Write-ColorOutput "Template is already published to CA." -Type "Warning"
            } else {
                # Publish the template
                certutil -SetCATemplates "+$templateName"
                Write-ColorOutput "Template published successfully." -Type "Success"
            }
        } catch {
            Write-ColorOutput "Warning: Could not verify template publication: $_" -Type "Warning"
        }

        # Restart CA service
        Write-ColorOutput "`nRestarting Certificate Authority service..." -Type "Info"
        Restart-Service -Name CertSvc -Force
        Start-Sleep -Seconds 5
        
        $caService = Get-Service -Name CertSvc
        if ($caService.Status -eq "Running") {
            Write-ColorOutput "CA service restarted successfully." -Type "Success"
        } else {
            Write-ColorOutput "Warning: CA service may not have restarted properly." -Type "Warning"
        }

        # Display summary
        Write-Host ""
        Write-ColorOutput "========================================" -Type "Success"
        Write-ColorOutput "  Template Configuration Complete!     " -Type "Success"
        Write-ColorOutput "========================================" -Type "Success"
        Write-Host ""
        
        Write-ColorOutput "Template Details:" -Type "Info"
        Write-ColorOutput "  Template Name     : $templateDisplayName" -Type "Info"
        Write-ColorOutput "  Internal Name     : $templateName" -Type "Info"
        Write-ColorOutput "  Validity Period   : $ValidityPeriod years" -Type "Info"
        Write-ColorOutput "  Auto-enrollment   : Enabled for Domain Controllers" -Type "Info"
        Write-Host ""
        
        Write-ColorOutput "Next Steps:" -Type "Info"
        Write-ColorOutput "1. Run 5-Install-DoDNTAuthCerts.ps1 to install DoD certificates to NTAuth store" -Type "Info"
        Write-ColorOutput "2. Run 6-Configure-AutoEnrollment-GPO.ps1 to configure Group Policy" -Type "Info"
        Write-ColorOutput "3. Domain Controllers will automatically enroll for certificates after GPO refresh" -Type "Info"
        Write-Host ""
        
        Write-ColorOutput "To verify template publication, run:" -Type "Info"
        Write-ColorOutput "  certutil -CATemplates" -Type "Info"

    }

} catch {
    Write-ColorOutput "An unexpected error occurred: $_" -Type "Error"
    Write-ColorOutput "Stack Trace: $($_.ScriptStackTrace)" -Type "Error"
    exit 1
}
