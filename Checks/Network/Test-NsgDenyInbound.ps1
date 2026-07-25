#Requires -Version 5.1
<#
.SYNOPSIS
    ARCH.5.2 - Perimeterschutz: Blockieren direkter oeffentlicher Verbindungen.
.DESCRIPTION
    Verifies NSGs contain effective Deny rules for SSH (22) and RDP (3389)
    from the Internet. Checks both explicit Deny rules and absence of Allow
    from Internet sources.
.PARAMETER ResourceGroup
    Azure resource group name.
.PARAMETER NsgNames
    Array of NSG names to check.
.PARAMETER Ports
    Array of port numbers to verify Deny rules for.
.PARAMETER SubscriptionId
    Optional Azure subscription ID.
#>
function Test-NsgDenyInbound {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ResourceGroup,
        [Parameter(Mandatory)][string[]]$NsgNames,
        [Parameter(Mandatory)][string[]]$Ports,
        [string]$SubscriptionId = ''
    )

    $results = @()
    $internetSources = @('Internet', '*', '0.0.0.0/0')

    foreach ($nsgName in $NsgNames) {
        $response = Get-AzCliResponse -Arguments @("network", "nsg", "rule", "list", "-g", $ResourceGroup, "--nsg-name", $nsgName) -SubscriptionId $SubscriptionId

        if ($response.ExitCode -ne 0 -or -not $response.Output) {
            $results += [ComplianceResult]::new(
                'ARCH.5.2', "NSG $nsgName - Deny SSH/RDP from Internet", 'Network',
                [BsiCheckMode]::Remote, [BsiCheckStatus]::Error, [BsiSeverity]::Critical,
                "Could not list rules for NSG $nsgName"
            )
            $results[-1].CheckFunction = 'Test-NsgDenyInbound'
            $results[-1].Remediation = "Create NSG rule: Deny inbound from Internet on ports 22, 3389"
            continue
        }

        $rules = $response.Output | ConvertFrom-Json

        foreach ($port in $Ports) {
            $relevantRules = $rules | Where-Object {
                $_.direction -eq 'Inbound' -and
                ($_.sourceAddressPrefix -in $internetSources -or
                 ($_.sourceAddressPrefixes -and ($_.sourceAddressPrefixes | Where-Object { $_ -in $internetSources })))
            }

            $denyRules = $relevantRules | Where-Object {
                $_.access -eq 'Deny' -and
                ($_.destinationPortRange -eq $port -or $_.destinationPortRange -eq '*' -or
                 ($_.destinationPortRanges -and $_.destinationPortRanges -contains $port))
            }

            $allowRules = $relevantRules | Where-Object {
                $_.access -eq 'Allow' -and
                ($_.destinationPortRange -eq $port -or $_.destinationPortRange -eq '*' -or
                 ($_.destinationPortRanges -and $_.destinationPortRanges -contains $port))
            }

            $pass = $false
            $details = ''

            if (-not $denyRules -and -not $allowRules) {
                # No explicit rules — default Azure behavior is deny-all inbound, which is fine
                $pass = $true
                $details = "No explicit rules for port $port; default DenyAllInbound applies"
            } elseif ($denyRules -and -not $allowRules) {
                $pass = $true
                $details = "Explicit Deny rule(s) exist for port $port; no Allow from Internet"
            } elseif ($denyRules -and $allowRules) {
                $denyPriorities = @($denyRules | ForEach-Object { [int]$_.priority } | Where-Object { $_ -gt 0 })
                $allowPriorities = @($allowRules | ForEach-Object { [int]$_.priority } | Where-Object { $_ -gt 0 })

                if ($denyPriorities -and $allowPriorities) {
                    $minDeny = ($denyPriorities | Measure-Object -Minimum).Minimum
                    $minAllow = ($allowPriorities | Measure-Object -Minimum).Minimum
                    $pass = $minDeny -lt $minAllow
                    $details = "Deny priority: $minDeny, Allow priority: $minAllow"
                } else {
                    $details = "Could not compare rule priorities"
                }
            } else {
                # Allow without Deny — FAIL
                $details = "Allow rule for port $port exists without a higher-priority Deny rule"
            }

            $status = if ($pass) { [BsiCheckStatus]::Pass } else { [BsiCheckStatus]::Fail }

            $result = [ComplianceResult]::new(
                'ARCH.5.2', "NSG $nsgName - Effective Deny for port $port from Internet", 'Network',
                [BsiCheckMode]::Remote, $status, [BsiSeverity]::Critical,
                $details
            )
            $result.CheckFunction   = 'Test-NsgDenyInbound'
            $result.Evidence        = "Deny rules: $(if ($denyRules) { $denyRules.Count } else { 0 }), Allow rules: $(if ($allowRules) { $allowRules.Count } else { 0 })"
            $result.Remediation     = "Ensure NSG rule with lower priority number Denys inbound port $port from Internet"
            $result.BsiReference    = 'BSI-G-00549'
            $result.Metadata['nsg'] = $nsgName
            $result.Metadata['port'] = $port
            $results += $result
        }
    }

    return $results
}
