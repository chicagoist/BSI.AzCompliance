#Requires -Version 5.1
<#
.SYNOPSIS
    HTML exporter — executive compliance dashboard.
.DESCRIPTION
    Generates a self-contained HTML report with pass/fail gauge,
    category breakdown, control details, and remediation guidance.
#>
function Export-Html {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][array]$Results,
        [string]$OutputPath = '',
        [string]$Title = 'BSI IT-Grundschutz++ Compliance Report'
    )

    $summary = Get-BsiSummary
    $grouped = $Results | Group-Object -Property Category

    # Build category rows
    $categoryRows = ''
    foreach ($group in $grouped) {
        $catPassed = @($group.Group | Where-Object { $_.Status -eq [BsiCheckStatus]::Pass }).Count
        $catTotal  = $group.Group.Count
        $catPct    = if ($catTotal -gt 0) { [math]::Round(($catPassed / $catTotal) * 100) } else { 0 }
        $catColor  = if ($catPct -ge 80) { '#22c55e' } elseif ($catPct -ge 50) { '#eab308' } else { '#ef4444' }

        $categoryRows += "      <tr>
        <td>$($group.Name)</td>
        <td>$catPassed / $catTotal</td>
        <td><div class='bar-bg'><div class='bar-fill' style='width:${catPct}%;background:$catColor'></div></div></td>
        <td>$catPct%</td>
      </tr>`n"
    }

    # Build control detail rows
    $controlRows = ''
    foreach ($r in $Results) {
        $statusColor = switch ($r.Status) {
            ([BsiCheckStatus]::Pass)  { '#22c55e' }
            ([BsiCheckStatus]::Fail)  { '#ef4444' }
            ([BsiCheckStatus]::Skip)  { '#eab308' }
            ([BsiCheckStatus]::Error) { '#a855f7' }
        }
        $sevColor = switch ($r.Severity) {
            ([BsiSeverity]::Critical) { '#ef4444' }
            ([BsiSeverity]::High)     { '#f97316' }
            ([BsiSeverity]::Medium)   { '#eab308' }
            ([BsiSeverity]::Low)      { '#22c55e' }
            ([BsiSeverity]::Info)     { '#6b7280' }
        }
        $details  = [System.Net.WebUtility]::HtmlEncode($r.Details)
        $remed    = if ($r.Remediation) { "<br><small class='remed'>-> $([System.Net.WebUtility]::HtmlEncode($r.Remediation))</small>" } else { '' }

        $controlRows += "      <tr>
        <td><span class='badge' style='background:$sevColor'>$($r.Severity)</span></td>
        <td><strong>$($r.ControlId)</strong></td>
        <td>$($r.ControlTitle)</td>
        <td><span class='badge' style='background:$statusColor'>$(if ($r.Status -eq [BsiCheckStatus]::Pass) { 'PASS' } else { 'FAIL' })</span></td>
        <td>$details$remed</td>
      </tr>`n"
    }

    # Score color
    $scoreColor = if ($summary.Score -ge 90) { '#22c55e' } elseif ($summary.Score -ge 70) { '#eab308' } else { '#ef4444' }
    $scoreDeg = [math]::Round($summary.Score * 3.6)

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>$Title</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #0f172a; color: #e2e8f0; padding: 2rem; }
  .container { max-width: 1200px; margin: 0 auto; }
  h1 { font-size: 1.5rem; margin-bottom: 0.5rem; color: #f1f5f9; }
  .subtitle { color: #94a3b8; font-size: 0.875rem; margin-bottom: 2rem; }
  .cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; margin-bottom: 2rem; }
  .card { background: #1e293b; border-radius: 12px; padding: 1.5rem; text-align: center; }
  .card h2 { font-size: 2rem; margin-bottom: 0.25rem; }
  .card p { color: #94a3b8; font-size: 0.875rem; }
  .gauge-container { position: relative; width: 160px; height: 160px; margin: 0 auto 1rem; }
  .gauge-bg { fill: none; stroke: #334155; stroke-width: 12; }
  .gauge-fill { fill: none; stroke: $scoreColor; stroke-width: 12; stroke-linecap: round; transform: rotate(-90deg); transform-origin: 50% 50%; transition: stroke-dashoffset 1s; }
  .gauge-text { font-size: 2.5rem; font-weight: bold; fill: #f1f5f9; text-anchor: middle; dominant-baseline: central; }
  table { width: 100%; border-collapse: collapse; margin-bottom: 2rem; }
  th, td { padding: 0.75rem 1rem; text-align: left; border-bottom: 1px solid #1e293b; }
  th { background: #1e293b; color: #94a3b8; font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.05em; }
  tr:hover { background: #1e293b; }
  .badge { padding: 0.25rem 0.75rem; border-radius: 9999px; font-size: 0.75rem; font-weight: 600; color: #fff; }
  .bar-bg { background: #334155; border-radius: 4px; height: 8px; width: 100%; }
  .bar-fill { height: 100%; border-radius: 4px; transition: width 0.5s; }
  .section { margin-bottom: 2rem; }
  .section h2 { font-size: 1.125rem; margin-bottom: 1rem; color: #f1f5f9; }
  .remed { color: #fbbf24; }
  footer { color: #475569; font-size: 0.75rem; text-align: center; margin-top: 2rem; }
</style>
</head>
<body>
<div class="container">
  <h1>$Title</h1>
  <p class="subtitle">Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC') | BSI Grundschutz++ OSCAL</p>

  <div class="cards">
    <div class="card">
      <div class="gauge-container">
        <svg viewBox="0 0 160 160">
          <circle class="gauge-bg" cx="80" cy="80" r="68" />
          <circle class="gauge-fill" cx="80" cy="80" r="68"
            stroke-dasharray="427" stroke-dashoffset="$([math]::Round(427 - (427 * $summary.Score / 100)))" />
          <text class="gauge-text" x="80" y="80">$($summary.Score)%</text>
        </svg>
      </div>
      <p>Compliance Score</p>
    </div>
    <div class="card"><h2 style="color:#22c55e">$($summary.Passed)</h2><p>Passed</p></div>
    <div class="card"><h2 style="color:#ef4444">$($summary.Failed)</h2><p>Failed</p></div>
    <div class="card"><h2>$($summary.Total)</h2><p>Total Checks</p></div>
  </div>

  <div class="section">
    <h2>Category Breakdown</h2>
    <table>
      <thead><tr><th>Category</th><th>Passed / Total</th><th>Progress</th><th>Score</th></tr></thead>
      <tbody>
$categoryRows      </tbody>
    </table>
  </div>

  <div class="section">
    <h2>Control Details</h2>
    <table>
      <thead><tr><th>Severity</th><th>Control</th><th>Title</th><th>Status</th><th>Details</th></tr></thead>
      <tbody>
$controlRows      </tbody>
    </table>
  </div>

  <footer>
    BSI.AzCompliance v2.0.0 | BSI IT-Grundschutz++ | $(Get-Date -Format 'yyyy')
  </footer>
</div>
</body>
</html>
"@

    if ($OutputPath) {
        $dir = Split-Path -Parent $OutputPath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($OutputPath, $html, $utf8NoBom)
        Write-Verbose "[Export-Html] Written to $OutputPath"
    }

    return $html
}
