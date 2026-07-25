#Requires -Version 5.1
<#
.SYNOPSIS
    BSI IT-Grundschutz++ Compliance Validation Module for Azure.
.DESCRIPTION
    Provides functions to validate Azure 3-tier deployments against BSI
    IT-Grundschutz++ controls. Supports local script analysis, remote
    Azure resource validation, and multiple output formats.

    Architecture: Internet -> VM-web -> VM-app -> VM-db
    Controls: ARCH.5.2, ARCH.2.1, ARCH.5.1, KONF.11.8, BER.6, NOT.4,
              DET.3, BER.2, KONF.2.6, BER.4 + 15 additional checks.

.NOTES
    Version: 2.0.0
    Author: Valerii Dundukov
    License: MIT
#>

$script:ModuleRoot = $PSScriptRoot
$script:ModuleData    = Join-Path $script:ModuleRoot 'Data'
$script:ModuleCache   = Join-Path $script:ModuleData 'cache'

# --- Ensure Data directories exist ---
if (-not (Test-Path -LiteralPath $script:ModuleCache)) {
    New-Item -ItemType Directory -Path $script:ModuleCache -Force | Out-Null
}

# --- Load Enums ---
. (Join-Path $script:ModuleRoot 'Enums' 'Severity.psm1')

# --- Load Classes ---
. (Join-Path $script:ModuleRoot 'Classes' 'ComplianceResult.psm1')

# --- Load Private functions ---
$privatePath = Join-Path $script:ModuleRoot 'Private'
foreach ($file in (Get-ChildItem -Path $privatePath -Filter '*.ps1' -Recurse)) {
    . $file.FullName
}

# --- Load Check functions ---
$checksPath = Join-Path $script:ModuleRoot 'Checks'
foreach ($file in (Get-ChildItem -Path $checksPath -Filter '*.ps1' -Recurse)) {
    . $file.FullName
}

# --- Load Exporters ---
$exportersPath = Join-Path $script:ModuleRoot 'Exporters'
foreach ($file in (Get-ChildItem -Path $exportersPath -Filter '*.ps1' -Recurse)) {
    . $file.FullName
}

# --- Load Public functions ---
$publicPath = Join-Path $script:ModuleRoot 'Public'
foreach ($file in (Get-ChildItem -Path $publicPath -Filter '*.ps1' -Recurse)) {
    . $file.FullName
}

# --- Module-level defaults (self-contained, paths relative to module Data directory) ---
$script:DefaultConfigPath   = '.\config.ps1'
$script:DefaultMappingFile  = 'bsi-azure-mapping.json'
$script:DefaultMappingPath  = Join-Path $script:ModuleData $script:DefaultMappingFile
$script:DefaultCacheDir     = $script:ModuleCache
$script:DefaultCatalogPath  = Join-Path $script:DefaultCacheDir 'Grundschutz++-catalog.json'

# --- Register convenience alias ---
New-Alias -Name ibs -Value Invoke-BsiCompliance -Force -ErrorAction SilentlyContinue
