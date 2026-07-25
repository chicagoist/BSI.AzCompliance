#Requires -Version 5.1
<#
.SYNOPSIS
    DET.3.1 - Network Watcher exists in target region.
.DESCRIPTION
    Verifies Network Watcher is deployed in the target Azure region.
#>
function Test-NetworkWatcher {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Location,
        [string]$SubscriptionId = ''
    )

    $response = Get-AzCliResponse -Arguments @("network", "watcher", "list") -SubscriptionId $SubscriptionId

    if ($response.ExitCode -ne 0 -or -not $response.Output) {
        $result = [ComplianceResult]::new(
            'DET.3.1', "Network Watcher in $Location", 'Monitoring',
            [BsiCheckMode]::Remote, [BsiCheckStatus]::Error, [BsiSeverity]::Medium,
            "Could not list Network Watchers"
        )
        $result.CheckFunction = 'Test-NetworkWatcher'
        return @($result)
    }

    $watchers = $response.Output | ConvertFrom-Json
    $nw = $watchers | Where-Object { $_.location -eq $Location } | Select-Object -First 1

    $pass = $null -ne $nw
    $status = if ($pass) { [BsiCheckStatus]::Pass } else { [BsiCheckStatus]::Fail }
    $details = if ($pass) {
        "Network Watcher '$($nw.name)' found in $Location"
    } else {
        "No Network Watcher in $Location (found $($watchers.Count) in other regions)"
    }

    $result = [ComplianceResult]::new(
        'DET.3.1', "Network Watcher in $Location", 'Monitoring',
        [BsiCheckMode]::Remote, $status, [BsiSeverity]::Medium, $details
    )
    $result.CheckFunction = 'Test-NetworkWatcher'
    $result.BsiReference  = 'BSI-G-00504'
    return @($result)
}
