#Requires -Version 5.1
<#
.SYNOPSIS
    BER.2 - Identitaetsmanagement: SystemAssigned Managed Identity.
.DESCRIPTION
    Verifies all VMs have SystemAssigned Managed Identity enabled.
#>
function Test-ManagedIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ResourceGroup,
        [Parameter(Mandatory)][string[]]$VmNames,
        [string]$SubscriptionId = ''
    )

    $results = @()

    foreach ($vmName in $VmNames) {
        $response = Get-AzCliResponse -Arguments @("vm", "show", "-g", $ResourceGroup, "-n", $vmName) -SubscriptionId $SubscriptionId

        if ($response.ExitCode -ne 0 -or -not $response.Output) {
            $results += [ComplianceResult]::new(
                'BER.2', "$vmName Managed Identity", 'Identity',
                [BsiCheckMode]::Remote, [BsiCheckStatus]::Error, [BsiSeverity]::Medium,
                "Could not retrieve VM $vmName"
            )
            $results[-1].CheckFunction = 'Test-ManagedIdentity'
            continue
        }

        $vm = $response.Output | ConvertFrom-Json
        $hasIdentity = $null -ne $vm.identity -and $vm.identity.type -match 'SystemAssigned'
        $status = if ($hasIdentity) { [BsiCheckStatus]::Pass } else { [BsiCheckStatus]::Fail }
        $details = if ($hasIdentity) {
            "SystemAssigned identity found: $($vm.identity.principalId)"
        } else {
            "No SystemAssigned Managed Identity on $vmName"
        }

        $result = [ComplianceResult]::new(
            'BER.2', "$vmName Managed Identity", 'Identity',
            [BsiCheckMode]::Remote, $status, [BsiSeverity]::Medium, $details
        )
        $result.CheckFunction = 'Test-ManagedIdentity'
        $result.BsiReference  = 'BSI-G-00618'
        if (-not $hasIdentity) {
            $result.Remediation = "Enable SystemAssigned Managed Identity on $vmName for Key Vault access"
        }
        $result.Metadata['vm'] = $vmName
        $results += $result
    }

    return $results
}
