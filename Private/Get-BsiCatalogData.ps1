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

    # Record the latest commit SHA from GitHub API for monitoring
    try {
        $updateCheck = Test-BsiCatalogUpdate -MappingPath $MappingPath -ErrorAction SilentlyContinue
        if ($updateCheck -and $updateCheck.LatestSha) {
            $mapping.catalogCommitSha = $updateCheck.LatestSha
            Write-Verbose "[Catalog] Recorded commit SHA: $($updateCheck.LatestSha.Substring(0,12))"
        }
    } catch {
        Write-Verbose "[Catalog] Could not record commit SHA (non-critical): $_"
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($MappingPath, ($mapping | ConvertTo-Json -Depth 10), $utf8NoBom)
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
        Extracts all controls AND group nodes from an OSCAL resolved catalog recursively.
    .DESCRIPTION
        In the resolved catalog format (Grundschutz++-resolved_catalog.json),
        controls are nested under groups → sub-groups. Some BSI mapping entries
        reference group-level IDs (e.g., BER.2, DET.3, NOT.4) that contain
        sub-controls rather than being controls themselves. This function
        collects both leaf controls AND intermediate group nodes so that
        Resolve-BsiOrphans can match against both levels.
    .PARAMETER Catalog
        Parsed OSCAL catalog object.
    .OUTPUTS
        Array of control and group objects (each has at minimum an 'id' property).
    #>
    param($Catalog)

    $results = [System.Collections.ArrayList]::new()
    if (-not $Catalog) { return $results }

    if ($Catalog.catalog) { $Catalog = $Catalog.catalog }

    if ($Catalog.controls) {
        foreach ($c in $Catalog.controls) { $null = $results.Add($c) }
    }

    function Add-ControlsRecursive {
        param($Node)
        # Collect control nodes (leaf-level)
        if ($Node.controls) {
            foreach ($c in $Node.controls) { $null = $results.Add($c) }
        }
        # Collect group/container nodes (those with id but no class).
        # In OSCAL: controls have id+class, groups have id+title (no class).
        # Leaf groups (BER.2, DET.3, NOT.4) have controls but no sub-groups.
        # Container groups (BER, ARCH) have sub-groups.
        # Both types are valid mapping targets and must be collected.
        if ($Node.id -and -not $Node.class) {
            $null = $results.Add($Node)
        }
        # Recurse into sub-groups
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
    return $results
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

function Test-BsiCatalogUpdate {
    <#
    .SYNOPSIS
        Checks the BSI GitHub repository for catalog updates by comparing
        the latest commit SHA with the locally stored reference.
    .DESCRIPTION
        Uses the GitHub API to fetch the latest commit for the resolved
        catalog file. Compares against the stored catalogCommitSha in
        the mapping file. Returns a result object indicating whether an
        update is available.
    .PARAMETER MappingPath
        Path to the bsi-azure-mapping.json file.
    .OUTPUTS
        PSCustomObject with HasUpdate, LatestSha, StoredSha, CommitDate,
        CommitMessage, ApiUrl properties.
    .EXAMPLE
        $check = Test-BsiCatalogUpdate -MappingPath ./Data/bsi-azure-mapping.json
        if ($check.HasUpdate) { Sync-BsiCatalog ... }
    #>
    param(
        [Parameter(Mandatory)][string]$MappingPath
    )

    if (-not (Test-Path -LiteralPath $MappingPath)) {
        throw "Mapping file not found: $MappingPath"
    }
    $mapping = Get-Content -Raw -Path $MappingPath | ConvertFrom-Json

    # Build GitHub API URL: commits for the catalog file path
    $catalogPath = 'control_layer/Grundschutz%2B%2B/Grundschutz%2B%2B-resolved_catalog.json'
    $repoOwner = 'BSI-Bund'
    $repoName = 'Stand-der-Technik-Bibliothek'
    $apiUrl = "https://api.github.com/repos/$repoOwner/$repoName/commits?path=$catalogPath&per_page=1"

    Write-Verbose "[Catalog-Monitor] Checking: $apiUrl"

    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add('User-Agent', 'BSI.AzCompliance/3.0.0')
        $wc.Headers.Add('Accept', 'application/vnd.github.v3+json')
        $wc.Encoding = [System.Text.Encoding]::UTF8
        $response = $wc.DownloadString($apiUrl)
        $wc.Dispose()

        $commits = $response | ConvertFrom-Json
        if (-not $commits -or $commits.Count -eq 0) {
            Write-Warning "[Catalog-Monitor] No commits found for catalog file"
            return [PSCustomObject]@{
                HasUpdate      = $false
                LatestSha      = ''
                StoredSha      = ''
                CommitDate     = ''
                CommitMessage  = ''
                ApiUrl         = $apiUrl
                Error          = 'No commits returned from GitHub API'
            }
        }

        $latestCommit = if ($commits -is [array]) { $commits[0] } else { $commits }
        $latestSha = $latestCommit.sha
        $commitDate = $latestCommit.commit.author.date
        $commitMsg = ($latestCommit.commit.message -split "`n")[0]

        $storedSha = if ($mapping.catalogCommitSha) { $mapping.catalogCommitSha.Trim() } else { '' }
        if (-not $storedSha) {
            $storedSha = '(none)'
        }

        $hasUpdate = ($latestSha.Trim() -ne $storedSha.Trim())

        Write-Verbose "[Catalog-Monitor] Latest SHA: $($latestSha.Substring(0,12))"
        Write-Verbose "[Catalog-Monitor] Stored SHA: $(if ($storedSha -ne '(none)') { $storedSha.Substring(0, [Math]::Min(12, $storedSha.Length)) } else { $storedSha })"
        Write-Verbose "[Catalog-Monitor] HasUpdate: $hasUpdate"

        return [PSCustomObject]@{
            HasUpdate      = $hasUpdate
            LatestSha      = $latestSha
            StoredSha      = $storedSha
            CommitDate     = $commitDate
            CommitMessage  = $commitMsg
            ApiUrl         = $apiUrl
            Error          = ''
        }
    } catch {
        Write-Warning "[Catalog-Monitor] GitHub API call failed: $_"
        return [PSCustomObject]@{
            HasUpdate      = $false
            LatestSha      = ''
            StoredSha      = ''
            CommitDate     = ''
            CommitMessage  = ''
            ApiUrl         = $apiUrl
            Error          = $_.Exception.Message
        }
    }
}

function Update-BsiCatalogSha {
    <#
    .SYNOPSIS
        Updates the catalogCommitSha in the mapping file after a successful sync.
    .PARAMETER MappingPath
        Path to the bsi-azure-mapping.json file.
    .PARAMETER CommitSha
        The new commit SHA to store.
    #>
    param(
        [Parameter(Mandatory)][string]$MappingPath,
        [Parameter(Mandatory)][string]$CommitSha
    )

    if (-not (Test-Path -LiteralPath $MappingPath)) {
        throw "Mapping file not found: $MappingPath"
    }
    $mapping = Get-Content -Raw -Path $MappingPath | ConvertFrom-Json
    $mapping.catalogCommitSha = $CommitSha
    $mapping.lastSynced = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    $mapping | ConvertTo-Json -Depth 10 | Set-Content -Path $MappingPath -Encoding UTF8
    Write-Verbose "[Catalog-Monitor] Updated catalogCommitSha to $($CommitSha.Substring(0,12))"
}
