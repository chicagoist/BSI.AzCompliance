#Requires -Version 5.1
<#
.SYNOPSIS
    JUnit XML exporter — for Azure DevOps, Jenkins, and CI/CD pipelines.
.DESCRIPTION
    Generates JUnit-compatible XML test results from BSI compliance checks.
    Compatible with dorny/test-reporter (GitHub Actions) and Azure DevOps test reporting.
.LINK
    https://github.com/dorny/test-reporter
#>
function Export-JUnitXml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][array]$Results,
        [string]$OutputPath = '',
        [string]$TestSuiteName = 'BSI IT-Grundschutz++ Compliance'
    )

    $summary = Get-BsiSummary
    $timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'

    # Group by category for test suites
    $grouped = $Results | Group-Object -Property Category

    $suiteXml = [System.Collections.ArrayList]::new()

    foreach ($group in $grouped) {
        $testCases = [System.Collections.ArrayList]::new()
        $failures  = 0
        $errors    = 0

        foreach ($r in $group.Group) {
            $escapedName = [System.Security.SecurityElement]::Escape("$($r.ControlId) - $($r.ControlTitle)")
            $className   = [System.Security.SecurityElement]::Escape($r.Category)

            if ($r.Status -eq [BsiCheckStatus]::Pass -or $r.Status -eq [BsiCheckStatus]::Skip) {
                $null = $testCases.Add("      <testcase name=`"$escapedName`" classname=`"$className`" time=`"0`" />")
            } else {
                $failures++
                $msg = [System.Security.SecurityElement]::Escape($r.Details)
                if ($r.Remediation) { $msg += " | $($r.Remediation)" }
                $msg = [System.Security.SecurityElement]::Escape($msg)
                $null = $testCases.Add("      <testcase name=`"$escapedName`" classname=`"$className`" time=`"0`">
        <failure message=`"BSI control $($r.ControlId) $($r.Status.ToString())`">$msg</failure>
      </testcase>")
            }
        }

        $suiteName = [System.Security.SecurityElement]::Escape($group.Name)
        $testCount = $group.Group.Count

        $null = $suiteXml.Add("    <testsuite name=`"$suiteName`" tests=`"$testCount`" failures=`"$failures`" errors=`"$errors`" timestamp=`"$timestamp`">")
        foreach ($tc in $testCases) { $null = $suiteXml.Add($tc) }
        $null = $suiteXml.Add("    </testsuite>")
    }

    $xml = @"
<?xml version="1.0" encoding="UTF-8"?>
<testsuites name="$([System.Security.SecurityElement]::Escape($TestSuiteName))" tests="$($summary.Total)" failures="$($summary.Failed)" errors="0">
$suiteXml
</testsuites>
"@

    if ($OutputPath) {
        $dir = Split-Path -Parent $OutputPath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($OutputPath, $xml, $utf8NoBom)
        Write-Verbose "[Export-JUnitXml] Written to $OutputPath"
    }

    return $xml
}
