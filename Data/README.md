# Data Directory — BSI IT-Grundschutz Compliance Data

This directory contains the **reference data** that powers the BSI.AzCompliance module.
It enables fully **offline local validation** without needing an internet connection.

## Directory Structure

```
Data/
├── README.md                      # This file
├── bsi-azure-mapping.json         # BSI control → Azure check mapping
└── cache/
    └── Grundschutz++-catalog.json  # BSI IT-Grundschutz++ catalog (OSCAL)
```

---

## File: `bsi-azure-mapping.json`

**Purpose:** Maps BSI IT-Grundschutz controls to deploy-time validation checks.

Each mapping entry defines:
| Field | Description |
|-------|-------------|
| `controlId` | BSI control identifier (e.g., `ARCH.5.2`) |
| `title` | Human-readable German title |
| `category` | Check category (`Network`, `VM`, `Identity`, `Backup`, `Monitoring`, `Policy`) |
| `severity` | Impact severity (`Critical`, `High`, `Medium`) |
| `baseline` | BSI baseline requirement (`B`, `C`, `K`) |
| `bsiReference` | BSI internal reference ID |
| `localCheck.patterns` | Regex patterns matched against deployment scripts |
| `localCheck.mustMatchAtLeast` | Minimum number of patterns that must match |

**How it's used:**
- **Local mode** (`-Local`): Patterns are matched against the deployment script to verify that security controls are implemented in code.
- **Remote mode** (`-Remote`): The `controlId` and `bsiReference` are used to correlate with Azure API responses.

---

## File: `cache/Grundschutz++-catalog.json`

**Purpose:** The official BSI IT-Grundschutz++ catalog in OSCAL (Open Security Controls Assessment Language) JSON format.

- Downloaded from: `https://github.com/BSI-Bund/Stand-der-Technik-Bibliothek`
- Format: [OSAL JSON](https://pages.nist.gov/OSCAL/) catalog format
- Size: ~5.4 MB
- Contains: All BSI IT-Grundschutz++ controls, groups, and requirements

This file is **committed to the repository** so that `Invoke-BsiCompliance -Local` works without internet access.

---

## How to Update When BSI Releases a New Catalog

### Quick Update (Manual)

```powershell
Import-Module BSI.AzCompliance
$moduleRoot = Split-Path -Parent (Get-Module BSI.AzCompliance).Path
$mapping = Join-Path $moduleRoot 'Data/bsi-azure-mapping.json'
$outPath = Join-Path $moduleRoot 'Data/cache/Grundschutz++-catalog.json'
Sync-BsiCatalog -OutPath $outPath -MappingPath $mapping
```

Then commit the updated catalog:

```bash
git add Data/cache/Grundschutz++-catalog.json
git commit -m "chore(deps): update BSI Grundschutz++ catalog to YYYY-MM-DD release"
git push
```

### Automated via CI/CD

The `-Sync` flag on `Invoke-BsiCompliance` downloads the latest catalog:

```powershell
Invoke-BsiCompliance -Local -Sync -ScriptPath deploy.ps1
```

### Full Update Checklist

1. **Sync catalog** — download the latest from BSI:
   ```bash
   curl -o Data/cache/Grundschutz++-catalog.json \
     https://raw.githubusercontent.com/BSI-Bund/Stand-der-Technik-Bibliothek/main/Anwenderkataloge/Grundschutz++/Grundschutz++-catalog.json
   ```

2. **Review new/changed controls** — check if any new controls should be mapped:
   ```powershell
   Import-Module BSI.AzCompliance
   $old = Get-BsiCatalog -Path Data/cache/Grundschutz++-catalog-OLD.json
   $new = Get-BsiCatalog -Path Data/cache/Grundschutz++-catalog.json
   $oldControls = Get-BsiCatalogControls -Catalog $old
   $newControls = Get-BsiCatalogControls -Catalog $new
   $oldIds = $oldControls | ForEach-Object { $_.id }
   $newIds = $newControls | ForEach-Object { $_.id }
   Compare-Object $oldIds $newIds  # Check for added/removed controls
   ```

3. **Update `bsi-azure-mapping.json`** — add mappings for new controls that are relevant to Azure deployments.

4. **Update `lastSynced` timestamp** — change the `lastSynced` field in `bsi-azure-mapping.json` to the current UTC time:
   ```json
   "lastSynced": "2026-07-26T21:00:00Z"
   ```

5. **Run local validation** — verify nothing is broken:
   ```powershell
   Invoke-BsiCompliance -Local -ScriptPath Tests/Integration/trap-real-00-baseline.ps1
   ```

6. **Commit both files** — always commit the catalog and mapping together:
   ```bash
   git add Data/cache/Grundschutz++-catalog.json Data/bsi-azure-mapping.json
   git commit -m "chore(deps): update BSI Grundschutz++ catalog + mapping"
   ```

> **Note:** The `Data/cache/` directory in `.gitignore` only ignores temporary files (`*.tmp`, `*.download`, `*.bak`). The committed `Grundschutz++-catalog.json` **is tracked** in git.

---

## How the Module Uses These Files

```
Invoke-BsiCompliance -Local -ScriptPath deploy.ps1
                           │
                           ▼
                    Data/bsi-azure-mapping.json
                           │
                           ▼
                    For each mapping entry:
                      ├─ controlId  ──────────►  Data/cache/Grundschutz++-catalog.json
                      │                            (verify control exists in BSI catalog)
                      └─ localCheck.patterns  ──►  Scan deploy.ps1 for regex matches
                                                    │
                                                    ▼
                                              ComplianceResult
                                              (pass/fail per control)
```

---

## Repository Source

The canonical BSI IT-Grundschutz++ catalog is maintained at:

**GitHub:** [BSI-Bund/Stand-der-Technik-Bibliothek](https://github.com/BSI-Bund/Stand-der-Technik-Bibliothek)  
**Catalog path:** `Anwenderkataloge/Grundschutz++/Grundschutz++-catalog.json`  

The old repository (`BSI-Bund/IT-Grundschutz-Kompendium`) has been **archived** and is no longer updated.
