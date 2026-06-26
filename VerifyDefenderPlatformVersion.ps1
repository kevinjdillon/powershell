<#
.SYNOPSIS
Verifies Microsoft Defender Antivirus platform and engine compliance, applies updates when required, and logs all actions.

.DESCRIPTION
This script is designed for Azure Policy and local remediation workflows. It checks installed
Defender platform and engine versions against configured minimums. If either component is out of
compliance, the script downloads and installs the corresponding update package, waits for
installation to finish, rechecks versions, and records outcomes in a timestamped log file.
#>


# =========================================
# CONFIGURATION
# =========================================
$MinPlatformVersion = [version]"4.18.25010.11"
$MinEngineVersion   = [version]"1.1.25020.1007"

$dir = "C:\Windows\Temp\DefenderUpdate"
$PlatformDownloadUrl = "https://mdav.uss.endpoint.security.microsoft.scloud/packages/?package=platform&arch=x64"
$PlatformDownloadPath = "$dir\defender_platform_update.exe"
$EngineDownloadUrl = "https://mdav.uss.endpoint.security.microsoft.scloud/packages/?arch=x64"
$EngineDownloadPath = "$dir\defender_engine_update.exe"
$LogFile = "$dir\defender_update_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$ComplianceFlagFile = "$dir\DefenderVersionCompliant.flag"

# =========================================
# FUNCTION: Write Timestamped Log Entry
# =========================================
function Write-Log {
    param (
        [string]$Message
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] $Message"
    
    # Write to console output stream
    Write-Output $logEntry
    
    # Append to log file
    Add-Content -Path $LogFile -Value $logEntry -ErrorAction SilentlyContinue
}

# =========================================
# FUNCTION: Get Current Defender Versions
# =========================================

function Get-DefenderVersions {
    $status = Get-MpComputerStatus

    return @{
        Platform = [version]$status.AMProductVersion
        Engine   = [version]$status.AMEngineVersion
    }
}

# =========================================
# FUNCTION: Evaluate Platform Compliance
# =========================================
function Test-PlatformCompliance {
    param (
        [version]$CurrentPlatform
    )

    return $CurrentPlatform -ge $MinPlatformVersion
}

# =========================================
# FUNCTION: Evaluate Engine Compliance
# =========================================
function Test-EngineCompliance {
    param (
        [version]$CurrentEngine
    )

    return $CurrentEngine -ge $MinEngineVersion
}

# =========================================
# FUNCTION: Ensure Compliance Marker File
# =========================================
function Ensure-ComplianceMarkerFile {
    if (-not (Test-Path -Path $ComplianceFlagFile)) {
        New-Item -Path $ComplianceFlagFile -ItemType File -Force | Out-Null
        Write-Log "Compliance marker file created: $ComplianceFlagFile"
    }
    else {
        Write-Log "Compliance marker file already exists: $ComplianceFlagFile"
    }
}

# =========================================
# EXECUTION FLOW
# =========================================

# If compliance marker file exists, exit early
if (Test-Path -Path $ComplianceFlagFile) {
    exit 0
}

# Ensure update/log directory exists
New-Item -ItemType Directory -Path $dir -Force | Out-Null

# Start execution log
Write-Log "=== Defender Version Update Script Started ==="

# Read current Defender versions
$versions = Get-DefenderVersions
Write-Log "Current Platform Version: $($versions.Platform)"
Write-Log "Current Engine Version:   $($versions.Engine)"

# Evaluate compliance for each component
$platformOK = Test-PlatformCompliance -CurrentPlatform $versions.Platform
$engineOK   = Test-EngineCompliance -CurrentEngine $versions.Engine

if ($platformOK -and $engineOK) {
    Write-Log "Defender versions meet minimum requirements. No action needed."
    Ensure-ComplianceMarkerFile
    Write-Log "=== Script Execution Completed Successfully ==="
    exit 0
}

Write-Log "Defender versions below required threshold. Updating..."

# Download and install platform update if needed
if (-not $platformOK) {
    Write-Log "Downloading Platform update (Required version: $MinPlatformVersion)..."
    try {
        Invoke-WebRequest -Uri $PlatformDownloadUrl -OutFile $PlatformDownloadPath -UseBasicParsing
        Write-Log "Platform update downloaded successfully."
    }
    catch {
        Write-Log "Invoke-WebRequest failed for Platform - trying BITS..."
        Start-BitsTransfer -Source $PlatformDownloadUrl -Destination $PlatformDownloadPath
        Write-Log "Platform update downloaded successfully."
    }
    
    Write-Log "Installing Platform update..."
    Start-Process -FilePath $PlatformDownloadPath -ArgumentList "/quiet", "/norestart" -Wait
    Write-Log "Platform update installation completed."
}

# Download and install engine update if needed
if (-not $engineOK) {
    Write-Log "Downloading Engine update (Required version: $MinEngineVersion)..."
    try {
        Invoke-WebRequest -Uri $EngineDownloadUrl -OutFile $EngineDownloadPath -UseBasicParsing
        Write-Log "Engine update downloaded successfully."
    }
    catch {
        Write-Log "Invoke-WebRequest failed for Engine - trying BITS..."
        Start-BitsTransfer -Source $EngineDownloadUrl -Destination $EngineDownloadPath
        Write-Log "Engine update downloaded successfully."
    }
    
    Write-Log "Installing Engine update..."
    Start-Process -FilePath $EngineDownloadPath -ArgumentList "/quiet", "/norestart" -Wait
    Write-Log "Engine update installation completed."
}

# Allow Defender services time to report updated versions
Start-Sleep -Seconds 20

# Re-read versions after install operations
Write-Log "Rechecking Defender versions after update..."
$updatedVersions = Get-DefenderVersions
Write-Log "Updated Platform Version: $($updatedVersions.Platform)"
Write-Log "Updated Engine Version:   $($updatedVersions.Engine)"

# Evaluate post-install compliance
$platformCompliant = Test-PlatformCompliance -CurrentPlatform $updatedVersions.Platform
$engineCompliant   = Test-EngineCompliance -CurrentEngine $updatedVersions.Engine

if ($platformCompliant) {
    Write-Log "Platform version now meets compliance requirement."
}
else {
    Write-Log "Platform version still below required threshold: $MinPlatformVersion"
}

if ($engineCompliant) {
    Write-Log "Engine version now meets compliance requirement."
}
else {
    Write-Log "Engine version still below required threshold: $MinEngineVersion"
}

if ($platformCompliant -and $engineCompliant) {
    Write-Log "All Defender components now meet compliance requirements."
    Ensure-ComplianceMarkerFile
    Write-Log "=== Script Execution Completed Successfully ==="
}
else {
    Write-Log "Some Defender components still require updates."
    Write-Log "=== Script Execution Completed with Warnings ==="
}
