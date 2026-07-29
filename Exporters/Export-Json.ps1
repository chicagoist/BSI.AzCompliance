#Requires -Version 5.1
<#
.SYNOPSIS
    JSON exporter — structured compliance report.
#>
function Export-Json {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][array]$Results,
        [string]$OutputPath = ''
    )

    $summary = Get-BsiSummary

    $report = [PSCustomObject]@{
        schemaVersion = '2.0.0'
        generator     = 'BSI.AzCompliance'
        generatedAt   = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
        summary       = [PSCustomObject]@{
            total   = $summary.Total
            passed  = $summary.Passed
            failed  = $summary.Failed
            skipped = $summary.Skipped
            score   = $summary.Score
        }
        controls = @($Results | ForEach-Object {
            [PSCustomObject]@{
                controlId    = $_.ControlId
                title        = $_.ControlTitle
                category     = $_.Category
                mode         = $_.Mode.ToString()
                status       = $_.Status.ToString()
                severity     = $_.Severity.ToString()
                baseline     = $_.Baseline.ToString()
                description  = $_.Description
                details      = $_.Details
                evidence     = $_.Evidence
                remediation  = $_.Remediation
                bsiReference = $_.BsiReference
            }
        })
    }

    $json = $report | ConvertTo-Json -Depth 10

    if ($OutputPath) {
        $dir = Split-Path -Parent $OutputPath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($OutputPath, $json, $utf8NoBom)
        Write-Verbose "[Export-Json] Written to $OutputPath"
    }

    return $json
}
