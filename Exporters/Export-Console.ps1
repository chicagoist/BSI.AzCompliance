#Requires -Version 5.1
<#
.SYNOPSIS
    Console exporter — color-coded terminal output with summary.
#>
function Export-Console {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][array]$Results
    )

    $summary = Get-BsiSummary

    Write-Host "`n=============================================" -ForegroundColor Cyan
    Write-Host "BSI IT-Grundschutz++ Compliance Results" -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor Cyan

    # Group by category
    $grouped = $Results | Group-Object -Property Category
    foreach ($group in $grouped) {
        Write-Host "`n--- $($group.Name) ---" -ForegroundColor Yellow
        foreach ($r in $group.Group) {
            $color = switch ($r.Status) {
                ([BsiCheckStatus]::Pass)  { 'Green' }
                ([BsiCheckStatus]::Fail)  { 'Red' }
                ([BsiCheckStatus]::Skip)  { 'Yellow' }
                ([BsiCheckStatus]::Error) { 'Magenta' }
            }
            $statusStr = $r.Status.ToString().ToUpper().PadRight(5)
            Write-Host "[$statusStr] " -ForegroundColor $color -NoNewline
            Write-Host "$($r.ControlId) - $($r.ControlTitle)" -ForegroundColor White
            if ($r.Details) {
                Write-Host "       $($r.Details)" -ForegroundColor DarkGray
            }
            if ($r.Remediation) {
                Write-Host "       -> $($r.Remediation)" -ForegroundColor Yellow
            }
        }
    }

    Write-Host "`n=============================================" -ForegroundColor Cyan
    Write-Host "Summary" -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host ("Total checks : {0}" -f $summary.Total) -ForegroundColor White
    Write-Host ("Passed       : {0}" -f $summary.Passed) -ForegroundColor Green
    Write-Host ("Failed       : {0}" -f $summary.Failed) -ForegroundColor $(if ($summary.Failed -gt 0) { 'Red' } else { 'Green' })
    Write-Host ("Skipped      : {0}" -f $summary.Skipped) -ForegroundColor $(if ($summary.Skipped -gt 0) { 'Yellow' } else { 'White' })
    Write-Host ("Score        : {0}%" -f $summary.Score) -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor Cyan

    return $summary
}
