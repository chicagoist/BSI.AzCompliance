#Requires -Version 5.1
<#
.SYNOPSIS
    DET.3 - Protokollierung: NSG Flow Logs.
.DESCRIPTION
    Verifies NSG Flow Logs are enabled for all NSGs.
#>
function Test-FlowLogs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Location,
        [Parameter(Mandatory)][string[]]$NsgNames,
        [string]$SubscriptionId = ''
    )

    $results = @()

    # List flow logs
    $response = Get-AzCliResponse -Arguments @("network", "watcher", "flow-log", "list", "--location", $Location) -SubscriptionId $SubscriptionId

    if ($response.ExitCode -ne 0 -or -not $response.Output) {
        $results += [ComplianceResult]::new(
            'DET.3', 'NSG Flow Logs enabled', 'Monitoring',
            [BsiCheckMode]::Remote, [BsiCheckStatus]::Error, [BsiSeverity]::Medium,
            "Could not list flow logs in $Location"
        )
        $results[-1].CheckFunction = 'Test-FlowLogs'
        return $results
    }

    $flowLogs = $response.Output | ConvertFrom-Json

    foreach ($nsgName in $NsgNames) {
        $escapedName = [regex]::Escape($nsgName)
        $match = $flowLogs | Where-Object {
            $_.targetResourceId -match "$escapedName`$" -and $_.enabled -eq $true
        } | Select-Object -First 1

        $pass = $null -ne $match
        $status = if ($pass) { [BsiCheckStatus]::Pass } else { [BsiCheckStatus]::Fail }

        $result = [ComplianceResult]::new(
            'DET.3', "$nsgName Flow Logs enabled", 'Monitoring',
            [BsiCheckMode]::Remote, $status, [BsiSeverity]::Medium,
            $(if ($pass) { "Flow log enabled for $nsgName" } else { "Flow log not enabled for $nsgName" })
        )
        $result.CheckFunction = 'Test-FlowLogs'
        $result.BsiReference  = 'BSI-G-00504'
        if (-not $pass) {
            $result.Remediation = "Enable NSG Flow Logs for $nsgName via Network Watcher"
        }
        $result.Metadata['nsg'] = $nsgName
        $results += $result
    }

    return $results
}
