#Requires -Version 5.1
<#
.SYNOPSIS
    Main entry point: validates Azure 3-tier deployment against BSI IT-Grundschutz++.

.DESCRIPTION
    Runs compliance checks in either Local mode (static script analysis) or
    Remote mode (live Azure resource inspection). Returns results and optionally
    exports to JSON, SARIF, JUnit XML, or HTML.

.PARAMETER Local
    Validate a deployment script via regex pattern matching.

.PARAMETER Remote
    Validate deployed Azure infrastructure via Azure CLI.

.PARAMETER ScriptPath
    Path to deployment script for Local mode.

.PARAMETER ConfigPath
    Path to config.ps1 for Remote mode.

.PARAMETER SubscriptionId
    Optional Azure subscription ID.

.PARAMETER Sync
    Force re-download of BSI catalog before validation.

.PARAMETER OutputFormat
    Output format(s): Console, Json, Sarif, JUnitXml, Html. Can be comma-separated.

.PARAMETER OutputPath
    Path to write the output file(s). Suffix is appended per format.

.PARAMETER NsgNames
    NSG names to check (default: NSG-Web, NSG-App, NSG-DB).

.PARAMETER DenyPorts
    Ports to check for Deny rules (default: 22, 3389).

.EXAMPLE
    Invoke-BsiCompliance -Local -ScriptPath .\create_3-tier-webapp_VM_v2.ps1

.EXAMPLE
    Invoke-BsiCompliance -Remote -ConfigPath .\config.ps1 -OutputFormat Sarif,Html -OutputPath .\reports\compliance

.EXAMPLE
    Invoke-BsiCompliance -Sync  # Just sync catalog, no validation
