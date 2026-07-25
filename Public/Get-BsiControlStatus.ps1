#Requires -Version 5.1
<#
.SYNOPSIS
    Query compliance results by control ID, category, or status.
.PARAMETER ControlId
    Filter by BSI control ID (e.g. ARCH.5.2).
.PARAMETER Category
    Filter by category (e.g. Network, VM).
.PARAMETER FailedOnly
    Show only failed checks.
.OUTPUTS
    Array of ComplianceResult objects.
#>
function Get-BsiControlStatus {
    [CmdletBinding()]
    param(
        [string]$ControlId = '',
        [string]$Category = '',
        [switch]$FailedOnly
    )

    $results = @($script:BsiResults)

    if ($ControlId) {
        $results = @($results | Where-Object { $_.ControlId -eq $ControlId })
    }
    if ($Category) {
        $results = @($results | Where-Object { $_.Category -eq $Category })
    }
    if ($FailedOnly) {
        $results = @($results | Where-Object { $_.Status -ne [BsiCheckStatus]::Pass })
    }

    return $results
}
