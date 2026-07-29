#Requires -Version 5.1
<#
.SYNOPSIS
    SARIF 2.1.0 exporter — for GitHub Code Scanning integration.
.DESCRIPTION
    Generates SARIF format output compatible with GitHub's code scanning
    alerts feature. Each failed BSI control becomes a SARIF result with
    severity mapping, remediation guidance, and source location.
.LINK
    https://docs.github.com/en/code-security/code-scanning/integrating-with-code-scanning/sarif-support-for-code-scanning
#>
function Export-Sarif {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][array]$Results,
        [string]$OutputPath = '',
        [string]$Version = '2.0.0'
    )

    # Build rules from check manifest
    $rules = @()
    $manifestPath = Join-Path $PSScriptRoot '..' 'Checks' '_CheckManifest.json'
    if (Test-Path -LiteralPath $manifestPath) {
        $manifest = Get-Content -Raw -Path $manifestPath | ConvertFrom-Json
        foreach ($check in $manifest.checks) {
            $level = if ($check.severity -in @('Critical', 'High')) { 'error' } else { 'warning' }
            $rules += [PSCustomObject]@{
                id          = $check.id
                name        = $check.function
                shortDescription = [PSCustomObject]@{ text = $check.description }
                defaultConfiguration = [PSCustomObject]@{ level = $level }
                properties  = [PSCustomObject]@{
                    category       = $check.category
                    severity       = $check.severity
                    baseline       = $check.baseline
                    bsiReference   = $check.bsiReference
                }
            }
        }
    } else {
        Write-Warning "[Export-Sarif] Check manifest not found at $manifestPath -- SARIF output will not include rule definitions"
    }
    $sarifResults = @()
    foreach ($r in $Results) {
        $level = switch ($r.Status) {
            ([BsiCheckStatus]::Pass)  { 'none' }
            ([BsiCheckStatus]::Skip)  { 'none' }
            default {
                if ($r.Severity -in @([BsiSeverity]::Critical, [BsiSeverity]::High)) { 'error' } else { 'warning' }
            }
        }

        $msgText = "$($r.ControlId): $($r.Details)"
        if ($r.Remediation) { $msgText += " | Remediation: $($r.Remediation)" }

        $resultObj = [PSCustomObject]@{
            ruleId      = $r.ControlId
            level       = $level
            message     = [PSCustomObject]@{ text = $msgText }
            properties  = [PSCustomObject]@{
                status     = $r.Status.ToString()
                severity   = $r.Severity.ToString()
                baseline   = $r.Baseline.ToString()
                category   = $r.Category
                evidence   = $r.Evidence
            }
        }

        # GitHub Code Scanning requires at least one location per result.
        # Use SourceFile if available, otherwise fall back to a logical location.
        $uri = if ($r.SourceFile) { $r.SourceFile } else { 'bsi-compliance-check' }
        $line = if ($r.LineNumber -gt 0) { $r.LineNumber } else { 1 }
        $resultObj | Add-Member -NotePropertyName 'locations' -NotePropertyValue @(
            [PSCustomObject]@{
                physicalLocation = [PSCustomObject]@{
                    artifactLocation = [PSCustomObject]@{
                        uri = $uri
                    }
                    region = [PSCustomObject]@{
                        startLine = $line
                    }
                }
            }
        )

        $sarifResults += $resultObj
    }

    # Build SARIF document
    $sarif = [PSCustomObject]@{
        '$schema' = 'https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json'
        version   = '2.1.0'
        runs      = @(
            [PSCustomObject]@{
                tool = [PSCustomObject]@{
                    driver = [PSCustomObject]@{
                        name           = 'BSI.AzCompliance'
                        version        = $Version
                        semanticVersion = $Version
                        informationUri = 'https://github.com/chicagoist/BSI-AzCompliance'
                        rules          = $rules
                    }
                }
                results = $sarifResults
            }
        )
    }

    $json = $sarif | ConvertTo-Json -Depth 10

    if ($OutputPath) {
        $dir = Split-Path -Parent $OutputPath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $json | Set-Content -Path $OutputPath -Encoding UTF8
        Write-Verbose "[Export-Sarif] Written to $OutputPath"
    }

    return $json
}
