#Requires -Version 5.1
<#
.SYNOPSIS
    INF.1 - Recovery Services Vault Existenz.
.DESCRIPTION
    Verifies the Recovery Services Vault exists.
#>
function Test-RecoveryServicesVault {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ResourceGroup,
        [Parameter(Mandatory)][string]$VaultName,
        [string]$SubscriptionId = ''
    )

    $response = Get-AzCliResponse -Arguments @("backup", "vault", "show", "--name", $VaultName, "--resource-group", $ResourceGroup) -SubscriptionId $SubscriptionId

    $pass = $response.ExitCode -eq 0
    $status = if ($pass) { [BsiCheckStatus]::Pass } else { [BsiCheckStatus]::Fail }
    $details = if ($pass) { "Recovery Services Vault '$VaultName' exists" } else { "Recovery Services Vault '$VaultName' not found" }

    $result = [ComplianceResult]::new(
        'INF.1', 'Recovery Services Vault exists', 'Backup',
        [BsiCheckMode]::Remote, $status, [BsiSeverity]::Medium, $details
    )
    $result.CheckFunction = 'Test-RecoveryServicesVault'
    $result.BsiReference  = 'BSI-G-00529'
    if (-not $pass) {
        $result.Remediation = "Create Recovery Services Vault '$VaultName' and configure backup policies"
    }
    return @($result)
}
