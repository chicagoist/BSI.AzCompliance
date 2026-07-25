#Requires -Version 5.1
<#
.SYNOPSIS
    OPS.1.1.4 - Monitoring: Diagnostics Settings.
.DESCRIPTION
    Verifies diagnostic settings are configured on a resource (e.g. Key Vault).
#>
function Test-DiagnosticSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ResourceGroup,
        [Parameter(Mandatory)][string]$ResourceName,
        [string]$SubscriptionId = ''
    )

    # Get resource ID
    $kvResp = Get-AzCliResponse -Arguments @("keyvault", "show", "--name", $ResourceName, "-g", $ResourceGroup, "--query", "id") -SubscriptionId $SubscriptionId
    if ($kvResp.ExitCode -ne 0 -or -not $kvResp.Output) {
        $result = [ComplianceResult]::new(
            'OPS.1.1.4', "Diagnostic settings on $ResourceName", 'Monitoring',
            [BsiCheckMode]::Remote, [BsiCheckStatus]::Error, [BsiSeverity]::Medium,
            "Could not retrieve resource $ResourceName"
        )
        $result.CheckFunction = 'Test-DiagnosticSettings'
        return @($result)
    }

    $resourceId = ($kvResp.Output | ConvertFrom-Json).id

    $diagResp = Get-AzCliResponse -Arguments @("monitor", "diagnostic-settings", "list", "--resource", $resourceId) -SubscriptionId $SubscriptionId

    if ($diagResp.ExitCode -ne 0 -or -not $diagResp.Output) {
        $result = [ComplianceResult]::new(
            'OPS.1.1.4', "Diagnostic settings on $ResourceName", 'Monitoring',
            [BsiCheckMode]::Remote, [BsiCheckStatus]::Fail, [BsiSeverity]::Medium,
            "Could not list diagnostic settings for $ResourceName"
        )
        $result.CheckFunction = 'Test-DiagnosticSettings'
        $result.Remediation  = "Configure diagnostic settings to send Key Vault logs to Log Analytics"
        return @($result)
    }

    $diags = $diagResp.Output | ConvertFrom-Json
    $hasDiags = $null -ne $diags -and $diags.Length -gt 0

    $result = [ComplianceResult]::new(
        'OPS.1.1.4', "Diagnostic settings on $ResourceName", 'Monitoring',
        [BsiCheckMode]::Remote, $(if ($hasDiags) { [BsiCheckStatus]::Pass } else { [BsiCheckStatus]::Fail }),
        [BsiSeverity]::Medium,
        "Found $(if ($hasDiags) { $diags.Length } else { 0 }) diagnostic setting(s)"
    )
    $result.CheckFunction = 'Test-DiagnosticSettings'
    $result.BsiReference  = 'BSI-G-00785'
    return @($result)
}
