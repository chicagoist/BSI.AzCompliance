#Requires -Version 5.1
<#
.SYNOPSIS
    BSI IT-Grundschutz++ Compliance Validator CLI Entry Point.
.DESCRIPTION
    Self-contained PowerShell CLI wrapper for the BSI.AzCompliance module.
    Automatically imports the module from the same directory tree and
    forwards all parameters to Invoke-BsiCompliance.

    Usage:
        .\Invoke-BsiCompliance.ps1 -Local -ScriptPath .\deploy.ps1
        .\Invoke-BsiCompliance.ps1 -Remote -ConfigPath .\config.ps1
        .\Invoke-BsiCompliance.ps1 -Remote -ConfigPath .\config.ps1 -OutputFormat Sarif,Html -OutputPath .\reports\compliance
        .\Invoke-BsiCompliance.ps1 -Sync
        .\Invoke-BsiCompliance.ps1 -Help

.NOTES
    Version: 3.0.0
    Author: Valerii Dundukov
    License: MIT
#>

[CmdletBinding()]
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

    [string]$OutputFormat = 'Console',
    [string]$OutputPath = '',

    [string[]]$NsgNames = @('NSG-Web', 'NSG-App', 'NSG-DB'),
    [string[]]$DenyPorts = @('22', '3389'),

    [switch]$Help
)

# --- Display help ---
if ($Help) {
    @"

BSI IT-Grundschutz++ Compliance Validator v3.0.0
=================================================

USAGE:
  .\Invoke-BsiCompliance.ps1 -Local -ScriptPath <path>
      Validate a deployment script via static regex analysis.

  .\Invoke-BsiCompliance.ps1 -Remote -ConfigPath <path> [OPTIONS]
      Validate deployed Azure infrastructure via Azure CLI.

  .\Invoke-BsiCompliance.ps1 -Sync
      Download the latest BSI OSCAL catalog.

OPTIONS:
  -OutputFormat  Console, Json, Sarif, JUnitXml, Html (comma-separated)
  -OutputPath    Base path for output files (suffix auto-appended per format)
  -NsgNames      NSG names to check (default: NSG-Web, NSG-App, NSG-DB)
  -DenyPorts     Ports to verify Deny rules for (default: 22, 3389)
  -SubscriptionId Optional Azure subscription ID

EXAMPLES:
  # Local: validate a deployment script
  .\Invoke-BsiCompliance.ps1 -Local -ScriptPath .\create_3-tier-webapp.ps1

  # Remote: validate deployed infrastructure with all output formats
  .\Invoke-BsiCompliance.ps1 -Remote -ConfigPath .\config.ps1 `
      -OutputFormat Sarif,Html,Json,Console -OutputPath .\reports\compliance

  # Sync catalog and validate
  .\Invoke-BsiCompliance.ps1 -Remote -ConfigPath .\config.ps1 -Sync

REQUIREMENTS:
  - PowerShell 5.1+ / PowerShell 7
  - Azure CLI (az) installed and logged in
  - Valid config.ps1 file for Remote mode (see docs/CONFIG.md)

"@
    exit 0
}

# --- Resolve module path relative to this script ---
$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptDir) { $scriptDir = '.' }
$moduleRoot = Join-Path $scriptDir '..'
$modulePsd1 = Join-Path $moduleRoot 'BSI.AzCompliance.psd1'

if (-not (Test-Path -LiteralPath $modulePsd1)) {
    Write-Error "BSI.AzCompliance module not found at: $modulePsd1"
    Write-Host "Ensure this script is in the Scripts/ directory of the BSI-AzCompliance project."
    exit 1
}
$moduleRoot = Resolve-Path $moduleRoot

# --- Import module ---
Import-Module $modulePsd1 -Force

# --- Build parameter hashtable ---
$params = @{}
if ($Local)            { $params['Local'] = $true }
if ($Remote)           { $params['Remote'] = $true }
if ($Sync)             { $params['Sync'] = $true }
if ($ScriptPath)       { $params['ScriptPath'] = $ScriptPath }
if ($ConfigPath)       { $params['ConfigPath'] = $ConfigPath }
if ($SubscriptionId)   { $params['SubscriptionId'] = $SubscriptionId }
if ($OutputFormat)     { $params['OutputFormat'] = $OutputFormat }
if ($OutputPath)       { $params['OutputPath'] = $OutputPath }
if ($NsgNames)         { $params['NsgNames'] = $NsgNames }
if ($DenyPorts)        { $params['DenyPorts'] = $DenyPorts }

# --- Execute ---
try {
    $exitCode = Invoke-BsiCompliance @params
    exit $exitCode
} catch {
    Write-Error "Compliance validation failed: $_"
    exit 255
}
