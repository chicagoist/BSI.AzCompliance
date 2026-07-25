# BSI.AzCompliance Architecture Design Document

**Version:** 3.0.0  
**Author:** Valerii Dundukov  
**Date:** 2026-07-25  
**License:** MIT

---

## 1. Overview

BSI.AzCompliance is a **self-contained PowerShell module** that validates Azure 3-tier web application deployments against BSI IT-Grundschutz++ controls. It bridges the gap between the German BSI OSCAL catalog and practical Azure infrastructure validation through two complementary modes: static script analysis (Local) and live resource inspection (Remote).

### 1.1 Design Goals

| Goal | Implementation |
|------|---------------|
| **Self-sufficiency** | Embedded BSI mapping data in `Data/` directory; no external file dependencies |
| **CI/CD native** | SARIF 2.1.0 and JUnit XML output for GitHub Code Scanning, Azure DevOps, Jenkins |
| **Resilience** | Azure CLI wrapper with exponential backoff, response caching, timeout handling |
| **Extensibility** | Modular check architecture — add new BSI controls by creating a single `.ps1` file |
| **Observability** | Structured logging, evidence collection, remediation guidance in all outputs |
| **Backward compatibility** | Gen 1 `validate-bsi-compliance.ps1` wrapper preserved |

---

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    CLI Entry Point                        │
│            Scripts/Invoke-BsiCompliance.ps1             │
└───────────────────────┬─────────────────────────────────┘
                        │ Import-Module
┌───────────────────────▼─────────────────────────────────┐
│             BSI.AzCompliance Module (psm1)               │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────────┐ │
│  │  Enums   │ │ Classes  │ │ Private  │ │   Public    │ │
│  │Severity  │ │Compl.Res │ │ AzCli    │ │Invoke-Bsi…  │ │
│  │CheckMode │ │          │ │ Catalog  │ │Get-Status   │ │
│  │Format    │ │          │ │ Config   │ │New-Report   │ │
│  │Baseline  │ │          │ │ Mapping  │ │             │ │
│  └──────────┘ └──────────┘ └──────────┘ └────────────┘ │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │                   Checks (17)                       │ │
│  │  Network │ VM │ Identity │ Backup │ Monitor │ Policy│ │
│  └────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────┐ │
│  │         Exporters (Console/JSON/SARIF/JUnit/HTML)   │ │
│  └────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────┐ │
│  │         Data/ (Self-contained BSI data)            │ │
│  │   bsi-azure-mapping.json  │  cache/ (OSCAL)        │ │
│  └────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

### 2.1 Layer Responsibilities

| Layer | Responsibility | Key Files |
|-------|---------------|-----------|
| **CLI Entry** | Parameter parsing, module import, error handling | `Scripts/Invoke-BsiCompliance.ps1` |
| **Public API** | `Invoke-BsiCompliance`, `Get-BsiControlStatus`, `New-BsiComplianceReport` | `Public/*.ps1` |
| **Checks** | Individual BSI control validators (one per control) | `Checks/{Category}/Test-*.ps1` |
| **Exporters** | Format conversion (Console, JSON, SARIF, JUnit, HTML) | `Exporters/Export-*.ps1` |
| **Data** | Embedded BSI mapping + OSCAL catalog cache | `Data/` |
| **Core** | AzCli wrapper, catalog management, mapping, enums/classes | `Private/`, `Enums/`, `Classes/` |

---

## 3. Core Data Model

### 3.1 ComplianceResult Class

