#Requires -Version 5.1
<#
.SYNOPSIS
    ARCH.2.3 - Netzdesign: Hub-Spoke VNet Peering Connected.
.DESCRIPTION
    Verifies that Hub-to-Spoke and Spoke-to-Hub peerings are in Connected state
    and allow virtual network access.
#>
function Test-VNetPeering {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ResourceGroup,
        [Parameter(Mandatory)][string]$HubVNetName,
        [Parameter(Mandatory)][string]$SpokeVNetName,
        [string]$SubscriptionId = ''
    )

    $results = @()

    # Hub-to-Spoke
    $hubResponse = Get-AzCliResponse -Arguments @("network", "vnet", "peering", "show", "-g", $ResourceGroup, "--vnet-name", $HubVNetName, "-n", "Hub-to-Spoke") -SubscriptionId $SubscriptionId

    if ($hubResponse.ExitCode -ne 0) {
        $results += [ComplianceResult]::new(
            'ARCH.2.3', 'Hub-to-Spoke peering exists', 'Network',
            [BsiCheckMode]::Remote, [BsiCheckStatus]::Error, [BsiSeverity]::High,
            'Could not retrieve Hub-to-Spoke peering'
        )
        $results[-1].CheckFunction = 'Test-VNetPeering'
        return $results
    }

    # Spoke-to-Hub
    $spokeResponse = Get-AzCliResponse -Arguments @("network", "vnet", "peering", "show", "-g", $ResourceGroup, "--vnet-name", $SpokeVNetName, "-n", "Spoke-to-Hub") -SubscriptionId $SubscriptionId

    if ($spokeResponse.ExitCode -ne 0) {
        $results += [ComplianceResult]::new(
            'ARCH.2.3', 'Spoke-to-Hub peering exists', 'Network',
            [BsiCheckMode]::Remote, [BsiCheckStatus]::Error, [BsiSeverity]::High,
            'Could not retrieve Spoke-to-Hub peering'
        )
        $results[-1].CheckFunction = 'Test-VNetPeering'
        return $results
    }

    $hubPeer   = $hubResponse.Output | ConvertFrom-Json
    $spokePeer = $spokeResponse.Output | ConvertFrom-Json

    $pass = ($hubPeer.peeringState -eq 'Connected') -and
            ($spokePeer.peeringState -eq 'Connected') -and
            $hubPeer.allowVirtualNetworkAccess -and
            $spokePeer.allowVirtualNetworkAccess

    $status = if ($pass) { [BsiCheckStatus]::Pass } else { [BsiCheckStatus]::Fail }
    $details = "Hub: $($hubPeer.peeringState), Spoke: $($spokePeer.peeringState)"

    $result = [ComplianceResult]::new(
        'ARCH.2.3', 'Hub-Spoke VNet Peering Connected', 'Network',
        [BsiCheckMode]::Remote, $status, [BsiSeverity]::High, $details
    )
    $result.CheckFunction = 'Test-VNetPeering'
    $result.BsiReference  = 'BSI-G-00547'
    $results += $result

    return $results
}
