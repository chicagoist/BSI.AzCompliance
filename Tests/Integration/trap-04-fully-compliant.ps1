# Fully BSI-compliant deployment script
$rgName = "test-rg"
$subnetWeb = "subnet-web"
$subnetApp = "subnet-app"
$subnetDb = "subnet-db"
$vnetSpoke1Name = "vnet-spoke1"
$vnetHubName = "vnet-hub"

az network nsg create --name "NSG-Web" --resource-group $rgName
az network nsg create --name "NSG-App" --resource-group $rgName
az network nsg create --name "NSG-DB" --resource-group $rgName

az network nsg rule create --resource-group $rgName --nsg-name "NSG-Web" --name "DenySSH" `
    --priority 200 --destination-port-ranges 22 --access Deny --protocol Tcp --source-address-prefixes '*'
az network nsg rule create --resource-group $rgName --nsg-name "NSG-Web" --name "DenyRDP" `
    --priority 210 --destination-port-ranges 3389 --access Deny --protocol Tcp --source-address-prefixes '*'
az network nsg rule create --resource-group $rgName --nsg-name "NSG-App" --name "DenySSH" `
    --priority 200 --destination-port-ranges 22 --access Deny --protocol Tcp --source-address-prefixes '*'

az network vnet create --name $vnetSpoke1Name --resource-group $rgName `
    --subnet-name $subnetWeb --subnet-prefixes "10.0.1.0/24" --nsg "NSG-Web"
az network vnet subnet create --name $subnetApp --vnet-name $vnetSpoke1Name `
    --resource-group $rgName --address-prefixes "10.0.2.0/24" --nsg "NSG-App"
az network vnet subnet create --name $subnetDb --vnet-name $vnetSpoke1Name `
    --resource-group $rgName --address-prefixes "10.0.3.0/24" --nsg "NSG-DB"

az network vnet peering create --name "Hub-to-Spoke" --resource-group $rgName `
    --vnet-name $vnetHubName --remote-vnet $vnetSpoke1Name --allow-vnet-access
az network vnet peering create --name "Spoke-to-Hub" --resource-group $rgName `
    --vnet-name $vnetSpoke1Name --remote-vnet $vnetHubName --allow-vnet-access

az network nat gateway create --resource-group $rgName --name "nat-gateway-prod" `
    --public-ip-addresses "pip-nat-outbound"
az network vnet subnet update --resource-group $rgName --vnet-name $vnetSpoke1Name `
    --name $subnetApp --nat-gateway "nat-gateway-prod"

az network bastion create --name "bastion-hub" --public-ip-address "pip-bastion" `
    --resource-group $rgName --vnet-name $vnetHubName --location westeurope

az vm create --name "VM-web" --resource-group $rgName --encryption-at-host `
    --assign-identity "[system]" --image Ubuntu2204
az vm create --name "VM-app" --resource-group $rgName --encryption-at-host `
    --assign-identity "[system]" --image Ubuntu2204
az vm create --name "VM-db" --resource-group $rgName --encryption-at-host `
    --assign-identity "[system]" --image Ubuntu2204

az keyvault create --name "kv-test" --resource-group $rgName `
    --enable-purge-protection --enable-soft-delete

az role assignment create --assignee "00000000-0000-0000-0000-000000000000" `
    --role "Key Vault Secrets User" --scope "/subscriptions/..."

az storage account create --name "sttest" --resource-group $rgName `
    --min-tls-version TLS1_2 --https-only true --allow-blob-public-access false

az backup vault create --name "rsv-test" --resource-group $rgName
$recoveryServicesVaultName = "rsv-test"

az network watcher flow-log create --location westeuropa --nsg "NSG-Web" `
    --enabled true --retention 90
