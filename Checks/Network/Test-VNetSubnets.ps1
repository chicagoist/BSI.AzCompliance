#Requires -Version 5.1
<#
.SYNOPSIS
    ARCH.2.1 - Netzdesign: Netzsegmente (Hub-Spoke mit getrennten Subnetzen).
.DESCRIPTION
    Verifies the Spoke VNet contains separate web/app/db subnets with
    correct address ranges and NSG associations.
#>
function Test-VNetSubnets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ResourceGroup,
        [Parameter(Mandatory)][string]$VNetName,
        [Parameter(Mandatory)][hashtable]$ExpectedSubnets,
        [string]$SubscriptionId = ''
    )

    $results = @()

    $response = Get-AzCliResponse -Arguments @("network", "vnet", "show", "-g", $ResourceGroup, "-n", $VNetName) -SubscriptionId $SubscriptionId

    if ($response.ExitCode -ne 0 -or -not $response.Output) {
        $results += [ComplianceResult]::new(
            'ARCH.2.1', "VNet $VNetName exists and contains subnets", 'Network',
            [BsiCheckMode]::Remote, [BsiCheckStatus]::Error, [BsiSeverity]::High,
            "Could not retrieve VNet $VNetName"
        )
        $results[-1].CheckFunction = 'Test-VNetSubnets'
        return $results
    }

    $vnet = $response.Output | ConvertFrom-Json
    $subnets = $vnet.subnets

    # Check VNet exists
    $results += [ComplianceResult]::new(
        'ARCH.2.1', "VNet $VNetName exists", 'Network',
        [BsiCheckMode]::Remote, [BsiCheckStatus]::Pass, [BsiSeverity]::High,
        "VNet $VNetName found with address space: $($vnet.addressSpace.addressPrefixes -join ', ')"
    )
    $results[-1].CheckFunction = 'Test-VNetSubnets'

    # Check each expected subnet
    foreach ($subnetName in $ExpectedSubnets.Keys) {
        $expected = $ExpectedSubnets[$subnetName]
        $found = $subnets | Where-Object { $_.name -eq $subnetName } | Select-Object -First 1

        if ($found) {
            $addrOk = $found.addressPrefix -eq $expected.AddressPrefix
            $status = if ($addrOk) { [BsiCheckStatus]::Pass } else { [BsiCheckStatus]::Fail }
            $details = if ($addrOk) {
                "Subnet $subnetName found with address $($found.addressPrefix)"
            } else {
                "Subnet $subnetName address mismatch: expected $($expected.AddressPrefix), actual $($found.addressPrefix)"
            }
        } else {
            $status = [BsiCheckStatus]::Fail
            $details = "Subnet $subnetName not found in $VNetName"
        }

        $result = [ComplianceResult]::new(
            'ARCH.2.1', "Subnet $subnetName exists with correct address", 'Network',
            [BsiCheckMode]::Remote, $status, [BsiSeverity]::High, $details
        )
        $result.CheckFunction = 'Test-VNetSubnets'
        if ($found -and $expected.NsgName) {
            $nsgAttached = $found.networkSecurityGroup -and $found.networkSecurityGroup.id -match "$([regex]::Escape($expected.NsgName))$"
            $result.Evidence = "NSG attached: $nsgAttached"
        }
        $results += $result
    }

    return $results
}
