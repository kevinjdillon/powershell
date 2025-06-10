<#
.SYNOPSIS
    Deploys ARM template to Azure subscription
.DESCRIPTION
    Deploys an ARM template and its parameters file to create Azure resources
.NOTES
    Created: 2025-06-09
#>

# Parameters
$location = "eastus"
$deploymentName = "CreateRG-$location"
$templateFile = "C:\Git\arm-templates\network\rgDeploy.json"
$templateParameterFile = "C:\Git\arm-templates\network\rgDeploy.parameters.json"

# Deploy ARM template
$outputs = New-AzDeployment `
    -Location $location `
    -Name $deploymentName `
    -TemplateFile $templateFile `
    -TemplateParameterFile $templateParameterFile
