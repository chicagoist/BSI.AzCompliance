# Script with umlauts and special chars: ae oe ue ss
$location = "germanywestcentral"
# BSI-Grundschutz: IT-Grundschutz-Bausteine
az network nsg rule create --destination-port-ranges 22 --access Deny `
    --description "Blockiere SSH-Zugang von aussen"
