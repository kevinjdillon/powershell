$tenant = "7a30c9f7-34a2-4098-a837-3c701caf7f05"
$vmName = "pwc-vm-LOTS-sandbox-dodaz-001"
$vmResourceGroup = "pwc-rg-mstesting-sandbox-dodaz-001_group"
$bastionName = "pwc-vnet-sandbox-dodaz-001-vnet-bastion"
$bastionResourceGroup = "PWC-RG-MSTESTING-SANDBOX-DODAZ-001_GROUP"

# az cloud set --name AzureUSGovernment
# az login --tenant $tenant

$vmId = az vm show --resource-group $vmResourceGroup --name $vmName --query id --output tsv
az network bastion rdp --name $bastionName --resource-group $bastionResourceGroup --target-resource-id $vmId