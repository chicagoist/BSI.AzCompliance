#Requires -Version 5.1
<#
.SYNOPSIS
    ARCH.5.3 - Perimeterschutz: Azure Bastion fuer sicheren SSH-Zugang.
.DESCRIPTION
    Verifies Azure Bastion host exists for secure SSH access to backend VMs.
#>
function Test-BastionExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ResourceGroup,
        [Parameter(Mandatory)][string]$BastionHostName,
        [string]$SubscriptionId = ''
    )

    $response = Get-AzCliResponse -Arguments @("network", "bastion", "show", "--name", $BastionHostName, "-g", $ResourceGroup) -SubscriptionId $SubscriptionId

    $pass = $response.ExitCode -eq 0
    $status = if ($pass) { [BsiCheckStatus]::Pass } else { [BsiCheckStatus]::Fail }
    $details = if ($pass) { "Bastion host $BastionHostName found" } else { "Bastion host $BastionHostName not found" }

    $result = [ComplianceResult]::new(
        'ARCH.5.3', 'Azure Bastion host exists', 'Network',
        [BsiCheckMode]::Remote, $status, [BsiSeverity]::High, $details
    )
    $result.CheckFunction = 'Test-BastionExists'
    $result.BsiReference  = 'BSI-G-00550'
    $result.Remediation  = "Deploy Azure Bastion to enable secure RDP/SSH without public IP exposure"
    return @($result)
}
