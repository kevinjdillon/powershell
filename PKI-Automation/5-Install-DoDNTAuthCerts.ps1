<#
.SYNOPSIS
    Installs DoD PKI certificates to the NTAuth store in Active Directory.

.DESCRIPTION
    This script imports DoD root and intermediate certificates to the NTAuth
    (Enterprise NTAuth) store in Active Directory. This is required to enable
    smart card authentication using DoD PKI certificates.

.PARAMETER CertificatePath
    Path to the directory containing the DoD certificates.
    Default: "C:\PKI-Certificates"

.PARAMETER InstallRootCerts
    Install root CA certificates to NTAuth store.
    Default: $true

.PARAMETER InstallIntermediateCerts
    Install intermediate CA certificates to NTAuth store.
    Default: $true

.PARAMETER AlsoInstallToTrustedRoot
    Also install certificates to Trusted Root CA store on local machine.
    Default: $true

.EXAMPLE
    .\5-Install-DoDNTAuthCerts.ps1
    
    Installs all DoD certificates from default location.

.EXAMPLE
    .\5-Install-DoDNTAuthCerts.ps1 -CertificatePath "D:\Certificates"
    
    Installs certificates from custom location.

.EXAMPLE
    .\5-Install-DoDNTAuthCerts.ps1 -InstallIntermediateCerts $false
    
    Installs only root certificates, skipping intermediates.

.NOTES
    File Name  : 5-Install-DoDNTAuthCerts.ps1
    Author     : PKI Automation Script
    Requires   : PowerShell 5.1 or higher
                 Administrator privileges
                 Domain-joined computer
                 Enterprise Admin permissions
                 Certificates must be downloaded first (run 2-Download-PrepDoDCerts.ps1)
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [string]$CertificatePath = "C:\PKI-Certificates",

    [Parameter(Mandatory = $false)]
    [bool]$InstallRootCerts = $true,

    [Parameter(Mandatory = $false)]
    [bool]$InstallIntermediateCerts = $true,

    [Parameter(Mandatory = $false)]
    [bool]$AlsoInstallToTrustedRoot = $false
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

# Function to check if domain-joined
function Test-DomainMembership {
    try {
        $computerSystem = Get-WmiObject -Class Win32_ComputerSystem
        return $computerSystem.PartOfDomain
    } catch {
        return $false
    }
}

# Function to get NTAuth store certificates
function Get-NTAuthCertificates {
    try {
        $configNC = ([ADSI]"LDAP://RootDSE").configurationNamingContext
        $pkiContainer = "CN=Public Key Services,CN=Services,$configNC"
        $ntAuthStore = "CN=NTAuthCertificates,$pkiContainer"
        
        $ntAuth = [ADSI]"LDAP://$ntAuthStore"
        $existingCerts = $ntAuth.Properties["cACertificate"]
        
        return $existingCerts
    } catch {
        Write-ColorOutput "Error accessing NTAuth store: $_" -Type "Error"
        return $null
    }
}

# Function to publish certificate to NTAuth store
function Publish-CertificateToNTAuth {
    param(
        [string]$CertPath
    )
    
    try {
        # Use certutil to publish to NTAuth store
        $result = certutil -dspublish -f $CertPath NTAuthCA 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            return $true
        } else {
            Write-ColorOutput "  certutil returned error code: $LASTEXITCODE" -Type "Warning"
            return $false
        }
    } catch {
        Write-ColorOutput "  Error: $_" -Type "Error"
        return $false
    }
}

