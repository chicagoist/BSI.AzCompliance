#Requires -Version 5.1
<#
.SYNOPSIS
    Generate a compliance report in any supported format.
.PARAMETER Format
    Output format: Console, Json, Sarif, JUnitXml, Html.
.PARAMETER OutputPath
    File path for the report.
.PARAMETER Title
    Report title (used in HTML).
.EXAMPLE
    New-BsiComplianceReport -Format Html -OutputPath .\reports\compliance.html
.EXAMPLE
    New-BsiComplianceReport -Format Sarif,Json -OutputPath .\reports\bsi-results
#>
function New-BsiComplianceReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Format,
        [Parameter(Mandatory)][string]$OutputPath,
        [string]$Title = 'BSI IT-Grundschutz++ Compliance Report'
    )

    $results = @($script:BsiResults)
    if ($results.Count -eq 0) {
        Write-Warning "No compliance results to export. Run Invoke-BsiCompliance first."
        return
    }

    $formats = $Format -split ',' | ForEach-Object { $_.Trim() }
    foreach ($fmt in $formats) {
        $basePath = $OutputPath
        switch ($fmt.ToLower()) {
            'json'     { Export-Json -Results $results -OutputPath "$basePath.json" }
            'sarif'    { Export-Sarif -Results $results -OutputPath "$basePath.sarif" }
            'junitxml' { Export-JUnitXml -Results $results -OutputPath "$basePath.junit.xml" }
            'html'     { Export-Html -Results $results -OutputPath "$basePath.html" -Title $Title }
            'console'  { Export-Console -Results $results }
            default    { Write-Warning "Unknown format: $fmt" }
        }
    }
}
