#Requires -Version 5.1
<#
.SYNOPSIS
    ARCH.5.1 - Perimeterschutz: Keine oeffentlichen IPs auf Backend-Tier.
.DESCRIPTION
    Verifies that DB and App VMs do not have public IPs attached to their NICs.
    Only the Web tier should have a public IP.
#>
function Test-NoPublicIp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ResourceGroup,
        [Parameter(Mandatory)][string[]]$BackendTiers,
        [string]$WebTier = '',
        [string]$SubscriptionId = ''
    )

    $results = @()

    foreach ($tier in $BackendTiers) {
        $vmName = "VM-$tier"
        $nicName = "${vmName}VMNic"

        $response = Get-AzCliResponse -Arguments @("network", "nic", "show", "-g", $ResourceGroup, "-n", $nicName, "--query", "ipConfigurations[0].publicIpAddress.id") -SubscriptionId $SubscriptionId

        if ($response.ExitCode -ne 0) {
            $results += [ComplianceResult]::new(
                'ARCH.5.1', "$vmName NIC check", 'Network',
                [BsiCheckMode]::Remote, [BsiCheckStatus]::Error, [BsiSeverity]::Critical,
                "Failed to retrieve NIC $nicName"
            )
            $results[-1].CheckFunction = 'Test-NoPublicIp'
            continue
        }

        $hasPublicIp = -not [string]::IsNullOrWhiteSpace($response.Output)
        $pass = -not $hasPublicIp
        $status = if ($pass) { [BsiCheckStatus]::Pass } else { [BsiCheckStatus]::Fail }

        $result = [ComplianceResult]::new(
            'ARCH.5.1', "$vmName has no Public IP", 'Network',
            [BsiCheckMode]::Remote, $status, [BsiSeverity]::Critical,
            $(if ($pass) { "$vmName correctly has no public IP" } else { "Public IP found on $vmName — violates ARCH.5.1" })
        )
        $result.CheckFunction = 'Test-NoPublicIp'
        $result.BsiReference  = 'BSI-G-00548'
        $result.Remediation  = "Remove public IP from $nicName. Use Bastion for SSH access."
        $result.Metadata['vm'] = $vmName
        $results += $result
    }

    # Web tier should have public IP
    if ($WebTier) {
        $vmName = "VM-$WebTier"
        $nicName = "${vmName}VMNic"

        $response = Get-AzCliResponse -Arguments @("network", "nic", "show", "-g", $ResourceGroup, "-n", $nicName, "--query", "ipConfigurations[0].publicIpAddress.id") -SubscriptionId $SubscriptionId

        if ($response.ExitCode -eq 0) {
            $hasPublicIp = -not [string]::IsNullOrWhiteSpace($response.Output)
            $result = [ComplianceResult]::new(
                'ARCH.5.1', "$vmName has Public IP (expected)", 'Network',
                [BsiCheckMode]::Remote, $(if ($hasPublicIp) { [BsiCheckStatus]::Pass } else { [BsiCheckStatus]::Fail }),
                [BsiSeverity]::Info,
                $(if ($hasPublicIp) { "$vmName correctly has public IP for internet reachability" } else { "$vmName is missing public IP" })
            )
            $result.CheckFunction = 'Test-NoPublicIp'
            $results += $result
        }
    }

    return $results
}
