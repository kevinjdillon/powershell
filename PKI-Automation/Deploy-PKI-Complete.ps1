<#
.SYNOPSIS
    Master orchestration script for complete PKI environment deployment.

.DESCRIPTION
    This script orchestrates the complete deployment of a DoD PKI environment
    by executing all component scripts in sequence. It includes error handling,
    dependency checking, and progress tracking.

.PARAMETER DomainName
    The fully qualified domain name to join (e.g., contoso.com)

.PARAMETER DomainCredential
    Domain credentials with appropriate permissions.
    If not provided, you will be prompted.

.PARAMETER NewComputerName
    Optional: New computer name for the CA server.

.PARAMETER CACommonName
    Common name for the Certificate Authority.
    Default: "Enterprise Root CA"

.PARAMETER CertificatePath
    Directory for certificate download and storage.
    Default: "C:\PKI-Certificates"

.PARAMETER SkipDomainJoin
    Skip domain join if already domain-joined.

.PARAMETER SkipCertDownload
    Skip certificate download if already downloaded.

.PARAMETER SkipCAInstall
    Skip CA installation if already installed.

.EXAMPLE
    .\Deploy-PKI-Complete.ps1 -DomainName "contoso.com"
    
    Runs complete PKI deployment with prompts for credentials.

.EXAMPLE
    $cred = Get-Credential
    .\Deploy-PKI-Complete.ps1 -DomainName "contoso.com" -DomainCredential $cred -NewComputerName "PKI-CA01"
    
    Runs with provided credentials and renames computer.

.EXAMPLE
    .\Deploy-PKI-Complete.ps1 -DomainName "contoso.com" -SkipDomainJoin -SkipCertDownload
    
    Runs deployment skipping domain join and certificate download.

.NOTES
    File Name  : Deploy-PKI-Complete.ps1
    Author     : PKI Automation Script
    Requires   : PowerShell 5.1 or higher
                 Administrator privileges
                 Internet connectivity (for certificate download)
                 Appropriate AD permissions
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$DomainName,

    [Parameter(Mandatory = $false)]
    [PSCredential]$DomainCredential,

    [Parameter(Mandatory = $false)]
    [string]$NewComputerName,

    [Parameter(Mandatory = $false)]
    [string]$CACommonName = "Enterprise Root CA",

    [Parameter(Mandatory = $false)]
    [string]$CertificatePath = "C:\PKI-Certificates",

    [Parameter(Mandatory = $false)]
    [switch]$SkipDomainJoin,

    [Parameter(Mandatory = $false)]
    [switch]$SkipCertDownload,

    [Parameter(Mandatory = $false)]
    [switch]$SkipCAInstall
)

#Requires -RunAsAdministrator

# Set error action preference
$ErrorActionPreference = "Stop"

# Script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Function to write colored output
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Type = "Info"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    switch ($Type) {
        "Info"    { Write-Host "[$timestamp] [INFO] $Message" -ForegroundColor Cyan }
        "Success" { Write-Host "[$timestamp] [SUCCESS] $Message" -ForegroundColor Green }
        "Warning" { Write-Host "[$timestamp] [WARNING] $Message" -ForegroundColor Yellow }
        "Error"   { Write-Host "[$timestamp] [ERROR] $Message" -ForegroundColor Red }
        "Step"    { Write-Host "`n[$timestamp] ===== $Message =====" -ForegroundColor Magenta }
    }
}

