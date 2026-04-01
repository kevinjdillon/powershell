<#
.SYNOPSIS
    Manages Defender for Cloud pricing plans for Azure VMs.

.DESCRIPTION
    This script checks or removes Defender for Cloud pricing plans assigned to specific VMs,
    allowing them to inherit the pricing plan from the subscription or resource group level.
    
    This is particularly useful when pricing plans were set to 'Free' by Azure Policy
    (e.g., "Configure Azure Defender for Servers to be disabled for all resources").
    Such policies can cause VMs to be unprotected if the subscription/resource group level
    pricing plan is set to 'Standard'.
    
    After removing the policy assignment, this script removes the resource-level pricing plan,
    allowing VMs to inherit the Standard plan from higher levels.

.PARAMETER ResourceGroupName
    The name of the resource group containing the target VM.
    Required when using SpecificVM parameter set.

.PARAMETER VMName
    The name of the target VM.
    Required when using SpecificVM parameter set.

.PARAMETER SearchAll
    Search for all VMs across subscriptions that have non-inherited pricing plans.
    Presents an interactive menu to select which VMs to process.

.PARAMETER CheckOnly
    Only display current pricing plan information without making any changes.
    Use this to audit VM pricing configurations.

.PARAMETER Force
    Skip all confirmation prompts and process immediately.
    Use with caution.

.EXAMPLE
    .\RemoveDefenderPricingPlanfromVM.ps1 -ResourceGroupName "rg-prod" -VMName "vm-web01"
    
    Checks and removes the pricing plan from a specific VM with confirmation prompts.

.EXAMPLE
    .\RemoveDefenderPricingPlanfromVM.ps1 -ResourceGroupName "rg-prod" -VMName "vm-web01" -CheckOnly
    
    Only displays the current pricing plan status without making changes.

.EXAMPLE
    .\RemoveDefenderPricingPlanfromVM.ps1 -SearchAll
    
    Searches for all VMs with non-inherited pricing plans and presents an interactive menu
    to select which VMs to process.

.EXAMPLE
    .\RemoveDefenderPricingPlanfromVM.ps1 -SearchAll -Force
    
    Searches for all VMs with non-inherited pricing plans and processes all of them
    without confirmation prompts.

.EXAMPLE
    .\RemoveDefenderPricingPlanfromVM.ps1 -SearchAll -CheckOnly
    
    Searches for and displays all VMs with non-inherited pricing plans without making changes.

.NOTES
    Requires:
    - Az.Accounts module
    - Az.Compute module
    - Az.ResourceGraph module (for SearchAll mode)
    - Appropriate Azure RBAC permissions to read/modify Security pricing configurations
#>

[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'SpecificVM')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'SpecificVM')]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true, ParameterSetName = 'SpecificVM')]
    [ValidateNotNullOrEmpty()]
    [string]$VMName,

    [Parameter(Mandatory = $true, ParameterSetName = 'SearchAll')]
    [switch]$SearchAll,

    [Parameter(Mandatory = $false)]
    [switch]$CheckOnly,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

#region Helper Functions

function Write-ColorOutput {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Type = 'Info'
    )
    
    $color = switch ($Type) {
        'Info'    { 'Cyan' }
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error'   { 'Red' }
    }
    
    Write-Host $Message -ForegroundColor $color
}

function Test-Prerequisites {
    Write-Verbose "Checking prerequisites..."
    
    # Check Azure login
    try {
        $context = Get-AzContext -ErrorAction Stop
        if (-not $context) {
            throw "Not logged in to Azure"
        }
        Write-Verbose "Azure context: $($context.Account.Id) in subscription $($context.Subscription.Name)"
    }
    catch {
        Write-ColorOutput "ERROR: Not logged in to Azure. Please run 'Connect-AzAccount' first." -Type Error
        return $false
    }
    
    # Check required modules
    $requiredModules = @('Az.Accounts', 'Az.Compute')
    if ($SearchAll) {
        $requiredModules += 'Az.ResourceGraph'
    }
    
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -Name $module -ListAvailable)) {
            Write-ColorOutput "ERROR: Required module '$module' is not installed. Please run 'Install-Module $module'." -Type Error
            return $false
        }
        
        if (-not (Get-Module -Name $module)) {
            Write-Verbose "Importing module: $module"
            Import-Module $module -ErrorAction SilentlyContinue
        }
    }
    
    return $true
}

