#Requires -Version 5.1
<#
.SYNOPSIS
    Validates and returns configuration settings from config.ps1 for Remote mode.
.DESCRIPTION
    Loads the configuration file and validates that required variables are present.
    Returns a hashtable of configuration settings for use in compliance checks.
.PARAMETER ConfigPath
    Path to the configuration file (config.ps1).
.OUTPUTS
    Hashtable containing configuration settings.
#>
function Get-BsiConfigValidation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigPath
    )

    # Resolve the config path
    $configFullPath = Resolve-Path -Path $ConfigPath -ErrorAction SilentlyContinue
    if (-not $configFullPath -or -not (Test-Path -LiteralPath $configFullPath)) {
        throw "Config file not found: $ConfigPath"
    }

    # Load the configuration
    try {
        . $configFullPath
    }
    catch {
        throw "Failed to load configuration file '$configFullPath': $_"
    }

    # Define required variables for Remote mode
    $requiredVars = @(
        'rgName',
        'location',
        'vnetSpoke1Name',
        'subnetWeb', 'subnetWebAddress',
        'subnetApp', 'subnetAppAddress',
        'subnetDb', 'subnetDBAddress',
        'storageaccountName',
        'keyVaultName',
        'recoveryServicesVaultName'
    )

    $missing = @()
    foreach ($var in $requiredVars) {
        if (-not (Get-Variable -Name $var -Scope Global -ErrorAction SilentlyContinue)) {
            $missing += $var
        }
    }

    if ($missing.Count -gt 0) {
        throw "Missing required configuration variables: $($missing -join ', ')"
    }

    # Return configuration as hashtable
    return @{
        rgName = $rgName
        location = $location
        vnetSpoke1Name = $vnetSpoke1Name
        subnetWeb = $subnetWeb
        subnetWebAddress = $subnetWebAddress
        subnetApp = $subnetApp
        subnetAppAddress = $subnetAppAddress
        subnetDb = $subnetDb
        subnetDBAddress = $subnetDBAddress
        storageaccountName = $storageaccountName
        keyVaultName = $keyVaultName
        secretName = $secretName   # may be $null
        recoveryServicesVaultName = $recoveryServicesVaultName
        vnetHubName = $vnetHubName   # may be $null
        bastionHostName = $bastionHostName   # may be $null
    }
}