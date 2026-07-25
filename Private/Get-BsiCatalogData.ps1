#Requires -Version 5.1
<#
.SYNOPSIS
    BSI OSCAL catalog management — download, cache, parse.
.DESCRIPTION
    Handles the BSI Grundschutz++ OSCAL catalog lifecycle:
    downloading from GitHub, caching locally, extracting controls.
#>

function Sync-BsiCatalog {
    <#
    .SYNOPSIS
        Downloads the BSI OSCAL catalog from GitHub.
    .PARAMETER OutPath
        Path to write the catalog JSON.
    .PARAMETER MappingPath
        Path to mapping file containing catalogUrl.
    #>
    param(
        [Parameter(Mandatory)][string]$OutPath,
        [Parameter(Mandatory)][string]$MappingPath
    )

    if (-not (Test-Path -LiteralPath $MappingPath)) {
        throw "Mapping file not found: $MappingPath"
    }
    $mapping = Get-Content -Raw -Path $MappingPath | ConvertFrom-Json
    $url = $mapping.catalogUrl
    if (-not $url) {
        throw "catalogUrl is not defined in $MappingPath"
    }

    $urls = @($url)
    if ($mapping.catalogFallbackUrls) {
        $urls += @($mapping.catalogFallbackUrls)
    }

    $downloaded = $false
    foreach ($u in $urls) {
        Write-Verbose "[Catalog] Trying URL: $u"
        try {
            $cacheDir = Split-Path -Parent $OutPath
            if (-not (Test-Path -LiteralPath $cacheDir)) {
                New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
            }

            $wc = New-Object System.Net.WebClient
            $wc.Encoding = [System.Text.Encoding]::UTF8
            $catalogJson = $wc.DownloadString($u)
            $wc.Dispose()

            if (-not ($catalogJson -match '^\s*[\{\[]')) {
                throw "Downloaded content does not look like JSON."
            }
            $null = $catalogJson | ConvertFrom-Json
            [System.IO.File]::WriteAllText($OutPath, $catalogJson, [System.Text.UTF8Encoding]::new($false))
            $downloaded = $true
            Write-Verbose "[Catalog] Cached to $OutPath"
            break
        } catch {
            Write-Warning "Failed to download catalog from $u : $_"
        }
    }

    if (-not $downloaded) {
        throw "Failed to download BSI catalog from any configured URL."
    }

    $mapping.lastSynced = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    $mapping | ConvertTo-Json -Depth 10 | Set-Content -Path $MappingPath -Encoding UTF8
}

function Get-BsiCatalog {
    <#
    .SYNOPSIS
        Loads the cached BSI OSCAL catalog.
    .PARAMETER Path
        Path to catalog JSON.
    .OUTPUTS
        Parsed catalog object or $null.
    #>
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    return Get-Content -Raw -Path $Path | ConvertFrom-Json
}

function Get-BsiCatalogControls {
    <#
    .SYNOPSIS
        Extracts all controls from an OSCAL catalog recursively.
    .PARAMETER Catalog
        Parsed OSCAL catalog object.
    .OUTPUTS
        Array of control objects.
    #>
    param($Catalog)

    $controls = [System.Collections.ArrayList]::new()
    if (-not $Catalog) { return $controls }

    if ($Catalog.catalog) { $Catalog = $Catalog.catalog }

    if ($Catalog.controls) {
        foreach ($c in $Catalog.controls) { $null = $controls.Add($c) }
    }

    function Add-ControlsRecursive {
        param($Node)
        if ($Node.controls) {
            foreach ($c in $Node.controls) { $null = $controls.Add($c) }
        }
        if ($Node.groups) {
            foreach ($group in $Node.groups) {
                Add-ControlsRecursive -Node $group
            }
        }
    }

    if ($Catalog.groups) {
        foreach ($group in $Catalog.groups) {
            Add-ControlsRecursive -Node $group
        }
    }
    return $controls
}

function Test-BsiCatalogExists {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        $json = Get-Content -Raw -Path $Path | ConvertFrom-Json
        return $null -ne $json
    } catch {
        return $false
    }
}