# Function to install certificate to local Trusted Root store
function Install-ToTrustedRoot {
    param(
        [string]$CertPath
    )
    
    try {
        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
        $cert.Import($CertPath)
        
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store(
            [System.Security.Cryptography.X509Certificates.StoreName]::Root,
            [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
        )
        
        $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
        
        # Check if certificate already exists
        $existingCert = $store.Certificates | Where-Object { $_.Thumbprint -eq $cert.Thumbprint }
        
        if ($existingCert) {
            $store.Close()
            return "AlreadyExists"
        }
        
        $store.Add($cert)
        $store.Close()
        
        return "Success"
    } catch {
        Write-ColorOutput "  Error: $_" -Type "Error"
        return "Failed"
    }
}

# Main script execution
try {
    Write-ColorOutput "========================================" -Type "Info"
    Write-ColorOutput "  DoD NTAuth Certificate Installation  " -Type "Info"
    Write-ColorOutput "========================================" -Type "Info"
    Write-Host ""

    # Check if domain-joined
    Write-ColorOutput "Verifying domain membership..." -Type "Info"
    if (-not (Test-DomainMembership)) {
        Write-ColorOutput "ERROR: This computer is not domain-joined." -Type "Error"
        Write-ColorOutput "NTAuth store is an Active Directory component." -Type "Error"
        exit 1
    }
    
    $domain = (Get-WmiObject -Class Win32_ComputerSystem).Domain
    Write-ColorOutput "Domain: $domain" -Type "Success"

    # Verify certificate path exists
    Write-ColorOutput "`nVerifying certificate path..." -Type "Info"
    if (-not (Test-Path $CertificatePath)) {
        Write-ColorOutput "ERROR: Certificate path not found: $CertificatePath" -Type "Error"
        Write-ColorOutput "Run 2-Download-PrepDoDCerts.ps1 first." -Type "Error"
        exit 1
    }
    Write-ColorOutput "Certificate path verified: $CertificatePath" -Type "Success"

    # Configuration summary
    Write-Host ""
    Write-ColorOutput "Installation Configuration:" -Type "Info"
    Write-ColorOutput "  Certificate Path        : $CertificatePath" -Type "Info"
    Write-ColorOutput "  Install Root CAs        : $InstallRootCerts" -Type "Info"
    Write-ColorOutput "  Install Intermediate CAs: $InstallIntermediateCerts" -Type "Info"
    Write-ColorOutput "  Install to Trusted Root : $AlsoInstallToTrustedRoot" -Type "Info"
    Write-Host ""

    # Initialize counters
    $rootInstalled = 0
    $rootSkipped = 0
    $intermediateInstalled = 0
    $intermediateSkipped = 0
    $errors = 0

    if ($PSCmdlet.ShouldProcess("NTAuth Store", "Install DoD certificates")) {
        
        # Get existing NTAuth certificates
        Write-ColorOutput "Checking existing NTAuth store certificates..." -Type "Info"
        $existingNTAuthCerts = Get-NTAuthCertificates
        Write-ColorOutput "Found $($existingNTAuthCerts.Count) existing certificates in NTAuth store." -Type "Info"
        Write-Host ""

        # Install Root CA certificates
        if ($InstallRootCerts) {
            $rootPath = Join-Path $CertificatePath "Root"
            
            if (Test-Path $rootPath) {
                Write-ColorOutput "Installing Root CA certificates..." -Type "Info"
                $rootCerts = Get-ChildItem -Path $rootPath -Filter "*.cer"
                
                if ($rootCerts.Count -eq 0) {
                    Write-ColorOutput "No root certificates found in: $rootPath" -Type "Warning"
                } else {
                    foreach ($certFile in $rootCerts) {
                        Write-ColorOutput "  Processing: $($certFile.Name)" -Type "Info"
                        
                        # Load certificate to get details
                        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
                        $cert.Import($certFile.FullName)
                        $subject = ($cert.Subject -split ',')[0] -replace 'CN=', ''
                        
                        Write-ColorOutput "    Subject: $subject" -Type "Info"
                        Write-ColorOutput "    Thumbprint: $($cert.Thumbprint)" -Type "Info"
                        
                        # Publish to NTAuth
                        Write-ColorOutput "    Publishing to NTAuth store..." -Type "Info"
                        if (Publish-CertificateToNTAuth -CertPath $certFile.FullName) {
                            Write-ColorOutput "    Published to NTAuth store successfully" -Type "Success"
                            $rootInstalled++
                        } else {
                            Write-ColorOutput "    May already exist in NTAuth store" -Type "Warning"
                            $rootSkipped++
                        }
                        
                        # Install to local Trusted Root if specified
                        if ($AlsoInstallToTrustedRoot) {
                            Write-ColorOutput "    Installing to Trusted Root CA store..." -Type "Info"
                            $result = Install-ToTrustedRoot -CertPath $certFile.FullName
                            
                            switch ($result) {
                                "Success" { Write-ColorOutput "    Installed to Trusted Root successfully" -Type "Success" }
                                "AlreadyExists" { Write-ColorOutput "    Already exists in Trusted Root store" -Type "Warning" }
                                "Failed" { 
                                    Write-ColorOutput "    Failed to install to Trusted Root" -Type "Error"
                                    $errors++
                                }
                            }
                        }
                        
                        Write-Host ""
                    }
                }
            } else {
                Write-ColorOutput "Root certificate directory not found: $rootPath" -Type "Warning"
            }
        }

        # Install Intermediate CA certificates
        if ($InstallIntermediateCerts) {
            $intermediatePath = Join-Path $CertificatePath "Intermediate"
            
            if (Test-Path $intermediatePath) {
                Write-ColorOutput "Installing Intermediate CA certificates..." -Type "Info"
                $intermediateCerts = Get-ChildItem -Path $intermediatePath -Filter "*.cer"
                
                if ($intermediateCerts.Count -eq 0) {
                    Write-ColorOutput "No intermediate certificates found in: $intermediatePath" -Type "Warning"
                } else {
                    foreach ($certFile in $intermediateCerts) {
                        Write-ColorOutput "  Processing: $($certFile.Name)" -Type "Info"
                        
                        # Load certificate to get details
                        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
                        $cert.Import($certFile.FullName)
                        $subject = ($cert.Subject -split ',')[0] -replace 'CN=', ''
                        
                        Write-ColorOutput "    Subject: $subject" -Type "Info"
                        Write-ColorOutput "    Thumbprint: $($cert.Thumbprint)" -Type "Info"
                        
                        # Publish to NTAuth
                        Write-ColorOutput "    Publishing to NTAuth store..." -Type "Info"
                        if (Publish-CertificateToNTAuth -CertPath $certFile.FullName) {
                            Write-ColorOutput "    Published to NTAuth store successfully" -Type "Success"
                            $intermediateInstalled++
                        } else {
                            Write-ColorOutput "    May already exist in NTAuth store" -Type "Warning"
                            $intermediateSkipped++
                        }
                        
                        # Install to local Intermediate CA store if specified
                        if ($AlsoInstallToTrustedRoot) {
                            Write-ColorOutput "    Installing to Intermediate CA store..." -Type "Info"
                            
                            try {
                                $store = New-Object System.Security.Cryptography.X509Certificates.X509Store(
                                    [System.Security.Cryptography.X509Certificates.StoreName]::CertificateAuthority,
                                    [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
                                )
                                $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
                                
                                $existingCert = $store.Certificates | Where-Object { $_.Thumbprint -eq $cert.Thumbprint }
                                
                                if ($existingCert) {
                                    Write-ColorOutput "    Already exists in Intermediate CA store" -Type "Warning"
                                } else {
                                    $store.Add($cert)
                                    Write-ColorOutput "    Installed to Intermediate CA store successfully" -Type "Success"
                                }
                                
                                $store.Close()
                            } catch {
                                Write-ColorOutput "    Failed to install to Intermediate CA store: $_" -Type "Error"
                                $errors++
                            }
                        }
                        
                        Write-Host ""
                    }
                }
            } else {
                Write-ColorOutput "Intermediate certificate directory not found: $intermediatePath" -Type "Warning"
            }
        }

        # Display summary
        Write-Host ""
        Write-ColorOutput "========================================" -Type "Success"
        Write-ColorOutput "  Certificate Installation Complete!   " -Type "Success"
        Write-ColorOutput "========================================" -Type "Success"
        Write-Host ""
        
        Write-ColorOutput "Installation Summary:" -Type "Info"
        Write-ColorOutput "  Root CAs Installed        : $rootInstalled" -Type "Info"
        Write-ColorOutput "  Root CAs Skipped          : $rootSkipped" -Type "Info"
        Write-ColorOutput "  Intermediate CAs Installed: $intermediateInstalled" -Type "Info"
        Write-ColorOutput "  Intermediate CAs Skipped  : $intermediateSkipped" -Type "Info"
        Write-ColorOutput "  Errors                    : $errors" -Type $(if ($errors -eq 0) { "Success" } else { "Error" })
        Write-Host ""

        # Verify NTAuth store contents
        Write-ColorOutput "Verifying NTAuth store..." -Type "Info"
        $updatedNTAuthCerts = Get-NTAuthCertificates
        Write-ColorOutput "NTAuth store now contains $($updatedNTAuthCerts.Count) certificates." -Type "Success"
        Write-Host ""

        Write-ColorOutput "Important Notes:" -Type "Info"
        Write-ColorOutput "- Certificates in NTAuth store enable smart card authentication" -Type "Info"
        Write-ColorOutput "- Changes will replicate to all domain controllers" -Type "Info"
        Write-ColorOutput "- Allow time for AD replication (typically a few minutes)" -Type "Info"
        Write-Host ""

        Write-ColorOutput "To view NTAuth store certificates, run:" -Type "Info"
        Write-ColorOutput "  certutil -viewstore -enterprise NTAuth" -Type "Info"
        Write-Host ""

        Write-ColorOutput "Next Step:" -Type "Info"
        Write-ColorOutput "Run 6-Configure-AutoEnrollment-GPO.ps1 to configure certificate auto-enrollment" -Type "Info"

    }

} catch {
    Write-ColorOutput "An unexpected error occurred: $_" -Type "Error"
    Write-ColorOutput "Stack Trace: $($_.ScriptStackTrace)" -Type "Error"
    exit 1
}