function Get-DefenderPricingPlan {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceId
    )
    
    try {
        $response = Invoke-AzRestMethod -Method GET -Path "$ResourceId/providers/Microsoft.Security/pricings/VirtualMachines?api-version=2024-01-01"
        
        if ($response.StatusCode -eq 200) {
            $content = $response.Content | ConvertFrom-Json
            return $content
        }
        elseif ($response.StatusCode -eq 404) {
            # No pricing plan defined at resource level (inheriting)
            return $null
        }
        else {
            Write-ColorOutput "WARNING: Unexpected status code $($response.StatusCode) when checking pricing plan" -Type Warning
            return $null
        }
    }
    catch {
        Write-ColorOutput "ERROR: Failed to get pricing plan: $($_.Exception.Message)" -Type Error
        return $null
    }
}

function Remove-DefenderPricingPlan {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceId,
        
        [Parameter(Mandatory = $true)]
        [string]$VMName
    )
    
    if ($PSCmdlet.ShouldProcess($VMName, "Remove Defender for Cloud pricing plan")) {
        try {
            $response = Invoke-AzRestMethod -Method DELETE -Path "$ResourceId/providers/Microsoft.Security/pricings/VirtualMachines?api-version=2024-01-01"
            
            if ($response.StatusCode -eq 200 -or $response.StatusCode -eq 204) {
                return @{
                    Success = $true
                    Message = "Successfully removed pricing plan"
                }
            }
            else {
                return @{
                    Success = $false
                    Message = "Unexpected status code: $($response.StatusCode)"
                }
            }
        }
        catch {
            return @{
                Success = $false
                Message = $_.Exception.Message
            }
        }
    }
    else {
        return @{
            Success = $false
            Message = "Operation cancelled by WhatIf"
        }
    }
}

function Show-PricingPlanInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMName,
        
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroup,
        
        [Parameter(Mandatory = $false)]
        $PricingPlan
    )
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "VM: $VMName" -ForegroundColor White
    Write-Host "Resource Group: $ResourceGroup" -ForegroundColor White
    Write-Host "========================================" -ForegroundColor Cyan
    
    if ($null -eq $PricingPlan) {
        Write-ColorOutput "Status: Pricing plan is INHERITED from subscription/resource group level" -Type Success
        Write-Host "No resource-level pricing plan is defined." -ForegroundColor Gray
    }
    else {
        $props = $PricingPlan.properties
        Write-ColorOutput "Status: Pricing plan is ASSIGNED at resource level" -Type Warning
        Write-Host "Pricing Tier: $($props.pricingTier)" -ForegroundColor White
        if ($props.subPlan) {
            Write-Host "Sub Plan: $($props.subPlan)" -ForegroundColor White
        }
        Write-Host "Inherited: $($props.inherited)" -ForegroundColor White
        if ($props.inheritedFrom) {
            Write-Host "Inherited From: $($props.inheritedFrom)" -ForegroundColor White
        }
    }
    Write-Host ""
}

function Search-DefenderPricingPlans {
    Write-Verbose "Searching for VMs with non-inherited pricing plans..."
    
    $query = @"
SecurityResources
| where type =~ 'microsoft.security/pricings'
| where name =~ 'VirtualMachines'
| where properties.inherited == false
| project
    resourceId = id,
    pricingTier = properties.pricingTier,
    subPlan = properties.subPlan,
    inherited = properties.inherited
| extend vmResourceId = substring(resourceId, 0, indexof(resourceId, '/providers/Microsoft.Security'))
| join kind=inner (
    Resources
    | where type =~ 'microsoft.compute/virtualmachines'
    | project vmResourceId = id, vmName = name, resourceGroup
) on vmResourceId
| project vmName, resourceGroup, vmResourceId, pricingTier, subPlan, inherited
"@
    
    try {
        $results = Search-AzGraph -Query $query
        return $results
    }
    catch {
        Write-ColorOutput "ERROR: Failed to search resource graph: $($_.Exception.Message)" -Type Error
        return $null
    }
}

