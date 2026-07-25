# Large script with many NSG rules
for ($i = 1; $i -le 100; $i++) {
    Write-Host "Creating NSG rule $i"
}
az network nsg rule create --resource-group rg --nsg-name "NSG-Web" `
    --name "Deny-SSH-$i" --destination-port-ranges 22 --access Deny --protocol Tcp
az network nsg rule create --resource-group rg --nsg-name "NSG-Web" `
    --name "Deny-RDP-$i" --destination-port-ranges 3389 --access Deny --protocol Tcp
az network nsg rule create --resource-group rg --nsg-name "NSG-Web" `
    --name "DenySSH" --destination-port-ranges 22 --access Deny --protocol Tcp `
    --source-address-prefixes '*'
az network nsg rule create --resource-group rg --nsg-name "NSG-Web" `
    --name "DenyRDP" --destination-port-ranges 3389 --access Deny --protocol Tcp `
    --source-address-prefixes '*'
