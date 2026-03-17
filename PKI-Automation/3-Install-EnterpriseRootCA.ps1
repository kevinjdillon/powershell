<#
.SYNOPSIS
    Installs and configures an Enterprise Root Certificate Authority.

.DESCRIPTION
    This script installs the Active Directory Certificate Services (AD CS) role
    and configures it as an Enterprise Root CA. It sets up the CA with appropriate
    settings for a DoD PKI environment including CRL distribution points and
    AIA (Authority Information Access) locations.

.PARAMETER CACommonName
    The common name for the Certificate Authority.
    Default: "Enterprise Root CA"

.PARAMETER CADistinguishedNameSuffix
    The distinguished name suffix for the CA.
    Example: "DC=contoso,DC=com"

.PARAMETER ValidityPeriod
    The validity period for the CA certificate.
    Default: "Years"

.PARAMETER ValidityPeriodUnits
    The number of validity period units.
    Default: 20

.PARAMETER CryptoProviderName
    The cryptographic provider to use.
    Default: "RSA#Microsoft Software Key Storage Provider"

.PARAMETER KeyLength
    The key length in bits.
    Default: 4096

.PARAMETER HashAlgorithm
    The hash algorithm to use.
    Default: "SHA256"

.PARAMETER DatabasePath
    Path for the CA database.
    Default: "C:\Windows\System32\CertLog"

.PARAMETER LogPath
    Path for the CA log files.
    Default: "C:\Windows\System32\CertLog"

.EXAMPLE
    .\3-Install-EnterpriseRootCA.ps1
    
    Installs Enterprise Root CA with default settings.

.EXAMPLE
    .\3-Install-EnterpriseRootCA.ps1 -CACommonName "DoD Root CA" -ValidityPeriodUnits 25 -KeyLength 4096
    
    Installs with custom CA name, 25-year validity, and 4096-bit key.

.NOTES
    File Name  : 3-Install-EnterpriseRootCA.ps1
    Author     : PKI Automation Script
    Requires   : PowerShell 5.1 or higher
                 Administrator privileges
                 Domain-joined computer
                 Enterprise Admin or Domain Admin credentials
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [string]$CACommonName = "Enterprise Root CA",

    [Parameter(Mandatory = $false)]
    [string]$CADistinguishedNameSuffix,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Years", "Months", "Weeks", "Days")]
    [string]$ValidityPeriod = "Years",

    [Parameter(Mandatory = $false)]
    [int]$ValidityPeriodUnits = 20,

    [Parameter(Mandatory = $false)]
    [string]$CryptoProviderName = "RSA#Microsoft Software Key Storage Provider",

    [Parameter(Mandatory = $false)]
    [ValidateSet(2048, 4096)]
    [int]$KeyLength = 4096,

    [Parameter(Mandatory = $false)]
    [ValidateSet("SHA256", "SHA384", "SHA512")]
    [string]$HashAlgorithm = "SHA256",

    [Parameter(Mandatory = $false)]
    [string]$DatabasePath = "C:\Windows\System32\CertLog",

    [Parameter(Mandatory = $false)]
    [string]$LogPath = "C:\Windows\System32\CertLog"
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

# Function to check if computer is domain-joined
function Test-DomainMembership {
    try {
        $computerSystem = Get-WmiObject -Class Win32_ComputerSystem
        return $computerSystem.PartOfDomain
    } catch {
        return $false
    }
}

# Function to check if CA is already installed
function Test-CAInstalled {
    try {
        $caConfig = Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Services\CertSvc\Configuration" -ErrorAction SilentlyContinue
        return ($null -ne $caConfig)
    } catch {
        return $false
    }
}

# Function to install Windows features
function Install-CAFeatures {
    Write-ColorOutput "Installing AD CS role and management tools..." -Type "Info"
    
    try {
        $features = @(
            "ADCS-Cert-Authority",
            "RSAT-ADCS",
            "RSAT-ADCS-Mgmt"
        )
        
        foreach ($feature in $features) {
            $installed = Get-WindowsFeature -Name $feature
            if (-not $installed.Installed) {
                Write-ColorOutput "  Installing: $feature" -Type "Info"
                Install-WindowsFeature -Name $feature -IncludeManagementTools | Out-Null
            } else {
                Write-ColorOutput "  Already installed: $feature" -Type "Warning"
            }
        }
        
        Write-ColorOutput "Feature installation completed." -Type "Success"
        return $true
    } catch {
        Write-ColorOutput "Failed to install features: $_" -Type "Error"
        return $false
    }
}