function Show-VMSelectionMenu {
    param(
        [Parameter(Mandatory = $true)]
        [array]$VMs
    )
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "VMs with Non-Inherited Pricing Plans" -ForegroundColor White
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Display VMs in a table format
    $index = 1
    $VMs | ForEach-Object {
        Write-Host ("{0,3}. " -f $index) -NoNewline -ForegroundColor Yellow
        Write-Host ("{0,-30} " -f $_.vmName) -NoNewline -ForegroundColor White
        Write-Host ("RG: {0,-30} " -f $_.resourceGroup) -NoNewline -ForegroundColor Gray
        Write-Host ("Tier: {0}" -f $_.pricingTier) -ForegroundColor Cyan
        $index++
    }
    
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Cyan
    Write-Host "  [A] Process All VMs" -ForegroundColor Yellow
    Write-Host "  [S] Select specific VMs (e.g., 1,3,5 or 1-5)" -ForegroundColor Yellow
    Write-Host "  [C] Cancel" -ForegroundColor Yellow
    Write-Host ""
    
    $choice = Read-Host "Enter your choice"
    
    return $choice
}

function Get-SelectedVMs {
    param(
        [Parameter(Mandatory = $true)]
        [array]$AllVMs,
        
        [Parameter(Mandatory = $true)]
        [string]$Selection
    )
    
    $selectedIndices = @()
    
    # Parse selection (supports: 1,3,5 or 1-5 or combinations)
    $parts = $Selection -split ','
    foreach ($part in $parts) {
        $part = $part.Trim()
        if ($part -match '^(\d+)-(\d+)$') {
            # Range (e.g., 1-5)
            $start = [int]$Matches[1]
            $end = [int]$Matches[2]
            $selectedIndices += $start..$end
        }
        elseif ($part -match '^\d+$') {
            # Single number
            $selectedIndices += [int]$part
        }
    }
    
    # Validate indices and return selected VMs
    $validVMs = @()
    foreach ($index in $selectedIndices) {
        if ($index -ge 1 -and $index -le $AllVMs.Count) {
            $validVMs += $AllVMs[$index - 1]
        }
        else {
            Write-ColorOutput "WARNING: Invalid index $index (valid range: 1-$($AllVMs.Count))" -Type Warning
        }
    }
    
    return $validVMs
}

#endregion

#region Main Script Logic

# Check prerequisites
if (-not (Test-Prerequisites)) {
    exit 1
}

# Track results for summary
$processedVMs = @()
$successCount = 0
$failureCount = 0

