# Changelog

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
- Updated `ProjectUri` to `github.com/JendrixBln/BSI-AzCompliance`
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