#>
function Invoke-BsiCompliance {
    [CmdletBinding(DefaultParameterSetName = 'Remote')]
    param(
        [Parameter(ParameterSetName = 'Local')]
        [switch]$Local,

        [Parameter(ParameterSetName = 'Remote')]
        [switch]$Remote,

        [Parameter(ParameterSetName = 'Sync')]
        [switch]$Sync,

        [string]$ScriptPath = '',
        [string]$ConfigPath = '.\config.ps1',
        [string]$SubscriptionId = '',

        [string[]]$OutputFormat = @('Console'),
        [string]$OutputPath = '',

        [string[]]$NsgNames = @('NSG-Web', 'NSG-App', 'NSG-DB'),
        [string[]]$DenyPorts = @('22', '3389')
    )

    $ErrorActionPreference = 'Continue'

    # --- Determine mode ---
    if (-not $Local -and -not $Remote -and -not $Sync) {
        $Remote = $true
    }

    # --- Resolve paths (self-contained: all data lives in ModuleRoot/Data/) ---
    # Fallback: if function is invoked outside module context, derive from function location
    if (-not $script:ModuleRoot) {
        $funcDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
        $script:ModuleRoot = Split-Path -Parent $funcDir
    }
    $moduleRoot   = $script:ModuleRoot
    $dataDir      = Join-Path $moduleRoot 'Data'
    $cacheDir     = Join-Path $dataDir 'cache'
    $catalogPath  = Join-Path $cacheDir 'Grundschutz++-catalog.json'
    $mappingPath  = Join-Path $dataDir 'bsi-azure-mapping.json'

    # --- Sync mode ---
    if ($Sync) {
        if (-not (Test-Path -LiteralPath $mappingPath)) {
            throw "Mapping file not found: $mappingPath"
        }
        Sync-BsiCatalog -OutPath $catalogPath -MappingPath $mappingPath
        $mapping = Get-BsiMapping -Path $mappingPath
        Write-Host "[OK] BSI catalog synchronised." -ForegroundColor Green
        if (-not $Local -and -not $Remote) {
            return
        }
    }

    # --- Reset results ---
    Reset-BsiResults

    # --- Load mapping ---
    if (-not (Test-Path -LiteralPath $mappingPath)) {
        throw "Mapping file not found: $mappingPath. Run with -Sync first."
    }
    $mapping = Get-BsiMapping -Path $mappingPath

    # --- Load catalog ---
    $catalog = Get-BsiCatalog -Path $catalogPath
    if ($catalog) {
        $catalogControls = Get-BsiCatalogControls -Catalog $catalog
        $orphaned = Resolve-BsiOrphans -Mapping $mapping -CatalogControls $catalogControls
        if ($orphaned.Count -gt 0) {
            Write-Warning "Orphaned controls (not in catalog): $($orphaned -join ', ')"
        }
    }

    # --- Print header ---
    $modeStr = if ($Local) { 'Local' } elseif ($Remote) { 'Remote' } else { 'Sync' }
    Write-Host "`n=============================================" -ForegroundColor Cyan
    Write-Host "BSI IT-Grundschutz++ Compliance Validator" -ForegroundColor Cyan
    Write-Host "Mode: $modeStr | Checks: $($mapping.mappings.Count) controls" -ForegroundColor Cyan
    Write-Host "=============================================`n" -ForegroundColor Cyan

    # ===================== LOCAL MODE =====================
    if ($Local) {
        if (-not $ScriptPath) {
            throw "-ScriptPath is required for Local mode."
        }
        if (-not (Test-Path -LiteralPath $ScriptPath)) {
            throw "Script file not found: $ScriptPath"
        }

        $content = Get-Content -Raw -Path $ScriptPath

        foreach ($entry in $mapping.mappings) {
            $lc = $entry.localCheck
            if (-not $lc) { continue }

            $controlId = $entry.controlId
            $catalogEntry = if ($catalogControls) {
                $catalogControls | Where-Object { $_.id -eq $controlId } | Select-Object -First 1
            }
            $title = if ($catalogEntry -and $catalogEntry.title) { $catalogEntry.title } else { $entry.title }

            $matched = 0
            $required = $lc.mustMatchAtLeast
            $maxAllowed = if ($null -ne $lc.maxAllowed) { $lc.maxAllowed } else { [int]::MaxValue }

            foreach ($pattern in $lc.patterns) {
                if ([regex]::IsMatch($content, $pattern)) {
                    $matched++
                }
            }

            $pass = ($matched -ge $required) -and ($matched -le $maxAllowed)
            $status = if ($pass) { [BsiCheckStatus]::Pass } else { [BsiCheckStatus]::Fail }

            Add-BsiResult -ControlId $controlId -Title $title -Category $entry.category `
                -Mode ([BsiCheckMode]::Local) -Status $status `
                -Severity ([BsiSeverity]::Medium) `
                -Details "$($lc.description) (matched $matched / required $required, max $maxAllowed)" `
                -CheckFunction 'Invoke-BsiCompliance'
        }
    }

    # ===================== REMOTE MODE =====================
    if ($Remote) {
        # Load config
        $configFullPath = Resolve-Path -Path $ConfigPath -ErrorAction SilentlyContinue
        if (-not $configFullPath -or -not (Test-Path -LiteralPath $configFullPath)) {
            throw "Config file not found: $ConfigPath"
        }
        . $configFullPath

        if (-not $rgName) { throw "`$rgName is not defined in config.ps1" }

        # Verify Azure CLI
        Test-AzCliReady | Out-Null
        if ($SubscriptionId) {
            $script:moduleSubscriptionId = $SubscriptionId
        }

        # --- Network checks ---
        $nsgResults = Test-NsgDenyInbound -ResourceGroup $rgName -NsgNames $NsgNames -Ports $DenyPorts -SubscriptionId $SubscriptionId
        foreach ($r in $nsgResults) { Add-BsiResultObject -Result $r }

        # VNet subnets
        $vnetSubnetConfig = @{}
        if ($subnetWeb) { $vnetSubnetConfig[$subnetWeb] = @{ AddressPrefix = $subnetWebAddress; NsgName = 'NSG-Web' } }
        if ($subnetApp) { $vnetSubnetConfig[$subnetApp] = @{ AddressPrefix = $subnetAppAddress; NsgName = 'NSG-App' } }
        if ($subnetDb)  { $vnetSubnetConfig[$subnetDb]  = @{ AddressPrefix = $subnetDBAddress; NsgName = 'NSG-DB' } }

        $vnetResults = Test-VNetSubnets -ResourceGroup $rgName -VNetName $vnetSpoke1Name -ExpectedSubnets $vnetSubnetConfig -SubscriptionId $SubscriptionId
        foreach ($r in $vnetResults) { Add-BsiResultObject -Result $r }

        # VNet Peering
        if ($vnetHubName) {
            $peerResults = Test-VNetPeering -ResourceGroup $rgName -HubVNetName $vnetHubName -SpokeVNetName $vnetSpoke1Name -SubscriptionId $SubscriptionId
            foreach ($r in $peerResults) { Add-BsiResultObject -Result $r }
        }

        # No Public IP on backend
        $backendTiers = @('db', 'app')
        $noPubIpResults = Test-NoPublicIp -ResourceGroup $rgName -BackendTiers $backendTiers -WebTier 'web' -SubscriptionId $SubscriptionId
        foreach ($r in $noPubIpResults) { Add-BsiResultObject -Result $r }

        # Bastion
        if ($bastionHostName) {
            $bastionResults = Test-BastionExists -ResourceGroup $rgName -BastionHostName $bastionHostName -SubscriptionId $SubscriptionId
            foreach ($r in $bastionResults) { Add-BsiResultObject -Result $r }
        }

        # NAT Gateway
        $natResults = Test-NatGateway -ResourceGroup $rgName -NatGatewayName 'nat-gateway-prod' -SubscriptionId $SubscriptionId
        foreach ($r in $natResults) { Add-BsiResultObject -Result $r }

        # --- VM checks ---
        $vmNames = @('VM-web', 'VM-app', 'VM-db')
        $diskResults = Test-DiskEncryption -ResourceGroup $rgName -VmNames $vmNames -SubscriptionId $SubscriptionId
        foreach ($r in $diskResults) { Add-BsiResultObject -Result $r }

        $tlsResults = Test-TlsVersion -ResourceGroup $rgName -StorageAccountName $storageaccountName -SubscriptionId $SubscriptionId
        foreach ($r in $tlsResults) { Add-BsiResultObject -Result $r }

        $imgResults = Test-VmImageVersion -ResourceGroup $rgName -VmNames $vmNames -SubscriptionId $SubscriptionId
        foreach ($r in $imgResults) { Add-BsiResultObject -Result $r }

        # --- Identity checks ---
        $idResults = Test-ManagedIdentity -ResourceGroup $rgName -VmNames $vmNames -SubscriptionId $SubscriptionId
        foreach ($r in $idResults) { Add-BsiResultObject -Result $r }

        $kvResults = Test-KeyVaultConfig -ResourceGroup $rgName -KeyVaultName $keyVaultName -SecretName $secretName -SubscriptionId $SubscriptionId
        foreach ($r in $kvResults) { Add-BsiResultObject -Result $r }

        $rbacResults = Test-RbacRoles -ResourceGroup $rgName -KeyVaultName $keyVaultName -SubscriptionId $SubscriptionId
        foreach ($r in $rbacResults) { Add-BsiResultObject -Result $r }

        # --- Backup checks ---
        $backupResults = Test-AzureBackup -ResourceGroup $rgName -VaultName $recoveryServicesVaultName -VmNames $vmNames -SubscriptionId $SubscriptionId
        foreach ($r in $backupResults) { Add-BsiResultObject -Result $r }

        $rsvResults = Test-RecoveryServicesVault -ResourceGroup $rgName -VaultName $recoveryServicesVaultName -SubscriptionId $SubscriptionId
        foreach ($r in $rsvResults) { Add-BsiResultObject -Result $r }

        # --- Monitoring checks ---
        if ($location) {
            $nwResults = Test-NetworkWatcher -Location $location -SubscriptionId $SubscriptionId
            foreach ($r in $nwResults) { Add-BsiResultObject -Result $r }

            $flowResults = Test-FlowLogs -Location $location -NsgNames $NsgNames -SubscriptionId $SubscriptionId
            foreach ($r in $flowResults) { Add-BsiResultObject -Result $r }
        }

        $diagResults = Test-DiagnosticSettings -ResourceGroup $rgName -ResourceName $keyVaultName -SubscriptionId $SubscriptionId
        foreach ($r in $diagResults) { Add-BsiResultObject -Result $r }

        # --- Policy checks ---
        $polResults = Test-AzurePolicy -SubscriptionId $SubscriptionId
        foreach ($r in $polResults) { Add-BsiResultObject -Result $r }
    }

    # --- Get results and export ---
    $results = @($script:BsiResults)
    $summary = Get-BsiSummary

    # Export
    $formats = ($OutputFormat -join ',') -split ',' | ForEach-Object { $_.Trim() }
    foreach ($fmt in $formats) {
        $fmtLower = $fmt.ToLower()
        $basePath = if ($OutputPath) { $OutputPath } else { ".\bsi-compliance" }

        switch ($fmtLower) {
            'console'  { Export-Console -Results $results }
            'json'     { Export-Json -Results $results -OutputPath "$basePath.json" }
            'sarif'    { Export-Sarif -Results $results -OutputPath "$basePath.sarif" }
            'junitxml' { Export-JUnitXml -Results $results -OutputPath "$basePath.junit.xml" }
            'html'     { Export-Html -Results $results -OutputPath "$basePath.html" }
        }
    }

    # Return summary for pipeline use
    $exitCode = [Math]::Min($summary.Failed, 255)
    return $exitCode
}