# Main script execution
try {
    Write-ColorOutput "========================================" -Type "Info"
    Write-ColorOutput "  Enterprise Root CA Installation      " -Type "Info"
    Write-ColorOutput "========================================" -Type "Info"
    Write-Host ""

    # Check if domain-joined
    Write-ColorOutput "Checking domain membership..." -Type "Info"
    if (-not (Test-DomainMembership)) {
        Write-ColorOutput "ERROR: This computer is not domain-joined." -Type "Error"
        Write-ColorOutput "Enterprise CA requires domain membership." -Type "Error"
        Write-ColorOutput "Run 1-Join-Domain.ps1 first." -Type "Error"
        exit 1
    }
    
    $domain = (Get-WmiObject -Class Win32_ComputerSystem).Domain
    Write-ColorOutput "Domain: $domain" -Type "Success"

    # Auto-detect DN suffix if not provided
    if (-not $CADistinguishedNameSuffix) {
        $domainParts = $domain.Split('.')
        $CADistinguishedNameSuffix = ($domainParts | ForEach-Object { "DC=$_" }) -join ','
        Write-ColorOutput "Auto-detected DN suffix: $CADistinguishedNameSuffix" -Type "Info"
    }

    # Check if CA is already installed
    Write-ColorOutput "`nChecking for existing CA installation..." -Type "Info"
    if (Test-CAInstalled) {
        Write-ColorOutput "WARNING: Certificate Authority is already installed." -Type "Warning"
        Write-ColorOutput "To reconfigure, you must first uninstall the existing CA." -Type "Warning"
        
        $proceed = Read-Host "Do you want to continue anyway? (yes/no)"
        if ($proceed -ne "yes") {
            Write-ColorOutput "Installation cancelled." -Type "Warning"
            exit 0
        }
    }

    # Display configuration summary
    Write-Host ""
    Write-ColorOutput "CA Configuration Summary:" -Type "Info"
    Write-ColorOutput "  CA Common Name       : $CACommonName" -Type "Info"
    Write-ColorOutput "  DN Suffix            : $CADistinguishedNameSuffix" -Type "Info"
    Write-ColorOutput "  Validity Period      : $ValidityPeriodUnits $ValidityPeriod" -Type "Info"
    Write-ColorOutput "  Key Length           : $KeyLength bits" -Type "Info"
    Write-ColorOutput "  Hash Algorithm       : $HashAlgorithm" -Type "Info"
    Write-ColorOutput "  Crypto Provider      : $CryptoProviderName" -Type "Info"
    Write-ColorOutput "  Database Path        : $DatabasePath" -Type "Info"
    Write-ColorOutput "  Log Path             : $LogPath" -Type "Info"
    Write-Host ""

    # Install Windows features
    if (-not (Install-CAFeatures)) {
        Write-ColorOutput "Failed to install required features." -Type "Error"
        exit 1
    }

    # Create database and log directories if they don't exist
    Write-ColorOutput "`nPreparing CA directories..." -Type "Info"
    foreach ($path in @($DatabasePath, $LogPath)) {
        if (-not (Test-Path $path)) {
            New-Item -Path $path -ItemType Directory -Force | Out-Null
            Write-ColorOutput "  Created: $path" -Type "Info"
        }
    }

    # Install and configure the CA
    Write-Host ""
    Write-ColorOutput "Installing and configuring Enterprise Root CA..." -Type "Info"
    Write-ColorOutput "This may take several minutes..." -Type "Warning"
    Write-Host ""

    if ($PSCmdlet.ShouldProcess($CACommonName, "Install Enterprise Root CA")) {
        try {
            # Install AD CS Certification Authority
            Install-AdcsCertificationAuthority `
                -CAType EnterpriseRootCA `
                -CACommonName $CACommonName `
                -CADistinguishedNameSuffix $CADistinguishedNameSuffix `
                -ValidityPeriod $ValidityPeriod `
                -ValidityPeriodUnits $ValidityPeriodUnits `
                -CryptoProviderName $CryptoProviderName `
                -KeyLength $KeyLength `
                -HashAlgorithmName $HashAlgorithm `
                -DatabaseDirectory $DatabasePath `
                -LogDirectory $LogPath `
                -Force `
                -ErrorAction Stop | Out-Null

            Write-ColorOutput "CA installation completed successfully!" -Type "Success"

            # Configure CRL and AIA settings
            Write-Host ""
            Write-ColorOutput "Configuring CRL Distribution Points and AIA..." -Type "Info"
            
            # Get CA configuration
            $caName = (Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Services\CertSvc\Configuration").Active
            
            # Remove default CDP locations and add new ones
            Write-ColorOutput "  Configuring CDP (CRL Distribution Points)..." -Type "Info"
            Get-CACrlDistributionPoint | Where-Object { $_.Uri -like "file://*" } | Remove-CACrlDistributionPoint -Force
            
            # Add HTTP CDP
            Add-CACrlDistributionPoint -Uri "http://$env:COMPUTERNAME.$domain/CertEnroll/<CAName><CRLNameSuffix><DeltaCRLAllowed>.crl" -AddToCertificateCdp -Force
            
            # Configure AIA
            Write-ColorOutput "  Configuring AIA (Authority Information Access)..." -Type "Info"
            Get-CAAuthorityInformationAccess | Where-Object { $_.Uri -like "file://*" } | Remove-CAAuthorityInformationAccess -Force
            
            # Add HTTP AIA
            Add-CAAuthorityInformationAccess -Uri "http://$env:COMPUTERNAME.$domain/CertEnroll/<ServerDNSName>_<CAName><CertificateName>.crt" -AddToCertificateAia -Force

            # Configure CRL publication interval
            Write-ColorOutput "  Setting CRL publication intervals..." -Type "Info"
            certutil -setreg CA\CRLPeriod "Weeks"
            certutil -setreg CA\CRLPeriodUnits 1
            certutil -setreg CA\CRLDeltaPeriod "Days"
            certutil -setreg CA\CRLDeltaPeriodUnits 1

            # Configure validity period for issued certificates
            Write-ColorOutput "  Setting certificate validity periods..." -Type "Info"
            certutil -setreg CA\ValidityPeriod "Years"
            certutil -setreg CA\ValidityPeriodUnits 5

            # Restart CA service to apply changes
            Write-ColorOutput "  Restarting Certificate Authority service..." -Type "Info"
            Restart-Service -Name CertSvc -Force
            Start-Sleep -Seconds 5

            # Publish CRL
            Write-ColorOutput "  Publishing initial CRL..." -Type "Info"
            certutil -CRL

            # Display CA information
            Write-Host ""
            Write-ColorOutput "========================================" -Type "Success"
            Write-ColorOutput "  CA Installation Complete!            " -Type "Success"
            Write-ColorOutput "========================================" -Type "Success"
            Write-Host ""

            # Get CA certificate info
            $caCert = Get-ChildItem -Path "Cert:\LocalMachine\My" | Where-Object { $_.Subject -like "*$CACommonName*" } | Select-Object -First 1
            
            if ($caCert) {
                Write-ColorOutput "CA Certificate Details:" -Type "Info"
                Write-ColorOutput "  Thumbprint : $($caCert.Thumbprint)" -Type "Info"
                Write-ColorOutput "  Subject    : $($caCert.Subject)" -Type "Info"
                Write-ColorOutput "  Valid From : $($caCert.NotBefore)" -Type "Info"
                Write-ColorOutput "  Valid To   : $($caCert.NotAfter)" -Type "Info"
                Write-Host ""
            }

            Write-ColorOutput "CA Service Status:" -Type "Info"
            $caService = Get-Service -Name CertSvc
            Write-ColorOutput "  Status: $($caService.Status)" -Type $(if ($caService.Status -eq "Running") { "Success" } else { "Error" })
            Write-Host ""

            Write-ColorOutput "Next Steps:" -Type "Info"
            Write-ColorOutput "1. Run 4-Configure-DCCertTemplate.ps1 to configure certificate templates" -Type "Info"
            Write-ColorOutput "2. Run 5-Install-DoDNTAuthCerts.ps1 to install DoD certificates" -Type "Info"
            Write-ColorOutput "3. Run 6-Configure-AutoEnrollment-GPO.ps1 to configure auto-enrollment" -Type "Info"

        } catch {
            Write-ColorOutput "Failed to install CA: $_" -Type "Error"
            Write-ColorOutput "Stack Trace: $($_.ScriptStackTrace)" -Type "Error"
            exit 1
        }
    }

} catch {
    Write-ColorOutput "An unexpected error occurred: $_" -Type "Error"
    Write-ColorOutput "Stack Trace: $($_.ScriptStackTrace)" -Type "Error"
    exit 1
}