```powershell
class ComplianceResult {
    [string]         $ControlId        # BSI control ID (e.g., ARCH.5.2)
    [string]         $ControlTitle     # Human-readable description
    [string]         $Category         # Network, VM, Identity, Backup, Monitoring, Policy
    [BsiCheckMode]   $Mode             # Local or Remote
    [BsiCheckStatus] $Status           # Pass, Fail, Skip, Error
    [BsiSeverity]    $Severity         # Critical, High, Medium, Low, Info
    [BsiBaseline]    $Baseline         # B, C, D
    [string]         $Details          # Detailed check description and findings
    [string]         $Evidence         # Supporting evidence (raw values)
    [string]         $Remediation      # Fix guidance
    [string]         $BsiReference     # BSI document reference (e.g., BSI-G-00549)
    [string]         $CheckFunction    # Name of check function
    [string]         $SourceFile       # File where match was found (Local mode)
    [int]            $LineNumber       # Line number (Local mode)
    [datetime]       $Timestamp        # UTC timestamp
    [hashtable]      $Metadata         # Extensible key-value store
}
```

### 3.2 Enum Types

```powershell
enum BsiSeverity  { Critical=0; High=1; Medium=2; Low=3; Info=4 }
enum BsiCheckMode { Local=0; Remote=1 }
enum BsiCheckStatus { Pass=0; Fail=1; Skip=2; Error=3 }
enum BsiOutputFormat { Console=0; Json=1; Sarif=2; JUnitXml=3; Html=4 }
enum BsiBaseline  { B=0; C=1; D=2 }
```

### 3.3 Global Result Store

Results accumulate in a module-scoped `ArrayList`:

```powershell
$script:BsiResults  # ArrayList of ComplianceResult objects
$script:BsiPassed   # Integer counter
$script:BsiFailed   # Integer counter
$script:BsiSkipped  # Integer counter
```

Functions: `Add-BsiResult`, `Add-BsiResultObject`, `Reset-BsiResults`, `Get-BsiSummary`

---

## 4. Check Architecture

### 4.1 Check Registry

All checks are registered in `Checks/_CheckManifest.json`:

```json
{
    "version": "2.0.0",
    "checks": [
        {
            "id": "ARCH.5.2",
            "function": "Test-NsgDenyInbound",
            "file": "Checks/Network/Test-NsgDenyInbound.ps1",
            "severity": "Critical",
            "baseline": "B",
            "category": "Network",
            "description": "Perimeterschutz - Blockieren direkter...",
            "bsiReference": "BSI-G-00549"
        }
    ]
}
```

### 4.2 Check Function Contract

