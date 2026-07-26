# CI/CD Setup: BSI Compliance Pipeline

## Overview

The GitHub Actions pipeline (`bsi-compliance.yml`) runs BSI IT-Grundschutz++ compliance checks in two modes:
- **Local**: Static analysis of deployment scripts (runs on every PR)
- **Remote**: Live Azure infrastructure validation (runs on schedule + manual trigger)

## Required GitHub Secrets

### For Remote Validation

| Secret | Description | How to get |
|--------|-------------|------------|
| `AZURE_CLIENT_ID` | Azure AD App Registration Client ID | Azure Portal → App Registrations |
| `AZURE_TENANT_ID` | Azure AD Tenant ID | Azure Portal → Tenant properties |
| `AZURE_SUBSCRIPTION_ID` | Azure Subscription ID | `az account show --query id` |
| `CONFIG_PS1_B64` | Base64-encoded config.ps1 | See below |

### How to create CONFIG_PS1_B64

```powershell
# From deployment project root:
$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes('scripts/config.ps1'))
Set-Clipboard -Value $b64
Write-Host "Copied to clipboard. Paste into GitHub Secret CONFIG_PS1_B64"
```

Or on Linux/WSL:
```bash
base64 -w0 scripts/config.ps1 | xclip -selection clipboard
```

### OIDC Federation Setup

1. Create Azure AD App Registration with Federated Credentials
2. Configure GitHub → Azure trust: `https://token.actions.githubusercontent.com`
3. Grant App Registration `Reader` + `Key Vault Secrets User` roles on your subscription
4. Add secrets to GitHub repo: Settings → Secrets and variables → Actions

## Triggers

| Trigger | Local | Remote |
|---------|-------|--------|
| Pull Request | ✅ | ❌ |
| Push to main | ✅ | ✅ |
| Schedule (Mon 06:00 UTC) | ❌ | ✅ |
| workflow_dispatch (manual) | ❌ | ✅ |

## Reports

- **SARIF**: Uploaded to GitHub Code Scanning (Security → Code scanning alerts)
- **HTML**: Available as build artifact (Actions → Run → Artifacts, 30-day retention)
- **JSON**: Available as build artifact for programmatic consumption
