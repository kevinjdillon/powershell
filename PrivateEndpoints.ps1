<#
.SYNOPSIS
    Audits Azure Private Endpoints across a subscription.

.DESCRIPTION
    This script performs a comprehensive audit of private endpoints in an Azure subscription, including:
    - All resources that support private endpoints
    - Private endpoint configurations
    - DNS recordsets validation
    - Private DNS zones association
    - VNET links for each private DNS zone
    
    Results are exported to CSV format with semicolon-separated multi-value fields.
    Errors are logged to a separate log file.

.PARAMETER SubscriptionId
    The Azure Subscription ID to audit. If not provided, uses the current subscription context.

.PARAMETER OutputPath
    The directory path where output files will be saved. Defaults to current directory.

.EXAMPLE
    .\PrivateEndpoints.ps1 -SubscriptionId "12345678-1234-1234-1234-123456789012"
    
.EXAMPLE
    .\PrivateEndpoints.ps1 -SubscriptionId "12345678-1234-1234-1234-123456789012" -OutputPath "C:\Audits"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "."
)

# Ensure output path exists
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

# Generate timestamp for output files
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$csvPath = Join-Path $OutputPath "PrivateEndpoint-Audit-$timestamp.csv"
$errorLogPath = Join-Path $OutputPath "PrivateEndpoint-Audit-Errors-$timestamp.log"

# Initialize error log
"Private Endpoint Audit Error Log - $(Get-Date)" | Out-File -FilePath $errorLogPath
"=" * 80 | Out-File -FilePath $errorLogPath -Append

# Function to log errors
function Write-ErrorLog {
    param(
        [string]$ResourceName,
        [string]$ResourceType,
        [string]$ErrorMessage
    )
    
    $logEntry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Resource: $ResourceName | Type: $ResourceType | Error: $ErrorMessage"
    $logEntry | Out-File -FilePath $errorLogPath -Append
    Write-Warning $logEntry
}

# Check if Az module is installed
Write-Host "Checking for Az PowerShell module..." -ForegroundColor Cyan
if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
    Write-Error "Az PowerShell module is not installed. Please install it using: Install-Module -Name Az -AllowClobber -Scope CurrentUser"
    exit 1
}

# Check Azure authentication
Write-Host "Checking Azure authentication..." -ForegroundColor Cyan
try {
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "Not authenticated to Azure. Please run Connect-AzAccount" -ForegroundColor Yellow
        Connect-AzAccount
        $context = Get-AzContext
    }
    Write-Host "Authenticated as: $($context.Account.Id)" -ForegroundColor Green
}
catch {
    Write-Error "Failed to authenticate to Azure: $_"
    exit 1
}

# Set subscription context
if ($SubscriptionId) {
    Write-Host "Setting subscription context to: $SubscriptionId" -ForegroundColor Cyan
    try {
        Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
    }
    catch {
        Write-Error "Failed to set subscription context: $_"
        exit 1
    }
}

$currentContext = Get-AzContext
Write-Host "Auditing subscription: $($currentContext.Subscription.Name) ($($currentContext.Subscription.Id))" -ForegroundColor Green
Write-Host ""

# Initialize results array
$results = @()

# Resource types that support private endpoints
$resourceTypesToAudit = @(
    'Microsoft.Storage/storageAccounts'
    'Microsoft.KeyVault/vaults'
    'Microsoft.Sql/servers'
    'Microsoft.DocumentDB/databaseAccounts'
    'Microsoft.ContainerRegistry/registries'
    'Microsoft.Web/sites'
    'Microsoft.ContainerService/managedClusters'
    'Microsoft.EventHub/namespaces'
    'Microsoft.ServiceBus/namespaces'
    'Microsoft.Synapse/workspaces'
    'Microsoft.CognitiveServices/accounts'
    'Microsoft.MachineLearningServices/workspaces'
    'Microsoft.DBforPostgreSQL/servers'
    'Microsoft.DBforMySQL/servers'
    'Microsoft.DBforMariaDB/servers'
    'Microsoft.Devices/IotHubs'
    'Microsoft.SignalRService/SignalR'
    'Microsoft.Databricks/workspaces'
    'Microsoft.HealthcareApis/services'
    'Microsoft.Search/searchServices'
    'Microsoft.HybridCompute/privateLinkScopes'
)

Write-Host "Querying all resources in subscription..." -ForegroundColor Cyan
try {
    $allResources = Get-AzResource | Where-Object { $_.ResourceType -in $resourceTypesToAudit }
    Write-Host "Found $($allResources.Count) resources that support private endpoints" -ForegroundColor Green
}
catch {
    Write-Error "Failed to query resources: $_"
    exit 1
}

if ($allResources.Count -eq 0) {
    Write-Host "No resources found that support private endpoints in this subscription." -ForegroundColor Yellow
    exit 0
}

