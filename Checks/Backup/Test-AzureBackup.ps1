#Requires -Version 5.1
<#
.SYNOPSIS
    NOT.4 - Datensicherung: Automatisierte Backups fuer VMs.
.DESCRIPTION
    Verifies Azure Backup is configured and protecting all VMs.
#>
function Test-AzureBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ResourceGroup,
        [Parameter(Mandatory)][string]$VaultName,
        [Parameter(Mandatory)][string[]]$VmNames,
        [string]$SubscriptionId = ''
    )

    $results = @()

    foreach ($vmName in $VmNames) {
        $response = Get-AzCliResponse -Arguments @("backup", "protection", "show", "--vault-name", $VaultName, "--resource-group", $ResourceGroup, "--container-name", $vmName, "--item-name", $vmName) -SubscriptionId $SubscriptionId

        if ($response.ExitCode -ne 0 -or -not $response.Output) {
            $results += [ComplianceResult]::new(
                'NOT.4', "$vmName backup protection", 'Backup',
                [BsiCheckMode]::Remote, [BsiCheckStatus]::Error, [BsiSeverity]::High,
                "Could not retrieve backup protection for $vmName"
            )
            $results[-1].CheckFunction = 'Test-AzureBackup'
            $results[-1].Remediation = "Enable Azure Backup for $vmName in vault $VaultName"
            continue
        }

        $backup = $response.Output | ConvertFrom-Json
        $state = $backup.properties.protectionState
        $pass = $state -eq 'Protected'
        $status = if ($pass) { [BsiCheckStatus]::Pass } else { [BsiCheckStatus]::Fail }

        $result = [ComplianceResult]::new(
            'NOT.4', "$vmName backup protection", 'Backup',
            [BsiCheckMode]::Remote, $status, [BsiSeverity]::High,
            "ProtectionState: $state"
        )
        $result.CheckFunction = 'Test-AzureBackup'
        $result.BsiReference  = 'BSI-G-00763'
        if (-not $pass) {
            $result.Remediation = "Enable backup for $vmName -- current state: $state"
        }
        $result.Metadata['vm'] = $vmName
        $results += $result
    }

    return $results
}