if ($PSCmdlet.ParameterSetName -eq 'SpecificVM') {
    #region SpecificVM Mode
    
    Write-Verbose "Processing specific VM: $VMName in $ResourceGroupName"
    
    # Validate VM exists
    try {
        $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -ErrorAction Stop
        Write-Verbose "VM found: $($vm.Id)"
    }
    catch {
        Write-ColorOutput "ERROR: VM '$VMName' not found in resource group '$ResourceGroupName'" -Type Error
        Write-ColorOutput "Details: $($_.Exception.Message)" -Type Error
        exit 1
    }
    
    # Get current pricing plan
    $pricingPlan = Get-DefenderPricingPlan -ResourceId $vm.Id
    
    # Display current state
    Show-PricingPlanInfo -VMName $VMName -ResourceGroup $ResourceGroupName -PricingPlan $pricingPlan
    
    if ($CheckOnly) {
        Write-ColorOutput "Check-only mode: No changes made" -Type Info
        exit 0
    }
    
    # If no pricing plan at resource level, nothing to remove
    if ($null -eq $pricingPlan) {
        Write-ColorOutput "No action needed: VM is already inheriting pricing plan from higher level" -Type Success
        exit 0
    }
    
    # Confirm removal
    if (-not $Force -and -not $WhatIfPreference) {
        $confirmation = Read-Host "`nRemove the resource-level pricing plan from this VM? (Y/N)"
        if ($confirmation -ne 'Y' -and $confirmation -ne 'y') {
            Write-ColorOutput "Operation cancelled by user" -Type Warning
            exit 0
        }
    }
    
    # Remove pricing plan
    Write-ColorOutput "Removing pricing plan from VM..." -Type Info
    $result = Remove-DefenderPricingPlan -ResourceId $vm.Id -VMName $VMName
    
    if ($result.Success) {
        Write-ColorOutput $result.Message -Type Success
        Write-ColorOutput "VM will now inherit the Defender for Cloud pricing plan from subscription/resource group level" -Type Success
        
        # Verify removal
        Start-Sleep -Seconds 2
        $verifyPlan = Get-DefenderPricingPlan -ResourceId $vm.Id
        if ($null -eq $verifyPlan) {
            Write-ColorOutput "Verified: Pricing plan successfully removed" -Type Success
        }
    }
    else {
        Write-ColorOutput "Failed to remove pricing plan: $($result.Message)" -Type Error
        exit 1
    }
    
    #endregion
}
elseif ($PSCmdlet.ParameterSetName -eq 'SearchAll') {
    #region SearchAll Mode
    
    Write-ColorOutput "Searching for VMs with non-inherited pricing plans..." -Type Info
    
    $vmsWithPricing = Search-DefenderPricingPlans
    
    if ($null -eq $vmsWithPricing -or $vmsWithPricing.Count -eq 0) {
        Write-ColorOutput "No VMs found with non-inherited pricing plans" -Type Success
        Write-ColorOutput "All VMs are inheriting pricing plans from subscription/resource group level" -Type Info
        exit 0
    }
    
    Write-ColorOutput "Found $($vmsWithPricing.Count) VM(s) with non-inherited pricing plans" -Type Warning
    
    if ($CheckOnly) {
        # Just display the results
        Write-Host ""
        $vmsWithPricing | Format-Table -Property vmName, resourceGroup, pricingTier, subPlan -AutoSize
        Write-ColorOutput "Check-only mode: No changes made" -Type Info
        exit 0
    }
    
    # Interactive selection (unless Force is specified)
    $selectedVMs = @()
    
    if ($Force) {
        Write-ColorOutput "Force mode: Processing all VMs without confirmation" -Type Warning
        $selectedVMs = $vmsWithPricing
    }
    else {
        $choice = Show-VMSelectionMenu -VMs $vmsWithPricing
        
        switch ($choice.ToUpper()) {
            'A' {
                $selectedVMs = $vmsWithPricing
                Write-ColorOutput "Selected: All $($selectedVMs.Count) VMs" -Type Info
            }
            'S' {
                $selection = Read-Host "Enter VM numbers to process"
                $selectedVMs = Get-SelectedVMs -AllVMs $vmsWithPricing -Selection $selection
                if ($selectedVMs.Count -eq 0) {
                    Write-ColorOutput "No valid VMs selected" -Type Warning
                    exit 0
                }
                Write-ColorOutput "Selected: $($selectedVMs.Count) VM(s)" -Type Info
            }
            'C' {
                Write-ColorOutput "Operation cancelled by user" -Type Warning
                exit 0
            }
            default {
                Write-ColorOutput "Invalid choice. Operation cancelled." -Type Error
                exit 1
            }
        }
        
        # Final confirmation
        Write-Host ""
        Write-ColorOutput "VMs to process:" -Type Info
        $selectedVMs | ForEach-Object { Write-Host "  - $($_.vmName) ($($_.resourceGroup))" }
        Write-Host ""
        
        $finalConfirm = Read-Host "Proceed with removing pricing plans from these VMs? (Y/N)"
        if ($finalConfirm -ne 'Y' -and $finalConfirm -ne 'y') {
            Write-ColorOutput "Operation cancelled by user" -Type Warning
            exit 0
        }
    }
    
    # Process selected VMs
    Write-Host ""
    Write-ColorOutput "Processing $($selectedVMs.Count) VM(s)..." -Type Info
    Write-Host ""
    
    $index = 1
    foreach ($vm in $selectedVMs) {
        Write-Host "[$index/$($selectedVMs.Count)] Processing: $($vm.vmName)" -ForegroundColor Cyan
        
        $result = Remove-DefenderPricingPlan -ResourceId $vm.vmResourceId -VMName $vm.vmName
        
        $processedVMs += [PSCustomObject]@{
            VMName        = $vm.vmName
            ResourceGroup = $vm.resourceGroup
            Success       = $result.Success
            Message       = $result.Message
        }
        
        if ($result.Success) {
            Write-ColorOutput "  ✓ $($result.Message)" -Type Success
            $successCount++
        }
        else {
            Write-ColorOutput "  ✗ $($result.Message)" -Type Error
            $failureCount++
        }
        
        $index++
    }
    
    # Display summary
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Summary" -ForegroundColor White
    Write-Host "========================================" -ForegroundColor Cyan
    Write-ColorOutput "Total VMs processed: $($processedVMs.Count)" -Type Info
    Write-ColorOutput "Successful: $successCount" -Type Success
    if ($failureCount -gt 0) {
        Write-ColorOutput "Failed: $failureCount" -Type Error
    }
    Write-Host ""
    
    # Show detailed results
    if ($failureCount -gt 0) {
        Write-Host "Failed VMs:" -ForegroundColor Red
        $processedVMs | Where-Object { -not $_.Success } | ForEach-Object {
            Write-Host "  - $($_.VMName): $($_.Message)" -ForegroundColor Red
        }
        Write-Host ""
    }
    
    #endregion
}

#endregion