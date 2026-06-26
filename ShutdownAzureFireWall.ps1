# Variables
$SubscriptionId   = "fa7b0278-0659-4cc0-8909-9827c3bc3763"
$ResourceGroup    = "rg-homelab"
$FirewallName     = "fw-homelab-hub"
$publicIpName     = "pip-fw-hub-client"
$mgmtPublicIpName = "pip-fw-hub-mgmt"
$vnetName        = "vnet-hub"

# Login and select subscription
# Connect-AzAccount
# Set-AzContext -SubscriptionId $SubscriptionId

# Get the firewall
$firewall = Get-AzFirewall `
    -Name $FirewallName `
    -ResourceGroupName $ResourceGroup

# Deallocate (stop) the firewall
$firewall.Deallocate()
$firewall | Set-AzFirewall

# Allocate (start) the firewall
$vnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroup -Name $vnetName
$pip = Get-AzPublicIpAddress -ResourceGroupName $ResourceGroup -Name $publicIpName
$mgmtPip = Get-AzPublicIpAddress -ResourceGroupName $ResourceGroup -Name $mgmtPublicIpName
$firewall.Allocate($vnet, $pip, $mgmtPip)
$firewall | Set-AzFirewall