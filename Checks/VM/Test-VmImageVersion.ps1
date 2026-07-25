#Requires -Version 5.1
<#
.SYNOPSIS
    APP.4.2 - Patch-Management: VM Image Aktualitaet.
.DESCRIPTION
    Checks that VMs are running a supported Ubuntu image version.
#>
function Test-VmImageVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ResourceGroup,
        [Parameter(Mandatory)][string[]]$VmNames,
        [string]$SubscriptionId = ''
    )

    $results = @()

    foreach ($vmName in $VmNames) {
        $response = Get-AzCliResponse -Arguments @("vm", "show", "-g", $ResourceGroup, "-n", $vmName, "--query", "storageProfile.imageReference") -SubscriptionId $SubscriptionId

        if ($response.ExitCode -ne 0 -or -not $response.Output) {
            $results += [ComplianceResult]::new(
                'APP.4.2', "$vmName image version", 'VM',
                [BsiCheckMode]::Remote, [BsiCheckStatus]::Error, [BsiSeverity]::Medium,
                "Could not retrieve image info for $vmName"
            )
            $results[-1].CheckFunction = 'Test-VmImageVersion'
            continue
        }

        $image = $response.Output | ConvertFrom-Json
        $publisher = $image.publisher
        $offer     = $image.offer
        $sku       = $image.sku
        $version   = $image.version

        # Check if using latest or a pinned version
        $isLatest = $version -eq 'latest' -or $version -eq 'Latest'
        $details  = "Publisher: $publisher, Offer: $offer, SKU: $sku, Version: $version"

        $result = [ComplianceResult]::new(
            'APP.4.2', "$vmName image version", 'VM',
            [BsiCheckMode]::Remote,
            $(if ($isLatest) { [BsiCheckStatus]::Pass } else { [BsiCheckStatus]::Fail }),
            [BsiSeverity]::Medium, $details
        )
        if (-not $isLatest) {
            $result.Remediation = "Consider using 'latest' image version for automatic patch updates"
        }
        $result.CheckFunction = 'Test-VmImageVersion'
        $result.BsiReference  = 'BSI-G-00434'
        $result.Evidence      = $details
        $result.Metadata['vm'] = $vmName
        $results += $result
    }

    return $results
}
