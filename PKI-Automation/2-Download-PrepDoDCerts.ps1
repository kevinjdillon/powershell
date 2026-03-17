<#
.SYNOPSIS
    Downloads and prepares DoD PKI certificates for installation.

.DESCRIPTION
    This script downloads the DoD unclassified certificate bundle in PKCS7 format,
    extracts individual certificates, and prepares them for installation into
    the Windows certificate stores and Active Directory NTAuth store.

.PARAMETER DownloadUrl
    URL to download the DoD certificate bundle.
    Default: https://dl.dod.cyber.mil/wp-content/uploads/pki-pke/zip/unclass-certificates_pkcs7_DoD.zip

.PARAMETER OutputPath
    Directory where certificates will be downloaded and extracted.
    Default: C:\PKI-Certificates

.PARAMETER Force
    If specified, will overwrite existing downloaded files.

.EXAMPLE
    .\2-Download-PrepDoDCerts.ps1
    
    Downloads DoD certificates to the default location.

.EXAMPLE
    .\2-Download-PrepDoDCerts.ps1 -OutputPath "D:\Certificates" -Force
    
    Downloads to a custom location and overwrites existing files.

.NOTES
    File Name  : 2-Download-PrepDoDCerts.ps1
    Author     : PKI Automation Script
    Requires   : PowerShell 5.1 or higher
                 Administrator privileges
                 Internet connectivity
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$DownloadUrl = "https://dl.dod.cyber.mil/wp-content/uploads/pki-pke/zip/unclass-certificates_pkcs7_DoD.zip",

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "C:\PKI-Certificates",

    [Parameter(Mandatory = $false)]
    [switch]$Force
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

