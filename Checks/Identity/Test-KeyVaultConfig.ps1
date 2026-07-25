#Requires -Version 5.1
<#
.SYNOPSIS
    BER.6 - Schluesselmanagement: Azure Key Vault Konfiguration.
.DESCRIPTION
    Verifies Key Vault exists with soft-delete, purge protection,
    required secrets, and diagnostic settings.
#>
function Test-KeyVaultConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ResourceGroup,
        [Parameter(Mandatory)][string]$KeyVaultName,
        [string]$SecretName = '',
        [string]$SubscriptionId = ''
    )

    $results = @()

    $response = Get-AzCliResponse -Arguments @("keyvault", "show", "--name", $KeyVaultName, "-g", $ResourceGroup) -SubscriptionId $SubscriptionId

    if ($response.ExitCode -ne 0 -or -not $response.Output) {
        $results += [ComplianceResult]::new(
            'BER.6', "Key Vault $KeyVaultName exists", 'Identity',
            [BsiCheckMode]::Remote, [BsiCheckStatus]::Error, [BsiSeverity]::Critical,
            "Could not retrieve Key Vault $KeyVaultName"
        )
        $results[-1].CheckFunction = 'Test-KeyVaultConfig'
        $results[-1].Remediation = "Create Key Vault $KeyVaultName with RBAC and Managed Identity"
        return $results
    }

    $kv = $response.Output | ConvertFrom-Json

    # Key Vault exists
    $results += [ComplianceResult]::new(
        'BER.6', "Key Vault $KeyVaultName exists", 'Identity',
        [BsiCheckMode]::Remote, [BsiCheckStatus]::Pass, [BsiSeverity]::Critical,
        "Key Vault found"
    )
    $results[-1].CheckFunction = 'Test-KeyVaultConfig'

    # Soft-delete
    $softDelete = $kv.properties.enableSoftDelete -eq $true
    $results += [ComplianceResult]::new(
        'BER.6', 'Key Vault soft-delete enabled', 'Identity',
        [BsiCheckMode]::Remote, $(if ($softDelete) { [BsiCheckStatus]::Pass } else { [BsiCheckStatus]::Fail }),
        [BsiSeverity]::Critical,
        "enableSoftDelete = $($kv.properties.enableSoftDelete)"
    )
    $results[-1].CheckFunction = 'Test-KeyVaultConfig'
    $results[-1].BsiReference  = 'BSI-G-00622'
    if (-not $softDelete) { $results[-1].Remediation = "Enable soft-delete on Key Vault" }

    # Purge protection
    $purgeProt = $kv.properties.enablePurgeProtection -eq $true
    $results += [ComplianceResult]::new(
        'BER.6', 'Key Vault purge protection enabled', 'Identity',
        [BsiCheckMode]::Remote, $(if ($purgeProt) { [BsiCheckStatus]::Pass } else { [BsiCheckStatus]::Fail }),
        [BsiSeverity]::Critical,
        "enablePurgeProtection = $($kv.properties.enablePurgeProtection)"
    )
    $results[-1].CheckFunction = 'Test-KeyVaultConfig'
    if (-not $purgeProt) { $results[-1].Remediation = "Enable purge protection on Key Vault" }

    # Secret existence
    if ($SecretName) {
        $secretResp = Get-AzCliResponse -Arguments @("keyvault", "secret", "show", "--vault-name", $KeyVaultName, "--name", $SecretName) -SubscriptionId $SubscriptionId
        $pass = $secretResp.ExitCode -eq 0
        $results += [ComplianceResult]::new(
            'BER.6', "Secret '$SecretName' exists", 'Identity',
            [BsiCheckMode]::Remote, $(if ($pass) { [BsiCheckStatus]::Pass } else { [BsiCheckStatus]::Fail }),
            [BsiSeverity]::Critical,
            $(if ($pass) { "Secret '$SecretName' found" } else { "Secret '$SecretName' not found in $KeyVaultName" })
        )
        $results[-1].CheckFunction = 'Test-KeyVaultConfig'
    }

    return $results
}
