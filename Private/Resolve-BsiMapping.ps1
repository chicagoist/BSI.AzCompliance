#Requires -Version 5.1
<#
.SYNOPSIS
    BSI mapping management — load, query, validate, update.
.DESCRIPTION
    Loads the bsi-azure-mapping.json, resolves controls against catalog,
    detects orphans, and provides lookup functions.
#>

function Get-BsiMapping {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Mapping file not found: $Path"
    }
    return Get-Content -Raw -Path $Path | ConvertFrom-Json
}

function Get-BsiMappingControls {
    param([Parameter(Mandatory)]$Mapping)
    return $Mapping.mappings
}

function Get-BsiMappingControlById {
    param(
        [Parameter(Mandatory)]$Mapping,
        [Parameter(Mandatory)][string]$ControlId
    )
    return $Mapping.mappings | Where-Object { $_.controlId -eq $ControlId } | Select-Object -First 1
}

function Resolve-BsiOrphans {
    <#
    .SYNOPSIS
        Finds mapping entries whose control IDs are not in the catalog.
    .DESCRIPTION
        Compares mapping control IDs against both control-level and group-level
        IDs from the resolved catalog. Skips entries marked with
        source='azure-extension' (Azure-specific custom checks that don't
        correspond to any BSI catalog entry).
    .OUTPUTS
        Array of orphaned control IDs.
    #>
    param(
        [Parameter(Mandatory)]$Mapping,
        [Parameter(Mandatory)]$CatalogControls
    )

    # Catalog now contains both control and group nodes (see Get-BsiCatalogControls)
    $catalogIds = $CatalogControls | ForEach-Object { $_.id }

    return @($Mapping.mappings | Where-Object {
        $cid = $_.controlId

        # Data-driven: skip entries explicitly marked as Azure extensions
        if ($_.source -eq 'azure-extension') { return $false }

        # True orphan: not found in catalog and not a known extension
        return ($catalogIds -notcontains $cid)
    } | ForEach-Object { $_.controlId })
}

function Resolve-BsiUncoveredControls {
    <#
    .SYNOPSIS
        Finds catalog controls not covered by the mapping.
    .OUTPUTS
        Array of uncovered control IDs.
    #>
    param(
        [Parameter(Mandatory)]$Mapping,
        [Parameter(Mandatory)]$CatalogControls
    )

    $mappedIds = $Mapping.mappings | ForEach-Object { $_.controlId }
    $catalogIds = $CatalogControls | ForEach-Object { $_.id }
    return @($catalogIds | Where-Object { $mappedIds -notcontains $_ })
}

function Update-BsiMappingTimestamp {
    param([Parameter(Mandatory)][string]$Path)

    $mapping = Get-BsiMapping -Path $Path
    $mapping.lastSynced = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, ($mapping | ConvertTo-Json -Depth 10), $utf8NoBom)
}

function Update-BsiSkillReadme {
    param(
        [Parameter(Mandatory)]$Mapping,
        [Parameter(Mandatory)][string]$OutputPath
    )

    $lines = [System.Collections.ArrayList]::new()
    $null = $lines.Add("---")
    $null = $lines.Add("name: 'bsi-oscal-azure-compliance'")
    $null = $lines.Add("description: 'BSI IT-Grundschutz++ OSCAL compliance validator for Azure 3-tier deployments.'")
    $null = $lines.Add("metadata:")
    $null = $lines.Add("  generated_at: $(Get-Date -Format 'yyyy-MM-dd')")
    $null = $lines.Add("  generator: 'BSI.AzCompliance'")
    $null = $lines.Add("  source_repo: '$($Mapping.repository)'")
    $null = $lines.Add("  lastSynced: '$($Mapping.lastSynced)'")
    $null = $lines.Add("---")
    $null = $lines.Add("")
    $null = $lines.Add("# BSI OSCAL Azure Compliance Skill")
    $null = $lines.Add("")
    $null = $lines.Add("## Mapped Controls")
    $null = $lines.Add("")

    foreach ($entry in $Mapping.mappings) {
        $null = $lines.Add("- **$($entry.controlId)**: $($entry.title) [$($entry.category)]")
    }

    $null = $lines.Add("")
    $null = $lines.Add("## Usage")
    $null = $lines.Add('```powershell')
    $null = $lines.Add('Import-Module ./modules/BSI.AzCompliance')
    $null = $lines.Add('Invoke-BsiCompliance -Local -ScriptPath .\create_3-tier-webapp_VM_v2.ps1')
    $null = $lines.Add('Invoke-BsiCompliance -Remote -ConfigPath .\config.ps1')
    $null = $lines.Add('```')
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($OutputPath, ($lines -join "`r`n"), $utf8NoBom)
    Write-Verbose "[Mapping] Updated skill readme: $OutputPath"
}
