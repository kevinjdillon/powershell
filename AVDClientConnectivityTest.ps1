<#
.SYNOPSIS
    Tests TCP 443 connectivity to Azure Virtual Desktop (AVD) endpoints in Azure US Government cloud.

.DESCRIPTION
    This script tests connectivity over TCP port 443 to required AVD endpoints including
    Azure US Government URLs and various Microsoft services. For wildcard domains, it tests
    against known subdomains.

.PARAMETER ExportPath
    Optional path to export results to a CSV file.

.EXAMPLE
    .\AVDClientConnectivityTest.ps1
    
.EXAMPLE
    .\AVDClientConnectivityTest.ps1 -ExportPath "C:\Reports\AVDConnectivity.csv"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$ExportPath
)

# Define URLs to test
$endpoints = @(
    @{URL = "login.microsoftonline.us"; Description = "Azure AD Authentication (US Gov)"},
    @{URL = "rdgateway.wvd.azure.us"; Description = "AVD Gateway (*.wvd.azure.us)"},
    @{URL = "rdbroker.wvd.azure.us"; Description = "AVD Broker (*.wvd.azure.us)"},
    @{URL = "rdweb.wvd.azure.us"; Description = "AVD Web (*.wvd.azure.us)"},
    @{URL = "rddiagnostics.wvd.azure.us"; Description = "AVD Diagnostics (*.wvd.azure.us)"},
    @{URL = "eh-prod.servicebus.usgovcloudapi.net"; Description = "Service Bus (*.servicebus.usgovcloudapi.net)"},
    @{URL = "go.microsoft.com"; Description = "Microsoft URL Shortener"},
    @{URL = "aka.ms"; Description = "Microsoft Link Service"},
    @{URL = "learn.microsoft.com"; Description = "Microsoft Learn"},
    @{URL = "privacy.microsoft.com"; Description = "Microsoft Privacy"},
    @{URL = "r.cdn.office.net"; Description = "Office CDN (*.cdn.office.net)"},
    @{URL = "graph.microsoft.com"; Description = "Microsoft Graph API"},
    @{URL = "windows.cloud.microsoft"; Description = "Windows Cloud Service"},
    @{URL = "windows365.microsoft.com"; Description = "Windows 365"},
    @{URL = "ecs.office.com"; Description = "Office Configuration Service"}
)

# Results array
$results = @()

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "AVD Client Connectivity Test" -ForegroundColor Cyan
Write-Host "Testing TCP 443 Connectivity" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$successCount = 0
$failureCount = 0

foreach ($endpoint in $endpoints) {
    Write-Host "Testing: $($endpoint.URL)..." -NoNewline
    
    try {
        # Test connectivity with 5 second timeout
        $testResult = Test-NetConnection -ComputerName $endpoint.URL -Port 443 -InformationLevel Detailed -WarningAction SilentlyContinue -ErrorAction Stop
        
        if ($testResult.TcpTestSucceeded) {
            Write-Host " SUCCESS" -ForegroundColor Green
            $status = "Success"
            $successCount++
            
            # Get response time if available
            $responseTime = if ($testResult.PingSucceeded) { 
                "$($testResult.PingReplyDetails.RoundtripTime) ms" 
            } else { 
                "N/A" 
            }
        } else {
            Write-Host " FAILED" -ForegroundColor Red
            $status = "Failed - Port 443 not reachable"
            $failureCount++
            $responseTime = "N/A"
        }
        
        $dnsResolved = if ($testResult.ResolvedAddresses) { "Yes" } else { "No" }
        $ipAddress = if ($testResult.ResolvedAddresses) { 
            ($testResult.ResolvedAddresses | Select-Object -First 1).IPAddressToString 
        } else { 
            "N/A" 
        }
        
    } catch {
        Write-Host " FAILED" -ForegroundColor Red
        $status = "Failed - $($_.Exception.Message)"
        $failureCount++
        $responseTime = "N/A"
        $dnsResolved = "No"
        $ipAddress = "N/A"
    }
    
    # Store result
    $results += [PSCustomObject]@{
        URL = $endpoint.URL
        Description = $endpoint.Description
        Status = $status
        DNSResolved = $dnsResolved
        IPAddress = $ipAddress
        ResponseTime = $responseTime
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
}

# Display summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total Endpoints Tested: $($endpoints.Count)" -ForegroundColor White
Write-Host "Successful: $successCount" -ForegroundColor Green
Write-Host "Failed: $failureCount" -ForegroundColor $(if ($failureCount -gt 0) { "Red" } else { "Green" })
Write-Host "Success Rate: $([math]::Round(($successCount / $endpoints.Count) * 100, 2))%" -ForegroundColor White

# Display detailed results table
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Detailed Results" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$results | Format-Table -Property URL, Status, DNSResolved, IPAddress, ResponseTime -AutoSize

# Export to CSV if path provided
if ($ExportPath) {
    try {
        $results | Export-Csv -Path $ExportPath -NoTypeInformation -Force
        Write-Host "`nResults exported to: $ExportPath" -ForegroundColor Green
    } catch {
        Write-Host "`nFailed to export results: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Return overall status
if ($failureCount -eq 0) {
    Write-Host "`n[OVERALL STATUS] All connectivity tests PASSED" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n[OVERALL STATUS] Some connectivity tests FAILED - Review results above" -ForegroundColor Yellow
    exit 1
}
