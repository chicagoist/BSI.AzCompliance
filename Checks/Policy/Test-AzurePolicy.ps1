#Requires -Version 5.1
<#
.SYNOPSIS
    KONF.2.6 - Automatische Konfigurationsverwaltung via Azure Policy.
.DESCRIPTION
    Verifies security-related Azure Policy assignments exist.
#>
function Test-AzurePolicy {
    [CmdletBinding()]
    param(
        [string]$SubscriptionId = ''
    )

    $response = Get-AzCliResponse -Arguments @("policy", "assignment", "list") -SubscriptionId $SubscriptionId

    if ($response.ExitCode -ne 0 -or -not $response.Output) {
        $result = [ComplianceResult]::new(
            'KONF.2.6', 'Azure Policy assignments', 'Policy',
            [BsiCheckMode]::Remote, [BsiCheckStatus]::Error, [BsiSeverity]::Medium,
            "Could not list policy assignments"
        )
        $result.CheckFunction = 'Test-AzurePolicy'
        return @($result)
    }

    $policies = $response.Output | ConvertFrom-Json
    $secPolicies = $policies | Where-Object {
        $_.displayName -match 'Security|Encryption|TLS|Defender|Network|Allowed|Deny'
    }

    $pass = $null -ne $secPolicies -and $secPolicies.Count -gt 0
    $status = if ($pass) { [BsiCheckStatus]::Pass } else { [BsiCheckStatus]::Fail }
    $details = if ($pass) {
        "Found $($secPolicies.Count) security-related policy assignment(s) out of $($policies.Count) total"
    } else {
        "No security-related policies found among $($policies.Count) assignment(s)"
    }

    $result = [ComplianceResult]::new(
        'KONF.2.6', 'Azure Policy security assignments', 'Policy',
        [BsiCheckMode]::Remote, $status, [BsiSeverity]::Medium, $details
    )
    $result.CheckFunction = 'Test-AzurePolicy'
    $result.BsiReference  = 'BSI-G-00661'
    if (-not $pass) {
        $result.Remediation = "Assign Azure Policy initiatives for security baselines (e.g. CIS, NIST, or custom)"
    }
    return @($result)
}
