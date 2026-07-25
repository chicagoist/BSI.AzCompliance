#Requires -Version 5.1
<#
.SYNOPSIS
    DER.1 - Schadensbegrenzung: NAT Gateway fuer outbound Traffic.
.DESCRIPTION
    Verifies NAT Gateway exists and is associated with App/DB subnets.
#>
function Test-NatGateway {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ResourceGroup,
        [Parameter(Mandatory)][string]$NatGatewayName,
        [string[]]$ExpectedSubnets = @('subnet-app', 'subnet-db'),
        [string]$SubscriptionId = ''
    )

    $results = @()

    $response = Get-AzCliResponse -Arguments @("network", "nat", "gateway", "show", "-g", $ResourceGroup, "-n", $NatGatewayName) -SubscriptionId $SubscriptionId

    if ($response.ExitCode -ne 0) {
        $results += [ComplianceResult]::new(
            'DER.1', "NAT Gateway $NatGatewayName exists", 'Network',
            [BsiCheckMode]::Remote, [BsiCheckStatus]::Error, [BsiSeverity]::Medium,
            "Could not retrieve NAT Gateway $NatGatewayName"
        )
        $results[-1].CheckFunction = 'Test-NatGateway'
        return $results
    }

    $nat = $response.Output | ConvertFrom-Json
    $associatedSubnetIds = @($nat.subnets.id)

    $results += [ComplianceResult]::new(
        'DER.1', "NAT Gateway $NatGatewayName exists", 'Network',
        [BsiCheckMode]::Remote, [BsiCheckStatus]::Pass, [BsiSeverity]::Medium,
        "NAT Gateway found with $($associatedSubnetIds.Count) subnet association(s)"
    )
    $results[-1].CheckFunction = 'Test-NatGateway'

    foreach ($subnetName in $ExpectedSubnets) {
        $found = $associatedSubnetIds | Where-Object { $_ -match "/subnets/$([regex]::Escape($subnetName))$" }
        $pass = $null -ne $found
        $status = if ($pass) { [BsiCheckStatus]::Pass } else { [BsiCheckStatus]::Fail }

        $result = [ComplianceResult]::new(
            'DER.1', "Subnet $subnetName uses NAT Gateway", 'Network',
            [BsiCheckMode]::Remote, $status, [BsiSeverity]::Medium,
            $(if ($pass) { "$subnetName is associated with NAT Gateway" } else { "$subnetName is not associated with NAT Gateway" })
        )
        $result.CheckFunction = 'Test-NatGateway'
        $result.Remediation  = "Associate $subnetName with NAT Gateway for outbound connectivity"
        $results += $result
    }

    return $results
}