# Process each resource
$counter = 0
foreach ($resource in $allResources) {
    $counter++
    $percentComplete = [math]::Round(($counter / $allResources.Count) * 100, 2)
    
    Write-Progress -Activity "Auditing Private Endpoints" `
                   -Status "Processing $($resource.Name) ($counter of $($allResources.Count))" `
                   -PercentComplete $percentComplete
    
    Write-Host "[$counter/$($allResources.Count)] Processing: $($resource.Name) ($($resource.ResourceType))" -ForegroundColor Cyan
    
    try {
        # Get private endpoint connections for the resource
        $privateEndpoints = @()
        
        # Query private endpoint connections differently based on resource type
        try {
            $privateEndpoints = Get-AzPrivateEndpointConnection -PrivateLinkResourceId $resource.ResourceId -ErrorAction SilentlyContinue
        }
        catch {
            # Some resources may not support this cmdlet, try alternative method
            Write-Verbose "Standard PE query failed for $($resource.Name), trying alternative method"
        }
        
        if ($privateEndpoints.Count -eq 0) {
            # No private endpoints configured for this resource
            $resultObject = [PSCustomObject]@{
                ResourceName = $resource.Name
                ResourceType = $resource.ResourceType
                ResourceGroup = $resource.ResourceGroupName
                PrivateEndpointName = "None"
                PrivateEndpointStatus = "N/A"
                PrivateIPAddress = "N/A"
                DNSRecordExists = "N/A"
                PrivateDNSZoneName = "N/A"
                DNSZoneResourceGroup = "N/A"
                VNETLinks = "N/A"
                VNETLinkStatus = "N/A"
            }
            $results += $resultObject
            continue
        }
        
        # Process each private endpoint
        foreach ($peConnection in $privateEndpoints) {
            try {
                # Get the private endpoint resource
                $peId = $peConnection.PrivateEndpoint.Id
                if (-not $peId) {
                    Write-Verbose "No PE ID found for connection"
                    continue
                }
                
                # Extract PE details
                $peResourceId = $peId
                $peIdParts = $peId -split '/'
                $peResourceGroup = $peIdParts[4]
                $peName = $peIdParts[-1]
                
                # Get full private endpoint details
                $pe = Get-AzPrivateEndpoint -ResourceGroupName $peResourceGroup -Name $peName -ErrorAction Stop
                
                # Get private IP address from network interface
                $privateIP = "Unknown"
                if ($pe.NetworkInterfaces.Count -gt 0) {
                    $nicId = $pe.NetworkInterfaces[0].Id
                    $nicIdParts = $nicId -split '/'
                    $nicRg = $nicIdParts[4]
                    $nicName = $nicIdParts[-1]
                    
                    try {
                        $nic = Get-AzNetworkInterface -ResourceGroupName $nicRg -Name $nicName -ErrorAction Stop
                        if ($nic.IpConfigurations.Count -gt 0) {
                            $privateIP = $nic.IpConfigurations[0].PrivateIpAddress
                        }
                    }
                    catch {
                        Write-ErrorLog -ResourceName $resource.Name -ResourceType $resource.ResourceType `
                                      -ErrorMessage "Failed to get NIC details: $_"
                    }
                }
                
                # Get DNS zone groups
                $dnsZoneName = "None"
                $dnsZoneRG = "N/A"
                $dnsRecordExists = "Unknown"
                $vnetLinks = "None"
                $vnetLinkStatus = "N/A"
                
                # Query DNS zone groups using the proper cmdlet
                try {
                    $dnsZoneGroups = Get-AzPrivateDnsZoneGroup -ResourceGroupName $peResourceGroup `
                                                                -PrivateEndpointName $peName `
                                                                -ErrorAction SilentlyContinue
                    
                    if ($dnsZoneGroups -and $dnsZoneGroups.Count -gt 0) {
                        $dnsZones = @()
                        $dnsZoneRGs = @()
                        $allVnetLinks = @()
                        $allVnetLinkStatuses = @()
                        
                        foreach ($zoneGroup in $dnsZoneGroups) {
                            foreach ($dnsConfig in $zoneGroup.PrivateDnsZoneConfigs) {
                                $privateDnsZoneId = $dnsConfig.PrivateDnsZoneId
                                
                                if ($privateDnsZoneId) {
                                    $dnsZoneIdParts = $privateDnsZoneId -split '/'
                                    $dnsZoneRGName = $dnsZoneIdParts[4]
                                    $dnsZoneNameItem = $dnsZoneIdParts[-1]
                                    
                                    $dnsZones += $dnsZoneNameItem
                                    $dnsZoneRGs += $dnsZoneRGName
                                    
                                    # Check if DNS records exist
                                    try {
                                        $recordSets = Get-AzPrivateDnsRecordSet -ResourceGroupName $dnsZoneRGName `
                                                                                -ZoneName $dnsZoneNameItem `
                                                                                -ErrorAction Stop
                                        $dnsRecordExists = if ($recordSets.Count -gt 0) { "Yes" } else { "No" }
                                    }
                                    catch {
                                        $dnsRecordExists = "Error checking"
                                        Write-ErrorLog -ResourceName $resource.Name -ResourceType $resource.ResourceType `
                                                      -ErrorMessage "Failed to check DNS records: $_"
                                    }
                                    
                                    # Get VNET links for this DNS zone
                                    try {
                                        $vnetLinksList = Get-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $dnsZoneRGName `
                                                                                             -ZoneName $dnsZoneNameItem `
                                                                                             -ErrorAction Stop
                                        
                                        if ($vnetLinksList.Count -gt 0) {
                                            foreach ($link in $vnetLinksList) {
                                                $vnetName = ($link.VirtualNetworkId -split '/')[-1]
                                                $allVnetLinks += $vnetName
                                                $linkStatus = if ($link.RegistrationEnabled) { "AutoReg-Enabled" } else { "Enabled" }
                                                $allVnetLinkStatuses += $linkStatus
                                            }
                                        }
                                    }
                                    catch {
                                        Write-ErrorLog -ResourceName $resource.Name -ResourceType $resource.ResourceType `
                                                      -ErrorMessage "Failed to get VNET links: $_"
                                    }
                                }
                            }
                        }
                        
                        $dnsZoneName = if ($dnsZones.Count -gt 0) { $dnsZones -join ';' } else { "None" }
                        $dnsZoneRG = if ($dnsZoneRGs.Count -gt 0) { $dnsZoneRGs -join ';' } else { "N/A" }
                        $vnetLinks = if ($allVnetLinks.Count -gt 0) { $allVnetLinks -join ';' } else { "None" }
                        $vnetLinkStatus = if ($allVnetLinkStatuses.Count -gt 0) { $allVnetLinkStatuses -join ';' } else { "N/A" }
                    }
                }
                catch {
                    Write-ErrorLog -ResourceName $resource.Name -ResourceType $resource.ResourceType `
                                  -ErrorMessage "Failed to get DNS zone groups: $_"
                }
                
                # Create result object
                $resultObject = [PSCustomObject]@{
                    ResourceName = $resource.Name
                    ResourceType = $resource.ResourceType
                    ResourceGroup = $resource.ResourceGroupName
                    PrivateEndpointName = $peName
                    PrivateEndpointStatus = $peConnection.PrivateLinkServiceConnectionState.Status
                    PrivateIPAddress = $privateIP
                    DNSRecordExists = $dnsRecordExists
                    PrivateDNSZoneName = $dnsZoneName
                    DNSZoneResourceGroup = $dnsZoneRG
                    VNETLinks = $vnetLinks
                    VNETLinkStatus = $vnetLinkStatus
                }
                
                $results += $resultObject
            }
            catch {
                Write-ErrorLog -ResourceName $resource.Name -ResourceType $resource.ResourceType `
                              -ErrorMessage "Failed to process private endpoint: $_"
                
                # Add error entry to results
                $resultObject = [PSCustomObject]@{
                    ResourceName = $resource.Name
                    ResourceType = $resource.ResourceType
                    ResourceGroup = $resource.ResourceGroupName
                    PrivateEndpointName = "Error"
                    PrivateEndpointStatus = "Error processing"
                    PrivateIPAddress = "Error"
                    DNSRecordExists = "Error"
                    PrivateDNSZoneName = "Error"
                    DNSZoneResourceGroup = "Error"
                    VNETLinks = "Error"
                    VNETLinkStatus = "Error"
                }
                $results += $resultObject
            }
        }
    }
    catch {
        Write-ErrorLog -ResourceName $resource.Name -ResourceType $resource.ResourceType `
                      -ErrorMessage "Failed to query private endpoints: $_"
        
        # Add error entry to results
        $resultObject = [PSCustomObject]@{
            ResourceName = $resource.Name
            ResourceType = $resource.ResourceType
            ResourceGroup = $resource.ResourceGroupName
            PrivateEndpointName = "Error"
            PrivateEndpointStatus = "Error querying"
            PrivateIPAddress = "Error"
            DNSRecordExists = "Error"
            PrivateDNSZoneName = "Error"
            DNSZoneResourceGroup = "Error"
            VNETLinks = "Error"
            VNETLinkStatus = "Error"
        }
        $results += $resultObject
    }
}

Write-Progress -Activity "Auditing Private Endpoints" -Completed

# Export results to CSV
Write-Host ""
Write-Host "Exporting results to CSV..." -ForegroundColor Cyan
$results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

# Display summary
Write-Host ""
Write-Host "===============================================" -ForegroundColor Green
Write-Host "Private Endpoint Audit Complete" -ForegroundColor Green
Write-Host "===============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Total resources audited: $($allResources.Count)" -ForegroundColor White
Write-Host "  Resources with private endpoints: $(@($results | Where-Object { $_.PrivateEndpointName -ne 'None' -and $_.PrivateEndpointName -ne 'Error' }).Count)" -ForegroundColor White
Write-Host "  Resources without private endpoints: $(@($results | Where-Object { $_.PrivateEndpointName -eq 'None' }).Count)" -ForegroundColor White
Write-Host "  Resources with errors: $(@($results | Where-Object { $_.PrivateEndpointName -eq 'Error' }).Count)" -ForegroundColor Yellow
Write-Host ""
Write-Host "Output files:" -ForegroundColor Cyan
Write-Host "  CSV Report: $csvPath" -ForegroundColor White
Write-Host "  Error Log: $errorLogPath" -ForegroundColor White
Write-Host ""