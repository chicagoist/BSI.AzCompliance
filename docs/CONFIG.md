# Configuration Reference (config.ps1)

This file defines the Azure resource names used by `Invoke-BsiCompliance -Remote`.

## Required Variables

| Variable | Type | Example | Description |
|----------|------|---------|-------------|
| `$rgName` | `string` | `"rg_Valerii_Dundukov"` | Azure resource group name |
| `$location` | `string` | `"centralindia"` | Azure region (e.g., westeurope, northeurope) |
| `$vnetSpoke1Name` | `string` | `"vnet-spoke1"` | Spoke VNet name |
| `$subnetWeb` | `string` | `"subnet-web"` | Web tier subnet name |
| `$subnetWebAddress` | `string` | `"10.0.1.0/24"` | Web subnet address prefix |
| `$subnetApp` | `string` | `"subnet-app"` | App tier subnet name |
| `$subnetAppAddress` | `string` | `"10.0.2.0/24"` | App subnet address prefix |
| `$subnetDb` | `string` | `"subnet-db"` | DB tier subnet name |
| `$subnetDBAddress` | `string` | `"10.0.3.0/24"` | DB subnet address prefix |
| `$storageaccountName` | `string` | `"stvalerii0422"` | Storage account name |
| `$keyVaultName` | `string` | `"kv-3tier-prod-0713"` | Key Vault name |
| `$recoveryServicesVaultName` | `string` | `"rsv-3tier-prod"` | Recovery Services Vault name |

## Optional Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `$vnetHubName` | `string` | — | Hub VNet name (for peering check) |
| `$bastionHostName` | `string` | — | Bastion host name (for ARCH.5.3) |
| `$secretName` | `string` | — | Key Vault secret name (for BER.6) |

## Example config.ps1

```powershell
# config.ps1 — User-specific Azure resource configuration
# This file should NOT be committed to version control.

$rgName = "rg_Valerii_Dundukov"
$location = "centralindia"

$vnetSpoke1Name = "vnet-spoke1"
$subnetWeb = "subnet-web"
$subnetWebAddress = "10.0.1.0/24"
$subnetApp = "subnet-app"
$subnetAppAddress = "10.0.2.0/24"
$subnetDb = "subnet-db"
$subnetDBAddress = "10.0.3.0/24"

$vnetHubName = "vnet-hub"
$bastionHostName = "bastion-hub"

$storageaccountName = "stvalerii0422"
$keyVaultName = "kv-3tier-prod-0713"
$secretName = "db-password"
$recoveryServicesVaultName = "rsv-3tier-prod"
```

## Security Notes

- **Never commit `config.ps1`** to version control
- Add `config.ps1` to `.gitignore`
- For CI/CD, store configuration as **GitHub Secrets** or Azure DevOps Variable Groups
- The `config.ps1` file is dot-sourced — only variable assignments, no executable code
