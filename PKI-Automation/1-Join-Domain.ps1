<#
.SYNOPSIS
    Joins a Windows Server to an Active Directory domain.

.DESCRIPTION
    This script joins a Windows Server to an existing Active Directory domain.
    It accepts domain credentials and optionally allows specifying a new computer name.
    After joining the domain, the computer will restart automatically.

.PARAMETER DomainName
    The fully qualified domain name (FQDN) to join (e.g., contoso.com)

.PARAMETER Credential
    Domain credentials with permission to join computers to the domain.
    If not provided, you will be prompted to enter credentials.

.PARAMETER NewComputerName
    Optional: Specify a new computer name. If not provided, current name is retained.

.PARAMETER OUPath
    Optional: Distinguished name of the OU where the computer account should be created.
    Example: "OU=Servers,OU=PKI,DC=contoso,DC=com"

.PARAMETER Restart
    If specified, the computer will restart automatically after joining the domain.
    Default is $true.

.EXAMPLE
    .\1-Join-Domain.ps1 -DomainName "contoso.com"
    
    Prompts for credentials and joins the domain using the current computer name.

.EXAMPLE
    $cred = Get-Credential "CONTOSO\Administrator"
    .\1-Join-Domain.ps1 -DomainName "contoso.com" -Credential $cred -NewComputerName "PKI-CA01"
    
    Joins the domain, renames the computer to PKI-CA01, and restarts.

.EXAMPLE
    .\1-Join-Domain.ps1 -DomainName "contoso.com" -OUPath "OU=Servers,OU=PKI,DC=contoso,DC=com"
    
    Joins the domain and places the computer account in the specified OU.

.NOTES
    File Name  : 1-Join-Domain.ps1
    Author     : PKI Automation Script
    Requires   : PowerShell 5.1 or higher
                 Administrator privileges
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$DomainName,

    [Parameter(Mandatory = $false)]
    [PSCredential]$Credential,

    [Parameter(Mandatory = $false)]
    [ValidateLength(1, 15)]
    [string]$NewComputerName,

    [Parameter(Mandatory = $false)]
    [string]$OUPath,

    [Parameter(Mandatory = $false)]
    [bool]$Restart = $true
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

# Function to check if computer is already domain-joined
function Test-DomainMembership {
    try {
        $computerSystem = Get-WmiObject -Class Win32_ComputerSystem
        if ($computerSystem.PartOfDomain) {
            return @{
                IsDomainJoined = $true
                CurrentDomain = $computerSystem.Domain
            }
        } else {
            return @{
                IsDomainJoined = $false
                CurrentDomain = $null
            }
        }
    } catch {
        Write-ColorOutput "Error checking domain membership: $_" -Type "Error"
        return @{
            IsDomainJoined = $false
            CurrentDomain = $null
        }
    }
}

# Main script execution
try {
    Write-ColorOutput "========================================" -Type "Info"
    Write-ColorOutput "  Domain Join Script - PKI Automation  " -Type "Info"
    Write-ColorOutput "========================================" -Type "Info"
    Write-Host ""

    # Check current domain membership
    Write-ColorOutput "Checking current domain membership..." -Type "Info"
    $domainStatus = Test-DomainMembership
    
    if ($domainStatus.IsDomainJoined) {
        if ($domainStatus.CurrentDomain -eq $DomainName) {
            Write-ColorOutput "Computer is already joined to domain: $($domainStatus.CurrentDomain)" -Type "Warning"
            Write-ColorOutput "No action needed." -Type "Success"
            exit 0
        } else {
            Write-ColorOutput "Computer is currently joined to domain: $($domainStatus.CurrentDomain)" -Type "Warning"
            Write-ColorOutput "Target domain: $DomainName" -Type "Warning"
            Write-ColorOutput "Computer must be removed from current domain first." -Type "Error"
            exit 1
        }
    }

    # Get credentials if not provided
    if (-not $Credential) {
        Write-ColorOutput "Please enter domain credentials..." -Type "Info"
        $Credential = Get-Credential -Message "Enter credentials for domain: $DomainName"
    }

    # Verify credentials are provided
    if (-not $Credential) {
        Write-ColorOutput "Credentials are required to join the domain." -Type "Error"
        exit 1
    }

    # Prepare Add-Computer parameters
    $addComputerParams = @{
        DomainName = $DomainName
        Credential = $Credential
        Force = $true
    }

    # Add optional parameters if provided
    if ($NewComputerName) {
        Write-ColorOutput "Computer will be renamed to: $NewComputerName" -Type "Info"
        $addComputerParams['NewName'] = $NewComputerName
    }

    if ($OUPath) {
        Write-ColorOutput "Computer account will be created in OU: $OUPath" -Type "Info"
        $addComputerParams['OUPath'] = $OUPath
    }

    if ($Restart) {
        $addComputerParams['Restart'] = $true
    }

    # Display summary
    Write-Host ""
    Write-ColorOutput "Domain Join Summary:" -Type "Info"
    Write-ColorOutput "  Domain Name    : $DomainName" -Type "Info"
    Write-ColorOutput "  Current Name   : $env:COMPUTERNAME" -Type "Info"
    
    if ($NewComputerName) {
        Write-ColorOutput "  New Name       : $NewComputerName" -Type "Info"
    }
    
    if ($OUPath) {
        Write-ColorOutput "  Target OU      : $OUPath" -Type "Info"
    }
    
    Write-ColorOutput "  Auto Restart   : $Restart" -Type "Info"
    Write-Host ""

    # Confirm action if not using -WhatIf
    if ($PSCmdlet.ShouldProcess($DomainName, "Join computer to domain")) {
        Write-ColorOutput "Joining domain: $DomainName..." -Type "Info"
        
        try {
            Add-Computer @addComputerParams -ErrorAction Stop
            
            Write-Host ""
            Write-ColorOutput "========================================" -Type "Success"
            Write-ColorOutput "  Domain Join Successful!              " -Type "Success"
            Write-ColorOutput "========================================" -Type "Success"
            
            if ($Restart) {
                Write-ColorOutput "Computer will restart in 10 seconds..." -Type "Warning"
            } else {
                Write-ColorOutput "Please restart the computer to complete domain join." -Type "Warning"
            }
            
        } catch {
            Write-ColorOutput "Failed to join domain: $_" -Type "Error"
            
            # Provide additional troubleshooting information
            Write-Host ""
            Write-ColorOutput "Troubleshooting Tips:" -Type "Warning"
            Write-ColorOutput "1. Verify domain name is correct and reachable" -Type "Warning"
            Write-ColorOutput "2. Ensure DNS is configured properly" -Type "Warning"
            Write-ColorOutput "3. Verify credentials have permission to join computers" -Type "Warning"
            Write-ColorOutput "4. Check if OU path is correct (if specified)" -Type "Warning"
            Write-ColorOutput "5. Verify network connectivity to domain controller" -Type "Warning"
            
            exit 1
        }
    }

} catch {
    Write-ColorOutput "An unexpected error occurred: $_" -Type "Error"
    exit 1
}
