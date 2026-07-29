# Changelog

## [3.1.0] - 2026-07-29

### Added

- **Catalog monitoring**: `Test-BsiCatalogUpdate` checks GitHub API for new commits; `Watch-BsiCatalog.ps1` standalone script with `-AutoSync`; `catalog-monitor` CI job auto-syncs and creates Issues on catalog updates
- **`catalogCommitSha` field**: stored in `bsi-azure-mapping.json`, auto-updated by `Sync-BsiCatalog` after each successful download
- **`source: azure-extension`**: 6 Azure-specific custom control IDs (ARCH.5.3, CON.1, OPS.1.1.4, DER.1, INF.1, APP.4.2) marked with `source` field in mapping — replaces hardcoded prefix list in `Resolve-BsiOrphans` (data-driven approach)
- **PS 5.1 CI matrix**: GitHub Actions `local-validation` now runs on both `ubuntu-latest`/pwsh/PS7 and `windows-latest`/powershell/PS5.1 with `fail-fast: false`
- **Pester: 29/29 tests passing**: 5 previously skipped tests fixed via `$global:moduleRoot` resolution with multi-fallback chain (`$PSScriptRoot` → walk-up → `BUILD_SOURCESDIRECTORY`/`GITHUB_WORKSPACE` → last resort)
- **Pester mocks for `az` CLI**: `Test-AzCliReady` test now mocks `Get-Command` and `Get-AzCliResponse` with `-ModuleName BSI.AzCompliance`

### Changed
- **Catalog URL**: updated to `Grundschutz++-resolved_catalog.json` from `control_layer/Grundschutz%2B%2B/` (new BSI OSCAL resolved format)
- **`Get-BsiCatalogControls`**: adapted to parse the new resolved-catalog structure — collects both control-level and group-level IDs (e.g., `BER.2`, `DET.3`, `NOT.4`)
- **`Resolve-BsiOrphans`**: replaced hardcoded prefix list (`CON.`, `OPS.`, `DER.`, `INF.`, `APP.`) and `ARCH.5.3` check with data-driven `$_.source -eq 'azure-extension'` filter
- **CI workflow**: `local-validation` now uses `strategy.matrix` (PS7 + PS5.1) with `issues: write` permission for `catalog-monitor`
- **`Sync-BsiCatalog`**: now calls `Test-BsiCatalogUpdate` after each successful download and records the latest commit SHA in mapping
- **Exported functions**: `Test-BsiCatalogExists`, `Get-BsiCatalog`, `Test-BsiCatalogUpdate` added to `FunctionsToExport` for Pester testability

### Fixed
- **PS 5.1 `Join-Path` compatibility**: `BSI.AzCompliance.psm1` — 3-argument `Join-Path` replaced with nested 2-argument calls (`Join-Path (Join-Path ...) ...`)
- **Em dash → ASCII**: Unicode `—` (U+2014) replaced with `--` in `Test-AzureBackup.ps1`, `Test-NoPublicIp.ps1`, `Export-Sarif.ps1` (PS 5.1 console encoding compatibility)
- **CI console output**: removed `-ForegroundColor` from `Write-Host` calls in CI workflow steps (colors not rendered in CI, caused noise on PS 5.1)
- **Pester path resolution**: 5 skipped tests (`Mapping functions` + 4× `Check manifest`) now pass — `$global:moduleRoot` bypasses Pester v6 scope isolation; CI env vars (`BUILD_SOURCESDIRECTORY`, `GITHUB_WORKSPACE`) provide fallback resolution

## [3.0.0] - 2026-07-25

### Added
- **Self-contained architecture**: all BSI mapping data embedded in `Data/` directory
- **Module data auto-creation**: `Data/cache/` created automatically on import
- **CLI entry point**: `Scripts/Invoke-BsiCompliance.ps1` with `-Help` support
- **`ibs` alias**: shorthand for `Invoke-BsiCompliance`
- **Comprehensive documentation**: Architecture Design, CONFIG reference, README
- **GitHub Actions CI/CD**: dual-job pipeline (Local + Remote) with SARIF upload
- **MIT LICENSE**

### Changed
- **BREAKING**: Path resolution now uses `$PSScriptRoot` (no longer depends on `.opencode/skills/` directory)
- Module version bumped from 2.0.0 to 3.0.0
- Updated `ProjectUri` to `github.com/chicagoist/BSI-AzCompliance`
- Default mapping path: `$PSScriptRoot/Data/bsi-azure-mapping.json` (was: `.opencode/skills/...`)
- Default cache path: `$PSScriptRoot/Data/cache/` (was: `.opencode/skills/.../cache/`)

### Fixed
- Dead path references to `.opencode/skills/bsi-oscal-azure-compliance/`
- Duplicate function implementations in `scripts/modules/` removed
- Module now works as standalone directory anywhere in filesystem
- `Invoke-BsiCompliance` path resolution no longer walks up 3 directory levels

### Removed
- `Update-BsiSkillReadme` call from `-Sync` flow (no longer needed)
- `.opencode/` dependency completely eliminated

## [2.0.0] - 2026-06

### Added
- PowerShell module structure (`BSI.AzCompliance.psd1`/`.psm1`)
- `ComplianceResult` class with SARIF/JUnit conversion
- `Get-AzCliResponse` wrapper with retry, cache, timeout
- `_CheckManifest.json` check registry
- 17 individual check functions across 6 categories
- 5 export formats: Console, JSON, SARIF 2.1.0, JUnit XML, HTML
- Module-based `Invoke-BsiCompliance` replacing Gen 1 monolithic script

## [1.0.0] - 2026-05

### Added
- Initial Gen 1 implementation: monolithic `Invoke-BsiValidator.ps1`
- Basic local/remote validation modes
- BSI OSCAL catalog sync from GitHub
- Console-only output