Every check function MUST:
1. Accept `-ResourceGroup` and `-SubscriptionId` parameters
2. Use `Get-AzCliResponse` for all Azure CLI calls (never call `az` directly)
3. Return `[ComplianceResult[]]` array
4. Handle resource-not-found gracefully (return Error status, don't throw)

### 4.3 Adding a New Check

```powershell
# 1. Create Checks/{Category}/Test-NewControl.ps1
function Test-NewControl {
    param([string]$ResourceGroup, [string]$SubscriptionId = '')
    # ... use Get-AzCliResponse for Azure calls ...
    return @([ComplianceResult]::new(...))
}

# 2. Register in Checks/_CheckManifest.json

# 3. Register in BSI.AzCompliance.psd1 FunctionsToExport

# 4. Add to Data/bsi-azure-mapping.json mappings array

# 5. Add invocation in Public/Invoke-BsiCompliance.ps1 Remote mode section
```

---

## 5. Dual-Mode Validation

### 5.1 Local Mode (Static Analysis)

Local mode performs static regex matching against deployment scripts without requiring Azure access:

```
Invoke-BsiCompliance -Local -ScriptPath .\deploy.ps1
```

**Flow:**
1. Load `Data/bsi-azure-mapping.json`
2. For each mapping entry with `localCheck` defined:
   - Extract regex `patterns` and `mustMatchAtLeast` count
   - Apply each pattern to script content via `[regex]::IsMatch()`
   - Compare matched count against thresholds
3. Record ComplianceResult with `Mode = Local`

**Pattern examples:**
```json
{
    "controlId": "ARCH.5.2",
    "localCheck": {
        "description": "NSG must deny SSH/RDP from Internet",
        "mustMatchAtLeast": 3,
        "patterns": [
            "az network nsg rule create.*--destination-port-ranges 22.*--access Deny",
            "nsg.*deny.*inbound"
        ]
    }
}
```

### 5.2 Remote Mode (Live Inspection)

Remote mode queries live Azure resources via CLI:

```
Invoke-BsiCompliance -Remote -ConfigPath .\config.ps1
```

**Flow:**
1. Dot-source `config.ps1` to load `$rgName`, `$vnetSpoke1Name`, `$keyVaultName`, etc.
2. Verify `az login` status via `Test-AzCliReady`
3. Execute all 17 check functions against live resources
4. Each check uses `Get-AzCliResponse` with:
   - **Retry**: 3 attempts with exponential backoff
   - **Cache**: 60-second TTL to avoid duplicate API calls
   - **Timeout**: 30-second per-call limit
5. Collect and export results

---

## 6. Azure CLI Wrapper (`Get-AzCliResponse`)

### 6.1 Design

Centralizes all `az` calls to provide:
- **Exponential backoff retry** (3 attempts, base 1s → 2s → 4s)
- **Response cache** with configurable TTL (default 60s)
- **Per-call timeout** (default 30s, configurable)
- **Rate-limit detection** (HTTP 429 with Retry-After)
- **Transient error handling** (EAGAIN, ETIMEDOUT, 502, 503, throttling)
- **Graceful degradation** (errors become `[BsiCheckStatus]::Error`, not exceptions)

### 6.2 Cache Key Design

Cache key = serialized arguments array: `"network nsg rule list -g myRG --nsg-name NSG-Web -o json"`

This prevents duplicate identical queries within a validation run.

---

## 7. Data Flow

```
User Input
    │
    ▼
Invoke-BsiCompliance (Public)
    │
    ├── -Local ──► Load mapping ──► Regex scan ──► ComplianceResults
    │
    ├── -Remote ─► Load config ──► AzCliReady check
    │                  │
    │                  ▼
    │           For each check:
    │           Get-AzCliResponse(args) ──► az CLI ──► JSON ──► ComplianceResult
    │                  │
    │                  ├── Cache hit? ──► Return cached
    │                  ├── Timeout?  ──► Kill process, retry
    │                  ├── Error?    ──► Retry or return Error result
    │                  └── Success?  ──► Cache & return
    │
    ├── -Sync ───► Download OSCAL catalog ──► Data/cache/
    │
    ▼
$script:BsiResults (global)
    │
    ▼
Exporters (Console / JSON / SARIF / JUnit / HTML)
    │
    ▼
exit $failedCount
```

---

## 8. Self-Containment Strategy

### 8.1 Problem

The original Gen 2 module (v2.0.0) depended on:
```powershell
$script:DefaultSkillDir = Join-Path $script:ModuleRoot '..' '..' '.opencode' 'skills' 'bsi-oscal-azure-compliance'
```

This hardcoded path only works when the module is nested inside the deployment project.

### 8.2 Solution (v3.0.0)

All paths are now relative to `$PSScriptRoot`:

```powershell
$script:ModuleRoot  = $PSScriptRoot                           # Module directory
$script:ModuleData  = Join-Path $script:ModuleRoot 'Data'     # Embedded data
$script:ModuleCache = Join-Path $script:ModuleData 'cache'    # Catalog cache
$script:DefaultMappingPath = Join-Path $script:ModuleData 'bsi-azure-mapping.json'
```

The module ships with:
- `Data/bsi-azure-mapping.json` — complete BSI control mappings with regex patterns
- `Data/cache/` — directory for downloaded OSCAL catalog (auto-created)

Users only need `config.ps1` for Remote mode (which is user-specific and should NOT be committed).

---

## 9. CI/CD Integration

### 9.1 GitHub Actions (`.github/workflows/bsi-compliance.yml`)

```
on: [pull_request, push, schedule (weekly), workflow_dispatch]

Jobs:
  local-validation:
    - Checkout code
    - Install PowerShell 7.4
    - Import module, run Local validation
    - Upload SARIF to GitHub Code Scanning

  remote-validation (main branch / schedule / manual only):
    - Checkout code
    - Azure Login (OIDC via AZURE_CLIENT_ID secret)
    - Run Remote validation with all output formats
    - Upload SARIF, HTML, JSON as artifacts
```

### 9.2 Required GitHub Secrets

| Secret | Purpose |
|--------|---------|
| `AZURE_CLIENT_ID` | Service principal client ID for OIDC auth |
| `AZURE_TENANT_ID` | Azure tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Target subscription |

### 9.3 Azure DevOps

Use `-OutputFormat JUnitXml` and the `PublishTestResults@2` task to surface BSI compliance as test results in the pipeline UI.

---

## 10. Output Formats

| Format | File Extension | Use Case |
|--------|---------------|----------|
| **Console** | (stdout) | Immediate feedback during development |
| **JSON** | `.json` | Programmatic consumption, API integration |
| **SARIF 2.1.0** | `.sarif` | GitHub Code Scanning, VS Code, SonarQube |
| **JUnit XML** | `.junit.xml` | Azure DevOps, Jenkins, TeamCity test reporting |
| **HTML** | `.html` | Executive dashboard with gauge, category breakdown, remediation |

### 10.1 Severity-to-SARIF Mapping

| BsiSeverity | SARIF Level |
|-------------|-------------|
| Critical, High (Fail/Error) | `error` |
| Medium, Low (Fail/Error) | `warning` |
| Pass, Skip | `none` |

---

## 11. Error Handling Strategy

| Scenario | Behavior |
|----------|----------|
| Azure CLI not installed | `Test-AzCliReady` throws immediately |
| Not logged in (`az login`) | `Test-AzCliReady` throws immediately |
| Resource not found (deleted/misnamed) | Check returns `[BsiCheckStatus]::Error` with details |
| Network timeout | `Get-AzCliResponse` retries 3x, then returns Error |
| Rate limit (HTTP 429) | Detected, delays 2x longer, retries |
| Config file missing variables | `Get-BsiConfigValidation` throws with missing var names |
| Mapping file missing | Clear error: "Run with -Sync first" |
| Script file not found (Local) | Immediate throw with path |
| PowerShell JSON parse error | Caught, returns `$null` with warning |

---

## 12. Future Roadmap

- [ ] **PowerShell Gallery publishing** (`Install-Module BSI.AzCompliance`)
- [ ] **Parallel check execution** (RunSpaces for faster Remote mode)
- [ ] **Terraform/Bicep support** (extend Local mode for IaC templates)
- [ ] **Custom check plugins** (user-defined `.ps1` check files)
- [ ] **Grafana dashboard integration** (JSON metrics export)
- [ ] **BSI Baseline B/C automatic classification**
- [ ] **DISA STIG / NIST 800-53 mapping** (cross-framework)
- [ ] **Remediation auto-fix** (`Invoke-BsiCompliance -AutoFix`)
- [ ] **Docker image** (pre-configured with Azure CLI for CI/CD)

---

## 13. References

- [BSI IT-Grundschutz-Kompendium](https://www.bsi.bund.de/DE/Themen/Unternehmen-und-Organisationen/Standards-und-Zertifizierung/IT-Grundschutz/IT-Grundschutz-Kompendium/)
- [OSCAL Standard (NIST)](https://pages.nist.gov/OSCAL/)
- [SARIF 2.1.0 Specification](https://docs.oasis-open.org/sarif/sarif/v2.1.0/)
- [GitHub Code Scanning SARIF](https://docs.github.com/en/code-security/code-scanning/integrating-with-code-scanning/sarif-support-for-code-scanning)
- [Azure CLI Reference](https://docs.microsoft.com/en-us/cli/azure/)
