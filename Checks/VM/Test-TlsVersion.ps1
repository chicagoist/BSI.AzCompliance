#Requires -Version 5.1
<#
.SYNOPSIS
    CON.1 - Verschluesselung: TLS 1.2 Minimum auf Storage Accounts.
.DESCRIPTION
    Verifies storage accounts enforce TLS 1.2 and disable public blob access.
#>
function Test-TlsVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ResourceGroup,
        [Parameter(Mandatory)][string]$StorageAccountName,
        [string]$SubscriptionId = ''
    )

    $results = @()

    $response = Get-AzCliResponse -Arguments @("storage", "account", "show", "--name", $StorageAccountName, "-g", $ResourceGroup) -SubscriptionId $SubscriptionId

    if ($response.ExitCode -ne 0 -or -not $response.Output) {
        $results += [ComplianceResult]::new(
            'CON.1', "Storage Account $StorageAccountName exists", 'VM',
            [BsiCheckMode]::Remote, [BsiCheckStatus]::Error, [BsiSeverity]::High,
            "Could not retrieve Storage Account $StorageAccountName"
        )
        $results[-1].CheckFunction = 'Test-TlsVersion'
        return $results
    }

    $sa = $response.Output | ConvertFrom-Json

    # TLS version check
    $tlsOk = $sa.minimumTlsVersion -eq 'TLS1_2'
    $results += [ComplianceResult]::new(
        'CON.1', "Storage Account TLS 1.2", 'VM',
        [BsiCheckMode]::Remote, $(if ($tlsOk) { [BsiCheckStatus]::Pass } else { [BsiCheckStatus]::Fail }),
        [BsiSeverity]::High,
        "minimumTlsVersion = $($sa.minimumTlsVersion)"
    )
    $results[-1].CheckFunction  = 'Test-TlsVersion'
    $results[-1].BsiReference   = 'BSI-G-00469'
    $results[-1].Remediation   = "Set minimumTlsVersion to TLS1_2 on storage account"

    # HTTPS-only
    $httpsOk = $sa.enableHttpsTrafficOnly -eq $true
    $results += [ComplianceResult]::new(
        'CON.1', "Storage Account HTTPS-only", 'VM',
        [BsiCheckMode]::Remote, $(if ($httpsOk) { [BsiCheckStatus]::Pass } else { [BsiCheckStatus]::Fail }),
        [BsiSeverity]::High,
        "enableHttpsTrafficOnly = $($sa.enableHttpsTrafficOnly)"
    )
    $results[-1].CheckFunction = 'Test-TlsVersion'

    # Public blob access disabled
    $publicOk = $sa.allowBlobPublicAccess -eq $false
    $results += [ComplianceResult]::new(
        'CON.1', "Storage Account public blob access disabled", 'VM',
        [BsiCheckMode]::Remote, $(if ($publicOk) { [BsiCheckStatus]::Pass } else { [BsiCheckStatus]::Fail }),
        [BsiSeverity]::Medium,
        "allowBlobPublicAccess = $($sa.allowBlobPublicAccess)"
    )
    $results[-1].CheckFunction = 'Test-TlsVersion'

    return $results
}
