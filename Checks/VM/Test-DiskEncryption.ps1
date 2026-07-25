#Requires -Version 5.1
<#
.SYNOPSIS
    KONF.11.8 - Verschluesselung schuetzenswerter Daten at-rest.
.DESCRIPTION
    Verifies VM OS disks are encrypted via EncryptionAtHost, DiskEncryptionSet,
    or Azure Disk Encryption extension.
#>
function Test-DiskEncryption {
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
                'KONF.11.8', "$vmName OS disk encryption", 'VM',
                [BsiCheckMode]::Remote, [BsiCheckStatus]::Error, [BsiSeverity]::High,
                "Could not retrieve VM $vmName"
            )
            $results[-1].CheckFunction = 'Test-DiskEncryption'
            continue
        }

        $vm = $response.Output | ConvertFrom-Json

        # Check EncryptionAtHost
        $encryptionAtHost = $null -ne $vm.securityProfile -and $vm.securityProfile.encryptionAtHost -eq $true

        # Check DiskEncryptionSet on OS disk
        $hasDes = $false
        $osDiskId = $vm.storageProfile.osDisk.managedDisk.id
        if ($osDiskId) {
            $diskParts = $osDiskId.Split('/')
            if ($diskParts.Length -ge 8) {
                $diskRg   = $diskParts[4]
                $diskName = $diskParts[-1]
                $diskResp = Get-AzCliResponse -Arguments @("disk", "show", "-g", $diskRg, "-n", $diskName) -SubscriptionId $SubscriptionId
                if ($diskResp.ExitCode -eq 0) {
                    $disk = $diskResp.Output | ConvertFrom-Json
                    $hasDes = $null -ne $disk.encryption.diskEncryptionSetId
                }
            }
        }

        # Check ADE extension
        $hasAde = $null -ne ($vm.resources | Where-Object { $_.id -match 'AzureDiskEncryption' })

        $encrypted = $encryptionAtHost -or $hasDes -or $hasAde
        $status = if ($encrypted) { [BsiCheckStatus]::Pass } else { [BsiCheckStatus]::Fail }
        $details = "EncryptionAtHost: $encryptionAtHost, DiskEncryptionSet: $hasDes, ADE: $hasAde"

        $result = [ComplianceResult]::new(
            'KONF.11.8', "$vmName OS disk encryption", 'VM',
            [BsiCheckMode]::Remote, $status, [BsiSeverity]::High, $details
        )
        $result.CheckFunction = 'Test-DiskEncryption'
        $result.BsiReference  = 'BSI-G-00684'
        $result.Evidence      = $details
        if (-not $encrypted) {
            $result.Remediation = "Enable EncryptionAtHost on VM $vmName or attach a DiskEncryptionSet"
        }
        $result.Metadata['vm'] = $vmName
        $results += $result
    }

    return $results
}