# Function to execute script with error handling
function Invoke-PKIScript {
    param(
        [string]$ScriptPath,
        [hashtable]$Parameters = @{},
        [string]$StepName
    )
    
    Write-ColorOutput "Executing: $StepName" -Type "Step"
    Write-ColorOutput "Script: $ScriptPath" -Type "Info"
    
    if (-not (Test-Path $ScriptPath)) {
        Write-ColorOutput "Script not found: $ScriptPath" -Type "Error"
        return $false
    }
    
    try {
        & $ScriptPath @Parameters
        
        if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
            Write-ColorOutput "$StepName completed with exit code: $LASTEXITCODE" -Type "Warning"
            return $false
        }
        
        Write-ColorOutput "$StepName completed successfully" -Type "Success"
        return $true
        
    } catch {
        Write-ColorOutput "$StepName failed: $_" -Type "Error"
        return $false
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

# Function to prompt for restart
function Request-Restart {
    param([string]$Reason)
    
    Write-ColorOutput "Computer restart required: $Reason" -Type "Warning"
    $response = Read-Host "Restart now? (yes/no)"
    
    if ($response -eq "yes") {
        Write-ColorOutput "Restarting computer in 10 seconds..." -Type "Warning"
        Start-Sleep -Seconds 10
        Restart-Computer -Force
        exit 0
    } else {
        Write-ColorOutput "Please restart the computer manually and re-run this script." -Type "Warning"
        exit 0
    }
}

# Main deployment logic
try {
    Write-ColorOutput "========================================" -Type "Info"
    Write-ColorOutput "  PKI COMPLETE DEPLOYMENT ORCHESTRATOR " -Type "Info"
    Write-ColorOutput "========================================" -Type "Info"
    Write-Host ""
    
    # Deployment configuration summary
    Write-ColorOutput "Deployment Configuration:" -Type "Info"
    Write-ColorOutput "  Domain Name       : $DomainName" -Type "Info"
    Write-ColorOutput "  CA Common Name    : $CACommonName" -Type "Info"
    Write-ColorOutput "  Certificate Path  : $CertificatePath" -Type "Info"
    Write-ColorOutput "  Script Directory  : $ScriptDir" -Type "Info"
    Write-Host ""
    
    Write-ColorOutput "Skip Options:" -Type "Info"
    Write-ColorOutput "  Skip Domain Join  : $SkipDomainJoin" -Type "Info"
    Write-ColorOutput "  Skip Cert Download: $SkipCertDownload" -Type "Info"
    Write-ColorOutput "  Skip CA Install   : $SkipCAInstall" -Type "Info"
    Write-Host ""
    
    # Confirmation
    $continue = Read-Host "Continue with deployment? (yes/no)"
    if ($continue -ne "yes") {
        Write-ColorOutput "Deployment cancelled by user." -Type "Warning"
        exit 0
    }
    
    # Track deployment progress
    $deploymentLog = @{
        StartTime = Get-Date
        Steps = @()
    }
    
    # ===== STEP 1: Domain Join =====
    if (-not $SkipDomainJoin) {
        $isDomainJoined = Test-DomainMembership
        
        if ($isDomainJoined) {
            Write-ColorOutput "Computer is already domain-joined. Skipping domain join." -Type "Warning"
        } else {
            if (-not $DomainName) {
                $DomainName = Read-Host "Enter domain name (FQDN)"
            }
            
            $params = @{
                DomainName = $DomainName
            }
            
            if ($DomainCredential) {
                $params['Credential'] = $DomainCredential
            }
            
            if ($NewComputerName) {
                $params['NewComputerName'] = $NewComputerName
            }
            
            $params['Restart'] = $false  # Manual restart control
            
            $success = Invoke-PKIScript `
                -ScriptPath (Join-Path $ScriptDir "1-Join-Domain.ps1") `
                -Parameters $params `
                -StepName "Step 1: Domain Join"
            
            $deploymentLog.Steps += @{
                Step = "Domain Join"
                Success = $success
                Timestamp = Get-Date
            }
            
            if ($success) {
                Request-Restart -Reason "Domain join completed"
            } else {
                Write-ColorOutput "Domain join failed. Cannot continue." -Type "Error"
                exit 1
            }
        }
    } else {
        Write-ColorOutput "Skipping Step 1: Domain Join (as requested)" -Type "Warning"
    }
    
    # ===== STEP 2: Download and Prepare DoD Certificates =====
    if (-not $SkipCertDownload) {
        $params = @{
            OutputPath = $CertificatePath
        }
        
        $success = Invoke-PKIScript `
            -ScriptPath (Join-Path $ScriptDir "2-Download-PrepDoDCerts.ps1") `
            -Parameters $params `
            -StepName "Step 2: Download DoD Certificates"
        
        $deploymentLog.Steps += @{
            Step = "Certificate Download"
            Success = $success
            Timestamp = Get-Date
        }
        
        if (-not $success) {
            Write-ColorOutput "Certificate download failed." -Type "Error"
            $response = Read-Host "Continue anyway? (yes/no)"
            if ($response -ne "yes") {
                exit 1
            }
        }
    } else {
        Write-ColorOutput "Skipping Step 2: Certificate Download (as requested)" -Type "Warning"
    }
    
    # ===== STEP 3: Install Enterprise Root CA =====
    if (-not $SkipCAInstall) {
        $params = @{
            CACommonName = $CACommonName
        }
        
        $success = Invoke-PKIScript `
            -ScriptPath (Join-Path $ScriptDir "3-Install-EnterpriseRootCA.ps1") `
            -Parameters $params `
            -StepName "Step 3: Install Enterprise Root CA"
        
        $deploymentLog.Steps += @{
            Step = "CA Installation"
            Success = $success
            Timestamp = Get-Date
        }
        
        if (-not $success) {
            Write-ColorOutput "CA installation failed. Cannot continue." -Type "Error"
            exit 1
        }
    } else {
        Write-ColorOutput "Skipping Step 3: CA Installation (as requested)" -Type "Warning"
    }
    
    # ===== STEP 4: Configure DC Certificate Template =====
    $params = @{
        UseExistingTemplate = $true
    }
    
    $success = Invoke-PKIScript `
        -ScriptPath (Join-Path $ScriptDir "4-Configure-DCCertTemplate.ps1") `
        -Parameters $params `
        -StepName "Step 4: Configure DC Certificate Template"
    
    $deploymentLog.Steps += @{
        Step = "Certificate Template Configuration"
        Success = $success
        Timestamp = Get-Date
    }
    
    if (-not $success) {
        Write-ColorOutput "Certificate template configuration failed." -Type "Error"
        $response = Read-Host "Continue anyway? (yes/no)"
        if ($response -ne "yes") {
            exit 1
        }
    }
    
    # ===== STEP 5: Install DoD Certificates to NTAuth Store =====
    $params = @{
        CertificatePath = $CertificatePath
    }
    
    $success = Invoke-PKIScript `
        -ScriptPath (Join-Path $ScriptDir "5-Install-DoDNTAuthCerts.ps1") `
        -Parameters $params `
        -StepName "Step 5: Install DoD NTAuth Certificates"
    
    $deploymentLog.Steps += @{
        Step = "NTAuth Certificate Installation"
        Success = $success
        Timestamp = Get-Date
    }
    
    if (-not $success) {
        Write-ColorOutput "NTAuth certificate installation had issues." -Type "Warning"
    }
    
    # ===== STEP 6: Configure Auto-Enrollment GPO =====
    $params = @{}
    
    $success = Invoke-PKIScript `
        -ScriptPath (Join-Path $ScriptDir "6-Configure-AutoEnrollment-GPO.ps1") `
        -Parameters $params `
        -StepName "Step 6: Configure Auto-Enrollment GPO"
    
    $deploymentLog.Steps += @{
        Step = "GPO Configuration"
        Success = $success
        Timestamp = Get-Date
    }
    
    if (-not $success) {
        Write-ColorOutput "GPO configuration had issues." -Type "Warning"
    }
    
    # ===== DEPLOYMENT COMPLETE =====
    $deploymentLog.EndTime = Get-Date
    $deploymentLog.Duration = $deploymentLog.EndTime - $deploymentLog.StartTime
    
    Write-Host ""
    Write-Host ""
    Write-ColorOutput "========================================" -Type "Success"
    Write-ColorOutput "  PKI DEPLOYMENT COMPLETE!             " -Type "Success"
    Write-ColorOutput "========================================" -Type "Success"
    Write-Host ""
    
    # Display deployment summary
    Write-ColorOutput "Deployment Summary:" -Type "Info"
    Write-ColorOutput "  Start Time    : $($deploymentLog.StartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -Type "Info"
    Write-ColorOutput "  End Time      : $($deploymentLog.EndTime.ToString('yyyy-MM-dd HH:mm:ss'))" -Type "Info"
    Write-ColorOutput "  Duration      : $($deploymentLog.Duration.ToString('hh\:mm\:ss'))" -Type "Info"
    Write-Host ""
    
    Write-ColorOutput "Step Results:" -Type "Info"
    foreach ($step in $deploymentLog.Steps) {
        $status = if ($step.Success) { "SUCCESS" } else { "FAILED" }
        $color = if ($step.Success) { "Success" } else { "Error" }
        Write-ColorOutput "  $($step.Step): $status" -Type $color
    }
    Write-Host ""
    
    # Check if all steps succeeded
    $failedSteps = $deploymentLog.Steps | Where-Object { -not $_.Success }
    
    if ($failedSteps.Count -eq 0) {
        Write-ColorOutput "All deployment steps completed successfully!" -Type "Success"
    } else {
        Write-ColorOutput "Some steps had issues. Review the log above." -Type "Warning"
    }
    
    Write-Host ""
    Write-ColorOutput "Next Steps:" -Type "Info"
    Write-ColorOutput "1. Verify CA service is running: Get-Service CertSvc" -Type "Info"
    Write-ColorOutput "2. Check certificate templates: certutil -CATemplates" -Type "Info"
    Write-ColorOutput "3. Force GP update on DCs: gpupdate /force" -Type "Info"
    Write-ColorOutput "4. Test auto-enrollment: certutil -pulse" -Type "Info"
    Write-ColorOutput "5. Verify certificates: Get-ChildItem Cert:\LocalMachine\My" -Type "Info"
    Write-Host ""
    
    Write-ColorOutput "Documentation:" -Type "Info"
    Write-ColorOutput "  Individual scripts can be run separately for testing or re-configuration" -Type "Info"
    Write-ColorOutput "  All scripts support -WhatIf for dry-run testing" -Type "Info"
    Write-ColorOutput "  Check each script's help for detailed parameters: Get-Help .\<script>.ps1 -Full" -Type "Info"
    
} catch {
    Write-ColorOutput "Deployment failed with unexpected error: $_" -Type "Error"
    Write-ColorOutput "Stack Trace: $($_.ScriptStackTrace)" -Type "Error"
    exit 1
}
