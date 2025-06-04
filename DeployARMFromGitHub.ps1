<#
    Start ARM template deployment script
#>

$templateUri = "https://raw.githubusercontent.com/<account>/<repo>/<branch>/<path>/<tempalte.json>"
$templateParameters = @{
    userName = $userName.ToLower()
    location = $location.ToLower()
    labName = $labName.ToLower()
}

$deploymentName = "$userName-$labName-$location"

$outputs = New-AzSubscriptionDeployment -Location $location -name $deploymentName -TemplateUri $templateUri -TemplateParameterObject $templateParameters