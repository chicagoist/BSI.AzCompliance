#Requires -Version 5.1
<#
.SYNOPSIS
    ComplianceResult class — the core data model for all check outcomes.
.DESCRIPTION
    Strongly-typed result class that every check returns. Supports severity,
    evidence, remediation guidance, and conversion to SARIF/JUnit/JSON.
#>

. (Join-Path $PSScriptRoot '..' 'Enums' 'Severity.psm1')

class ComplianceResult {
    [string]            $ControlId
    [string]            $ControlTitle
    [string]            $Category
    [BsiCheckMode]      $Mode
    [BsiCheckStatus]    $Status
    [BsiSeverity]       $Severity
    [BsiBaseline]       $Baseline
    [string]            $Description
    [string]            $Details
    [string]            $Evidence
    [string]            $Remediation
    [string]            $RemediationUrl
    [string]            $BsiReference
    [string]            $CheckFunction
    [string]            $SourceFile
    [int]               $LineNumber
    [datetime]          $Timestamp
    [hashtable]         $Metadata

    ComplianceResult() {
        $this.Severity     = [BsiSeverity]::Medium
        $this.Baseline     = [BsiBaseline]::B
        $this.Status       = [BsiCheckStatus]::Fail
        $this.Mode         = [BsiCheckMode]::Remote
        $this.Timestamp    = [datetime]::UtcNow
        $this.Metadata     = @{}
        $this.BsiReference = ''
        $this.RemediationUrl = ''
        $this.CheckFunction  = ''
        $this.SourceFile     = ''
        $this.LineNumber     = 0
    }

    ComplianceResult(
        [string]$controlId, [string]$title, [string]$category,
        [BsiCheckMode]$mode, [BsiCheckStatus]$status, [BsiSeverity]$severity,
        [string]$details
    ) {
        $this.ControlId    = $controlId
        $this.ControlTitle = $title
        $this.Category     = $category
        $this.Mode         = $mode
        $this.Status       = $status
        $this.Severity     = $severity
        $this.Details      = $details
        $this.Baseline     = [BsiBaseline]::B
        $this.Timestamp    = [datetime]::UtcNow
        $this.Metadata     = @{}
    }

    [bool] IsPass() {
        return $this.Status -eq [BsiCheckStatus]::Pass
    }

    [string] ToSarifResult() {
        $level = switch ($this.Status) {
            ([BsiCheckStatus]::Pass) { 'none' }
            ([BsiCheckStatus]::Skip) { 'none' }
            default {
                if ($this.Severity -in @([BsiSeverity]::Critical, [BsiSeverity]::High)) {
                    'error'
                } else {
                    'warning'
                }
            }
        }

        $msg = $this.Details
        if ($this.Evidence) { $msg += " | Evidence: $($this.Evidence)" }

        $props = @(
            ('"controlId": "' + $this.ControlId + '"'),
            ('"category": "' + $this.Category + '"'),
            ('"severity": "' + $this.Severity.ToString() + '"'),
            ('"baseline": "' + $this.Baseline.ToString() + '"'),
            ('"bsiReference": "' + ($this.BsiReference -replace '"', '\"') + '"')
        )

        $locBlock = ''
        if ($this.SourceFile) {
            $locBlock = @"
, "locations": [{ "physicalLocation": { "artifactLocation": { "uri": "$($this.SourceFile)" }, "region": { "startLine": $($this.LineNumber) } } }]
"@
        }

        return @"
{
  "ruleId": "$($this.ControlId)",
  "level": "$level",
  "message": { "text": "$($msg -replace '"', '\"')" },
  "properties": { $($props -join ', ') }$locBlock
}
"@
    }

    [string] ToJUnitElement() {
        $escaped = [System.Security.SecurityElement]::Escape($this.Details)
        $name = "$($this.ControlId) - $($this.ControlTitle)"
        $escapedName = [System.Security.SecurityElement]::Escape($name)

        if ($this.IsPass()) {
            return "    <testcase name=`"$escapedName`" classname=`"$($this.Category)`" time=`"0`" />"
        } else {
            $msg = if ($this.Evidence) { "$escaped | $($this.Evidence)" } else { $escaped }
            $escapedMsg = [System.Security.SecurityElement]::Escape($msg)
            return "    <testcase name=`"$escapedName`" classname=`"$($this.Category)`" time=`"0`">
      <failure message=`"BSI control $($this.ControlId) failed`">$escapedMsg</failure>
    </testcase>"
        }
    }
}

# --- Global result store ---
if (-not (Get-Variable -Name 'script:BsiResults' -Scope 'Script' -ErrorAction SilentlyContinue)) {
    Set-Variable -Name 'script:BsiResults' -Scope 'Script' -Value ([System.Collections.ArrayList]::new())
    Set-Variable -Name 'script:BsiPassed'   -Scope 'Script' -Value 0
    Set-Variable -Name 'script:BsiFailed'   -Scope 'Script' -Value 0
    Set-Variable -Name 'script:BsiSkipped'  -Scope 'Script' -Value 0
}

