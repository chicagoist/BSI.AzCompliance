# BSI.AzCompliance — BSI IT-Grundschutz++ Compliance Validator for Azure

[![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/version-3.0.0-green.svg)]()

**Self-contained PowerShell module** for validating Azure 3-tier deployments against BSI IT-Grundschutz++ (German Federal Office for Information Security) controls.

Maps BSI OSCAL catalog controls to Azure CLI checks with local script analysis and remote infrastructure validation, producing SARIF, JUnit XML, JSON, and HTML reports for CI/CD integration.

## Quick Start

```powershell
# 1. Import the module
Import-Module .\BSI.AzCompliance.psd1

# 2a. Local mode: validate a deployment script
Invoke-BsiCompliance -Local -ScriptPath .\create_3-tier-webapp.ps1

# 2b. Remote mode: validate deployed Azure infrastructure
Invoke-BsiCompliance -Remote -ConfigPath .\config.ps1

# 3. Full compliance report (all formats)
Invoke-BsiCompliance -Remote -ConfigPath .\config.ps1 `
    -OutputFormat Sarif,Html,Json,Console -OutputPath .\reports\compliance_report

# 4. Sync BSI catalog (download latest OSCAL data)
Invoke-BsiCompliance -Sync
```

Or use the `ibs` alias:
```powershell
ibs -Local -ScriptPath .\deploy.ps1
```

## Features

- **Dual-mode validation**: Local (static regex analysis of scripts) and Remote (live Azure CLI queries)
- **18 BSI controls** across 6 categories: Network, VM, Identity, Backup, Monitoring, Policy
- **5 output formats**: Console, JSON, SARIF 2.1.0, JUnit XML, HTML dashboard
- **Self-contained**: Embedded BSI OSCAL mapping data — no external file dependencies
- **CI/CD ready**: GitHub Actions, Azure DevOps, Jenkins compatible via JUnit/SARIF
- **Azure CLI wrapper**: built-in retry, caching, timeout, rate-limit handling
- **Graceful degradation**: network failures produce warnings, not crashes

## Architecture

```
Internet -> VM-web (Nginx :80) -> VM-app (Flask :5000) -> VM-db (MariaDB :3306)
```

### BSI Controls Validated

| Control | Category | Description | Severity |
|---------|----------|-------------|----------|
| ARCH.5.2 | Network | Deny SSH/RDP from Internet | Critical |
| ARCH.2.1 | Network | Hub-Spoke VNet with isolated subnets | High |
| ARCH.5.1 | Network | No public IPs on backend VMs | Critical |
| ARCH.2.3 | Network | VNet Peering Connected | High |
| ARCH.5.3 | Network | Azure Bastion for secure SSH | High |
| DER.1 | Network | NAT Gateway for outbound traffic | Medium |
| KONF.11.8 | VM | Disk encryption at-rest | High |
| CON.1 | VM | TLS 1.2 minimum on Storage | High |
| APP.4.2 | VM | VM image patch level | Medium |
| BER.2 | Identity | SystemAssigned Managed Identity | Medium |
| BER.6 | Identity | Key Vault with soft-delete/purge | Critical |
| BER.4 | Identity | RBAC roles for Key Vault | High |
| NOT.4 | Backup | Automated VM backups | High |
| INF.1 | Backup | Recovery Services Vault | Medium |
| DET.3 | Monitoring | NSG Flow Logs with retention | Medium |
| DET.3.1 | Monitoring | Network Watcher in region | Medium |
| OPS.1.1.4 | Monitoring | Diagnostic settings on Key Vault | Medium |
| KONF.2.6 | Policy | Azure Policy assignments | Medium |

## Requirements

- **PowerShell 5.1+** or **PowerShell 7**
- **Azure CLI** (`az`) — installed and authenticated (`az login`)
- **Active Azure subscription** with deployed 3-tier infrastructure (Remote mode)
- **config.ps1** file defining Azure resource names (see [CONFIG.md](docs/CONFIG.md))

## Project Structure

```
BSI-AzCompliance/
├── BSI.AzCompliance.psd1          # Module manifest
├── BSI.AzCompliance.psm1          # Module loader
├── Classes/ComplianceResult.ps1  # Core data model
├── Enums/Severity.ps1            # Type definitions
├── Private/                       # Internal functions
│   ├── Get-AzCliResponse.ps1      # Azure CLI wrapper (retry/cache/timeout)
│   ├── Get-BsiCatalogData.ps1     # OSCAL catalog management
│   ├── Get-BsiConfigValidation.ps1 # Config file validation
│   └── Resolve-BsiMapping.ps1     # Mapping management
├── Public/                        # Public cmdlets
│   ├── Invoke-BsiCompliance.ps1   # Main entry point
│   ├── Get-BsiControlStatus.ps1   # Query results by control
│   └── New-BsiComplianceReport.ps1 # Report generation
├── Checks/                        # 17 individual check functions
│   ├── Network/                   # ARCH.5.2, ARCH.2.1, ARCH.5.1, etc.
│   ├── VM/                        # KONF.11.8, CON.1, APP.4.2
│   ├── Identity/                  # BER.2, BER.6, BER.4
│   ├── Backup/                    # NOT.4, INF.1
│   ├── Monitoring/                # DET.3, DET.3.1, OPS.1.1.4
│   └── Policy/                    # KONF.2.6
├── Exporters/                     # Output formatters
│   ├── Export-Console.ps1
│   ├── Export-Json.ps1
│   ├── Export-Sarif.ps1
│   ├── Export-JUnitXml.ps1
│   └── Export-Html.ps1
├── Data/                          # Self-contained BSI data
│   ├── bsi-azure-mapping.json     # Embedded control mappings
│   └── cache/                     # Downloaded OSCAL catalog cache
├── Scripts/                       # CLI entry points
│   └── Invoke-BsiCompliance.ps1
├── Tests/                         # Pester tests
├── docs/                          # Documentation
├── .github/workflows/             # CI/CD pipelines
├── LICENSE
└── README.md
```

## CI/CD Integration

### GitHub Actions

```yaml
- name: BSI Compliance Check
  shell: pwsh
  run: |
    Import-Module .\BSI.AzCompliance.psd1 -Force
    Invoke-BsiCompliance -Local -ScriptPath .\deploy.ps1 -OutputFormat Console,Sarif -OutputPath .\reports\bsi

- name: Upload SARIF
  uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: .\reports\bsi.sarif
```

### Azure DevOps

```yaml
- task: PowerShell@2
  inputs:
    filePath: 'Scripts/Invoke-BsiCompliance.ps1'
    arguments: '-Remote -ConfigPath $(System.DefaultWorkingDirectory)/config.ps1 -OutputFormat JUnitXml -OutputPath $(Common.TestResultsDirectory)/bsi'

- task: PublishTestResults@2
  inputs:
    testResultsFormat: 'JUnit'
    testResultsFiles: '**/bsi.junit.xml'
```

## Documentation

- [Architecture Design](docs/BSI-AzCompliance-Design.md) — Full design document
- [Configuration](docs/CONFIG.md) — config.ps1 reference
- [Changelog](CHANGELOG.md)

## License

MIT License — see [LICENSE](LICENSE)

---

**Author**: Valerii Dundukov  
**Project**: [github.com/JendrixBln/BSI-AzCompliance](https://github.com/JendrixBln/BSI-AzCompliance)
