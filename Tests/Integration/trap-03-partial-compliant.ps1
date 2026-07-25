# This script has subnets but no NSG deny rules and no encryption
$rgName = "test-rg"
$subnetWeb = "subnet-web"
$subnetApp = "subnet-app"
$subnetDb = "subnet-db"

az network vnet create --name "vnet-spoke1" --resource-group $rgName `
    --subnet-name $subnetWeb --subnet-prefixes "10.0.1.0/24"
az network vnet subnet create --name $subnetApp --vnet-name "vnet-spoke1" `
    --resource-group $rgName --address-prefixes "10.0.2.0/24"
az network vnet subnet create --name $subnetDb --vnet-name "vnet-spoke1" `
    --resource-group $rgName --address-prefixes "10.0.3.0/24"