function Reset-BsiResults {
    $script:BsiResults = [System.Collections.ArrayList]::new()
    $script:BsiPassed  = 0
    $script:BsiFailed  = 0
    $script:BsiSkipped = 0
}

function Add-BsiResult {
    <#
    .SYNOPSIS
        Records a single compliance check result.
    #>
    param(
        [Parameter(Mandatory)][string]$ControlId,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][BsiCheckMode]$Mode,
        [Parameter(Mandatory)][BsiCheckStatus]$Status,
        [Parameter(Mandatory)][BsiSeverity]$Severity = [BsiSeverity]::Medium,
        [string]$Details = '',
        [string]$Evidence = '',
        [string]$Remediation = '',
        [string]$RemediationUrl = '',
        [string]$BsiReference = '',
        [string]$CheckFunction = '',
        [string]$SourceFile = '',
        [int]$LineNumber = 0
    )

    $result = [ComplianceResult]::new($ControlId, $Title, $Category, $Mode, $Status, $Severity, $Details)
    $result.Evidence        = $Evidence
    $result.Remediation     = $Remediation
    $result.RemediationUrl  = $RemediationUrl
    $result.BsiReference    = $BsiReference
    $result.CheckFunction   = $CheckFunction
    $result.SourceFile      = $SourceFile
    $result.LineNumber      = $LineNumber

    $null = $script:BsiResults.Add($result)

    switch ($Status) {
        ([BsiCheckStatus]::Pass)  { $script:BsiPassed++ }
        ([BsiCheckStatus]::Fail)  { $script:BsiFailed++ }
        ([BsiCheckStatus]::Skip)  { $script:BsiSkipped++ }
        ([BsiCheckStatus]::Error) { $script:BsiFailed++ }
    }

    $statusStr = $Status.ToString().ToUpper()
    $color = switch ($Status) {
        ([BsiCheckStatus]::Pass)  { 'Green' }
        ([BsiCheckStatus]::Fail)  { 'Red' }
        ([BsiCheckStatus]::Skip)  { 'Yellow' }
        ([BsiCheckStatus]::Error) { 'Magenta' }
    }

    Write-Host ("[{0}] [{1}] [{2}] {3} > {4}" -f $statusStr, $Severity.ToString().ToUpper(), $Mode, $Category, $Title) -ForegroundColor $color
    if ($Details) {
        Write-Host ("       {0}" -f $Details) -ForegroundColor DarkGray
    }
    if ($Evidence) {
        Write-Host ("       Evidence: {0}" -f $Evidence) -ForegroundColor DarkCyan
    }
    if ($Remediation) {
        Write-Host ("       -> {0}" -f $Remediation) -ForegroundColor Yellow
    }
}

function Add-BsiResultObject {
    <#
    .SYNOPSIS
        Records a pre-built ComplianceResult object and prints it.
    .DESCRIPTION
        Convenience wrapper: takes a [ComplianceResult] object directly,
        appends it to the global store, and prints the formatted line.
    #>
    param(
        [Parameter(Mandatory)][ComplianceResult]$Result
    )

    $null = $script:BsiResults.Add($Result)

    switch ($Result.Status) {
        ([BsiCheckStatus]::Pass)  { $script:BsiPassed++ }
        ([BsiCheckStatus]::Fail)  { $script:BsiFailed++ }
        ([BsiCheckStatus]::Skip)  { $script:BsiSkipped++ }
        ([BsiCheckStatus]::Error) { $script:BsiFailed++ }
    }

    $statusStr = $Result.Status.ToString().ToUpper()
    $color = switch ($Result.Status) {
        ([BsiCheckStatus]::Pass)  { 'Green' }
        ([BsiCheckStatus]::Fail)  { 'Red' }
        ([BsiCheckStatus]::Skip)  { 'Yellow' }
        ([BsiCheckStatus]::Error) { 'Magenta' }
    }

    Write-Host ("[{0}] [{1}] [{2}] {3} > {4}" -f $statusStr, $Result.Severity.ToString().ToUpper(), $Result.Mode, $Result.Category, $Result.ControlTitle) -ForegroundColor $color
    if ($Result.Details) {
        Write-Host ("       {0}" -f $Result.Details) -ForegroundColor DarkGray
    }
    if ($Result.Evidence) {
        Write-Host ("       Evidence: {0}" -f $Result.Evidence) -ForegroundColor DarkCyan
    }
    if ($Result.Remediation) {
        Write-Host ("       -> {0}" -f $Result.Remediation) -ForegroundColor Yellow
    }
}

function Get-BsiSummary {
    $total = $script:BsiPassed + $script:BsiFailed + $script:BsiSkipped
    return [PSCustomObject]@{
        Total   = $total
        Passed  = $script:BsiPassed
        Failed  = $script:BsiFailed
        Skipped = $script:BsiSkipped
        Results = $script:BsiResults
        Score   = if ($total -gt 0) { [math]::Round(($script:BsiPassed / $total) * 100, 1) } else { 0 }
    }
}
