<#
.SYNOPSIS
    Deploys ARM template to Azure Resource Group
.DESCRIPTION
    Deploys an ARM template and its parameters file to create Azure resources
.NOTES
    Created: 2025-06-09
#>

# Parameters
$ResourceGroupName = "IaC-Tutorial-EastUS"
$location = (Get-AzResourceGroup -Name $ResourceGroupName).Location
$deploymentName = "CreateAzRGResource-$location"
$templateFile = "C:\Git\arm-templates\network\vnetDeploy.json"
$templateParameterFile = "C:\Git\arm-templates\network\vnetDeploy.eastus.parameters.json"

# Deploy ARM template
$outputs = New-AzResourceGroupDeployment `
    -Location $location `
    -ResourceGroupName $ResourceGroupName `
    -Name $deploymentName `
    -TemplateFile $templateFile `
    -TemplateParameterFile $templateParameterFile
