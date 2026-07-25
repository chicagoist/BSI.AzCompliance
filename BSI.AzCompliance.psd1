@{
    RootModule        = 'BSI.AzCompliance.psm1'
    ModuleVersion     = '3.0.0'
    GUID              = 'b1a2c3d4-e5f6-7890-abcd-ef1234567890'
    Author            = 'Valerii Dundukov'
    CompanyName       = 'CYBER-SECURITY'
    Copyright         = '(c) 2026 Valerii Dundukov. MIT License.'
    Description       = 'BSI IT-Grundschutz++ compliance validation for Azure 3-tier deployments. Self-contained PowerShell module with embedded OSCAL catalog mapping. Supports local script analysis, remote Azure resource validation, and SARIF/JUnit/HTML export for CI/CD integration.'

    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        'Invoke-BsiCompliance',
        'Get-BsiControlStatus',
        'New-BsiComplianceReport',
        'Export-Console',
        'Export-Json',
        'Export-Sarif',
        'Export-JUnitXml',
        'Export-Html',
        'Reset-BsiResults',
        'Get-BsiSummary',
        'Add-BsiResult',
        'Add-BsiResultObject',
        'New-BsiComplianceResult',
        'Sync-BsiCatalog',
        'Get-BsiMapping',
        'Get-BsiCatalogControls',
        'Get-AzCliResponse',
        'Test-AzCliReady',
        'Test-NsgDenyInbound',
        'Test-VNetSubnets',
        'Test-NoPublicIp',
        'Test-VNetPeering',
        'Test-BastionExists',
        'Test-NatGateway',
        'Test-DiskEncryption',
        'Test-TlsVersion',
        'Test-VmImageVersion',
        'Test-ManagedIdentity',
        'Test-KeyVaultConfig',
        'Test-RbacRoles',
        'Test-AzureBackup',
        'Test-RecoveryServicesVault',
        'Test-FlowLogs',
        'Test-NetworkWatcher',
        'Test-DiagnosticSettings',
        'Test-AzurePolicy'
    )

    CmdletsToExport   = @()
    AliasesToExport   = @('ibs')

    PrivateData = @{
        PSData = @{
            Tags       = @('BSI', 'Compliance', 'Azure', 'IT-Grundschutz', 'OSCAL', 'Security', 'Cloud', 'DevSecOps')
            LicenseUri = 'https://opensource.org/licenses/MIT'
            ProjectUri = 'https://github.com/JendrixBln/BSI-AzCompliance'
        }
    }
}