# Function to test internet connectivity
function Test-InternetConnection {
    param([string]$Url)
    
    try {
        $response = Invoke-WebRequest -Uri $Url -Method Head -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

# Function to extract certificates from PKCS7 file
function Export-CertificatesFromPKCS7 {
    param(
        [string]$PKCS7Path,
        [string]$ExportPath
    )
    
    try {
       # Load the required assembly for PKCS7 operations
        Add-Type -AssemblyName System.Security
           
        Write-ColorOutput "Extracting certificates from PKCS7 bundle..." -Type "Info"
        
        # Load the PKCS7 file
        $pkcs7Content = [System.IO.File]::ReadAllBytes($PKCS7Path)
        $signedCms = New-Object System.Security.Cryptography.Pkcs.SignedCms
        $signedCms.Decode($pkcs7Content)
        
        $certCount = 0
        $rootCerts = @()
        $intermediateCerts = @()
        
        # Process each certificate in the bundle
        foreach ($cert in $signedCms.Certificates) {
            $certCount++
            
            # Determine certificate type
            $isRoot = $cert.Subject -eq $cert.Issuer
            
            # Create friendly name
            $subjectCN = ($cert.Subject -split ',')[0] -replace 'CN=', ''
            $friendlyName = $subjectCN -replace '[^\w\-\.]', '_'
            
            # Determine subfolder
            if ($isRoot) {
                $certType = "Root"
                $certFolder = Join-Path $ExportPath "Root"
                $rootCerts += $cert
            } else {
                $certType = "Intermediate"
                $certFolder = Join-Path $ExportPath "Intermediate"
                $intermediateCerts += $cert
            }
            
            # Create folder if it doesn't exist
            if (-not (Test-Path $certFolder)) {
                New-Item -Path $certFolder -ItemType Directory -Force | Out-Null
            }
            
            # Export certificate as .cer file
            $certFileName = "$friendlyName.cer"
            $certPath = Join-Path $certFolder $certFileName
            
            $certBytes = $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
            [System.IO.File]::WriteAllBytes($certPath, $certBytes)
            
            Write-ColorOutput "  [$certType] $subjectCN" -Type "Info"
        }
        
        Write-ColorOutput "`nExtraction Summary:" -Type "Success"
        Write-ColorOutput "  Total Certificates : $certCount" -Type "Info"
        Write-ColorOutput "  Root CAs          : $($rootCerts.Count)" -Type "Info"
        Write-ColorOutput "  Intermediate CAs  : $($intermediateCerts.Count)" -Type "Info"
        
        return @{
            Success = $true
            TotalCount = $certCount
            RootCount = $rootCerts.Count
            IntermediateCount = $intermediateCerts.Count
        }
        
    } catch {
        Write-ColorOutput "Error extracting certificates: $_" -Type "Error"
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

# Main script execution
try {
    Write-ColorOutput "========================================" -Type "Info"
    Write-ColorOutput "  DoD Certificate Download & Prep      " -Type "Info"
    Write-ColorOutput "========================================" -Type "Info"
    Write-Host ""

    # Create output directory if it doesn't exist
    if (-not (Test-Path $OutputPath)) {
        Write-ColorOutput "Creating output directory: $OutputPath" -Type "Info"
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
    }

    # Define file paths
    $zipFileName = "unclass-certificates_pkcs7_DoD.zip"
    $zipFilePath = Join-Path $OutputPath $zipFileName
    $extractPath = Join-Path $OutputPath "Extracted"

    # Check if files already exist
    if ((Test-Path $zipFilePath) -and -not $Force) {
        Write-ColorOutput "Certificate bundle already downloaded." -Type "Warning"
        Write-ColorOutput "Use -Force to re-download." -Type "Warning"
    } else {
        # Test internet connectivity
        Write-ColorOutput "Testing connectivity to DoD Cyber Exchange..." -Type "Info"
        if (-not (Test-InternetConnection -Url "https://dl.dod.cyber.mil")) {
            Write-ColorOutput "Cannot reach DoD Cyber Exchange website." -Type "Error"
            Write-ColorOutput "Please check your internet connection and proxy settings." -Type "Error"
            exit 1
        }

        # Download the certificate bundle
        Write-ColorOutput "Downloading DoD certificate bundle..." -Type "Info"
        Write-ColorOutput "  Source: $DownloadUrl" -Type "Info"
        Write-ColorOutput "  Target: $zipFilePath" -Type "Info"
        Write-Host ""

        try {
            # Use TLS 1.2 or higher
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            
            # Download with progress
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($DownloadUrl, $zipFilePath)
            
            Write-ColorOutput "Download completed successfully!" -Type "Success"
            
        } catch {
            Write-ColorOutput "Failed to download certificate bundle: $_" -Type "Error"
            exit 1
        }
    }

    # Extract the ZIP file
    Write-ColorOutput "`nExtracting ZIP archive..." -Type "Info"
    
    if (Test-Path $extractPath) {
        if ($Force) {
            Remove-Item -Path $extractPath -Recurse -Force
        }
    }
    
    try {
        Expand-Archive -Path $zipFilePath -DestinationPath $extractPath -Force
        Write-ColorOutput "ZIP extraction completed." -Type "Success"
    } catch {
        Write-ColorOutput "Failed to extract ZIP file: $_" -Type "Error"
        exit 1
    }

    # Find PKCS7 files
    Write-ColorOutput "`nSearching for PKCS7 certificate files..." -Type "Info"
    $pkcs7Files = Get-ChildItem -Path $extractPath -Filter "*.p7b" -Recurse
    
    if ($pkcs7Files.Count -eq 0) {
        Write-ColorOutput "No PKCS7 (.p7b) files found in the archive." -Type "Error"
        exit 1
    }

    Write-ColorOutput "Found $($pkcs7Files.Count) PKCS7 file(s)." -Type "Success"

    # Process each PKCS7 file
    $allResults = @()
    foreach ($p7bFile in $pkcs7Files) {
        Write-ColorOutput "`nProcessing: $($p7bFile.Name)" -Type "Info"
        
        $result = Export-CertificatesFromPKCS7 -PKCS7Path $p7bFile.FullName -ExportPath $OutputPath
        $allResults += $result
    }

    # Display final summary
    Write-Host ""
    Write-ColorOutput "========================================" -Type "Success"
    Write-ColorOutput "  Certificate Preparation Complete!    " -Type "Success"
    Write-ColorOutput "========================================" -Type "Success"
    Write-Host ""
    Write-ColorOutput "Certificate Location: $OutputPath" -Type "Info"
    Write-ColorOutput "  Root CAs         : $OutputPath\Root" -Type "Info"
    Write-ColorOutput "  Intermediate CAs : $OutputPath\Intermediate" -Type "Info"
    Write-Host ""
    
    # Create a summary file
    $summaryPath = Join-Path $OutputPath "Certificate-Summary.txt"
    $summaryContent = @"
DoD PKI Certificate Download Summary
=====================================
Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Download URL: $DownloadUrl
Output Path: $OutputPath

Certificate Counts:
"@
    
    foreach ($result in $allResults) {
        if ($result.Success) {
            $summaryContent += "`n  Total Certificates: $($result.TotalCount)"
            $summaryContent += "`n  Root CAs: $($result.RootCount)"
            $summaryContent += "`n  Intermediate CAs: $($result.IntermediateCount)"
        }
    }
    
    $summaryContent | Out-File -FilePath $summaryPath -Encoding UTF8
    Write-ColorOutput "Summary saved to: $summaryPath" -Type "Info"
    Write-Host ""
    Write-ColorOutput "Next Step: Run 3-Install-EnterpriseRootCA.ps1" -Type "Info"

} catch {
    Write-ColorOutput "An unexpected error occurred: $_" -Type "Error"
    Write-ColorOutput "Stack Trace: $($_.ScriptStackTrace)" -Type "Error"
    exit 1
}
