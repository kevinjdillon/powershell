<#
.SYNOPSIS
    Deploys ARM template to Azure subscription
.DESCRIPTION
    Deploys an ARM template and its parameters file to create Azure resources
.NOTES
    Created: 2025-06-09
#>

# Parameters
$location = "westus"
$deploymentName = "CreateRG-$location"
$templateFile = "C:\Git\arm-templates\network\deployWestUSNetwork.json"
$templateParameterFile = "C:\Git\arm-templates\network\rgDeploy.westus.parameters.json"

# Deploy ARM template
$outputs = New-AzSubscriptionDeployment `
    -Location $location `
    -Name $deploymentName `
    -TemplateFile $templateFile `
    -TemplateParameterFile $templateParameterFile
