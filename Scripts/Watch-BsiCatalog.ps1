#Requires -Version 5.1
<#
.SYNOPSIS
    BSI IT-Grundschutz++ Catalog Change Monitor.
.DESCRIPTION
    Standalone script that checks the BSI GitHub repository for catalog
    updates. Can be run manually, via cron/task scheduler, or in CI/CD.
    When an update is detected, optionally auto-syncs the catalog.

    Usage:
        .\Watch-BsiCatalog.ps1
        .\Watch-BsiCatalog.ps1 -AutoSync
        .\Watch-BsiCatalog.ps1 -OutputPath .\reports\catalog-check.json

.NOTES
    Version: 1.0.0
    Author: Valerii Dundukov
    License: MIT
#>

[CmdletBinding()]
param(
    [switch]$AutoSync,
    [string]$OutputPath = '',
    [switch]$Quiet
)

$ErrorActionPreference = 'Continue'

# Resolve paths relative to this script
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptDir) { $scriptDir = '.' }
$moduleRoot = Join-Path $scriptDir '..'
$mappingPath = Join-Path $moduleRoot 'Data' 'bsi-azure-mapping.json'
$modulePsd1 = Join-Path $moduleRoot 'BSI.AzCompliance.psd1'
$cacheDir = Join-Path $moduleRoot 'Data' 'cache'
$catalogPath = Join-Path $cacheDir 'Grundschutz++-catalog.json'

# Import module
if (Test-Path -LiteralPath $modulePsd1) {
    Import-Module $modulePsd1 -Force
} else {
    Write-Error "Module not found at: $modulePsd1"
    exit 2
}

# Ensure cache directory
if (-not (Test-Path -LiteralPath $cacheDir)) {
    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
}

# Check for updates
if (-not $Quiet) {
    Write-Host "`n=============================================" -ForegroundColor Cyan
    Write-Host "BSI Catalog Change Monitor" -ForegroundColor Cyan
    Write-Host "Repository: BSI-Bund/Stand-der-Technik-Bibliothek" -ForegroundColor Cyan
    Write-Host "Catalog:    Grundschutz++-resolved_catalog.json" -ForegroundColor Cyan
    Write-Host "=============================================`n" -ForegroundColor Cyan
}

$check = Test-BsiCatalogUpdate -MappingPath $mappingPath

if ($check.Error) {
    Write-Warning "Monitor check failed: $($check.Error)"
    exit 1
}

if (-not $Quiet) {
    Write-Host ("Latest commit SHA : " + $check.LatestSha.Substring(0, 12)) -ForegroundColor White
    Write-Host ("Stored commit SHA : " + $(if ($check.StoredSha -and $check.StoredSha -ne '(none)') { $check.StoredSha.Substring(0, [Math]::Min(12, $check.StoredSha.Length)) } else { '(none)' })) -ForegroundColor White
    Write-Host ("Commit date       : " + $check.CommitDate) -ForegroundColor White
    Write-Host ("Commit message    : " + $check.CommitMessage) -ForegroundColor DarkGray
    Write-Host ("")

    if ($check.HasUpdate) {
        Write-Host "[!] UPDATE AVAILABLE!" -ForegroundColor Yellow
        Write-Host ("    The BSI catalog has been updated since last sync.") -ForegroundColor Yellow
    } else {
        Write-Host "[OK] Catalog is up-to-date." -ForegroundColor Green
    }
}

# Auto-sync if requested and update available
if ($AutoSync -and $check.HasUpdate) {
    Write-Host "`n--- Auto-syncing catalog ---" -ForegroundColor Cyan
    try {
        Sync-BsiCatalog -OutPath $catalogPath -MappingPath $mappingPath
        Write-Host "[OK] Catalog synced and SHA updated." -ForegroundColor Green
    } catch {
        Write-Error "Auto-sync failed: $_"
        exit 1
    }
}

# Export results
if ($OutputPath) {
    $result = [PSCustomObject]@{
        checkedAt      = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
        hasUpdate      = $check.HasUpdate
        latestSha      = $check.LatestSha
        storedSha      = $check.StoredSha
        commitDate     = $check.CommitDate
        commitMessage  = $check.CommitMessage
        autoSynced     = ($AutoSync -and $check.HasUpdate)
    }
    $dir = Split-Path -Parent $OutputPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $result | ConvertTo-Json -Depth 5 | Set-Content -Path $OutputPath -Encoding UTF8
    if (-not $Quiet) { Write-Host "`n[OK] Results exported to $OutputPath" -ForegroundColor Green }
}

# Exit codes: 0 = up-to-date, 1 = error, 100 = update available
if ($check.Error) { exit 1 }
if ($check.HasUpdate) { exit 100 }
exit 0
