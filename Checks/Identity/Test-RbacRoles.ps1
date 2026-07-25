#Requires -Version 5.1
<#
.SYNOPSIS
    BER.4 - Berechtigungsmanagement: RBAC Rollen fuer Key Vault Zugriff.
.DESCRIPTION
    Verifies VMs have the Key Vault Secrets User role assigned.
#>
function Test-RbacRoles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ResourceGroup,
        [Parameter(Mandatory)][string]$KeyVaultName,
        [string]$SubscriptionId = ''
    )

    $results = @()

    # Get Key Vault resource ID
    $kvResp = Get-AzCliResponse -Arguments @("keyvault", "show", "--name", $KeyVaultName, "-g", $ResourceGroup, "--query", "id") -SubscriptionId $SubscriptionId
    if ($kvResp.ExitCode -ne 0 -or -not $kvResp.Output) {
        $results += [ComplianceResult]::new(
            'BER.4', 'RBAC roles on Key Vault', 'Identity',
            [BsiCheckMode]::Remote, [BsiCheckStatus]::Error, [BsiSeverity]::High,
            "Could not retrieve Key Vault $KeyVaultName for RBAC check"
        )
        $results[-1].CheckFunction = 'Test-RbacRoles'
        return $results
    }

    $kvId = ($kvResp.Output | ConvertFrom-Json).id

    # List role assignments on Key Vault
    $rolesResp = Get-AzCliResponse -Arguments @("role", "assignment", "list", "--scope", $kvId) -SubscriptionId $SubscriptionId
    if ($rolesResp.ExitCode -ne 0 -or -not $rolesResp.Output) {
        $results += [ComplianceResult]::new(
            'BER.4', 'RBAC roles on Key Vault', 'Identity',
            [BsiCheckMode]::Remote, [BsiCheckStatus]::Fail, [BsiSeverity]::High,
            "No role assignments found on Key Vault"
        )
        $results[-1].CheckFunction = 'Test-RbacRoles'
        $results[-1].Remediation  = "Assign 'Key Vault Secrets User' role to VM Managed Identities"
        return $results
    }

    $assignments = $rolesResp.Output | ConvertFrom-Json
    $kvSecretsUserRole = $assignments | Where-Object { $_.roleDefinitionName -match 'Key Vault Secrets' }

    $pass = $null -ne $kvSecretsUserRole -and $kvSecretsUserRole.Count -gt 0
    $status = if ($pass) { [BsiCheckStatus]::Pass } else { [BsiCheckStatus]::Fail }
    $details = if ($pass) {
        "Found $($kvSecretsUserRole.Count) Key Vault Secrets role assignment(s)"
    } else {
        "No 'Key Vault Secrets User' role found on $KeyVaultName"
    }

    $result = [ComplianceResult]::new(
        'BER.4', 'RBAC roles for Key Vault access', 'Identity',
        [BsiCheckMode]::Remote, $status, [BsiSeverity]::High, $details
    )
    $result.CheckFunction = 'Test-RbacRoles'
    $result.BsiReference  = 'BSI-G-00620'
    if (-not $pass) {
        $result.Remediation = "Assign 'Key Vault Secrets User' role to VM Managed Identities via: az role assignment create --role 'Key Vault Secrets User'"
    }
    $results += $result

    return $results
}
