#Requires -Version 5.1
<#
.SYNOPSIS
    Core enums for BSI compliance framework.
.DESCRIPTION
    Defines severity levels, check modes, output formats, and baseline classifications
    used across the BSI IT-Grundschutz++ compliance validation framework.
    Uses Add-Type for globally-visible .NET enum types (required for module export).
#>

# --- Globally-visible .NET enums via Add-Type ---
# Each defined once (idempotent via -IgnoreWarnings or pre-checks)

if (-not ('BsiSeverity' -as [type])) {
    Add-Type -TypeDefinition @"
    public enum BsiSeverity {
        Critical = 0,
        High     = 1,
        Medium   = 2,
        Low      = 3,
        Info     = 4
    }
"@ -ErrorAction Stop
}

if (-not ('BsiCheckMode' -as [type])) {
    Add-Type -TypeDefinition @"
    public enum BsiCheckMode {
        Local  = 0,
        Remote = 1
    }
"@ -ErrorAction Stop
}

if (-not ('BsiOutputFormat' -as [type])) {
    Add-Type -TypeDefinition @"
    public enum BsiOutputFormat {
        Console  = 0,
        Json     = 1,
        Sarif    = 2,
        JUnitXml = 3,
        Html     = 4
    }
"@ -ErrorAction Stop
}

if (-not ('BsiBaseline' -as [type])) {
    Add-Type -TypeDefinition @"
    public enum BsiBaseline {
        B = 0,
        C = 1,
        D = 2
    }
"@ -ErrorAction Stop
}

if (-not ('BsiCheckStatus' -as [type])) {
    Add-Type -TypeDefinition @"
    public enum BsiCheckStatus {
        Pass  = 0,
        Fail  = 1,
        Skip  = 2,
        Error = 3
    }
"@ -ErrorAction Stop
}

# --- Helper: convert severity string to enum ---
function ConvertTo-BsiSeverity {
    param([string]$Value)
    switch ($Value.ToLower()) {
        'critical' { return [BsiSeverity]::Critical }
        'high'     { return [BsiSeverity]::High }
        'medium'   { return [BsiSeverity]::Medium }
        'low'      { return [BsiSeverity]::Low }
        'info'     { return [BsiSeverity]::Info }
        default    { return [BsiSeverity]::Medium }
    }
}

# --- Helper: convert severity enum to string ---
function ConvertFrom-BsiSeverity {
    param([BsiSeverity]$Severity)
    return $Severity.ToString()
}

# --- Helper: convert output format string to enum ---
function ConvertTo-BsiOutputFormat {
    param([string]$Value)
    switch ($Value.ToLower()) {
        'console'  { return [BsiOutputFormat]::Console }
        'json'     { return [BsiOutputFormat]::Json }
        'sarif'    { return [BsiOutputFormat]::Sarif }
        'junitxml' { return [BsiOutputFormat]::JUnitXml }
        'html'     { return [BsiOutputFormat]::Html }
        default    { return [BsiOutputFormat]::Console }
    }
}

# --- Helper: convert baseline string to enum ---
function ConvertTo-BsiBaseline {
    param([string]$Value)
    switch ($Value.ToUpper()) {
        'B' { return [BsiBaseline]::B }
        'C' { return [BsiBaseline]::C }
        'D' { return [BsiBaseline]::D }
        default { return [BsiBaseline]::B }
    }
}

# --- Helper: get numeric weight for severity ---
function Get-BsiSeverityWeight {
    param([BsiSeverity]$Severity)
    switch ($Severity) {
        ([BsiSeverity]::Critical) { return 8 }
        ([BsiSeverity]::High)     { return 4 }
        ([BsiSeverity]::Medium)   { return 1 }
        ([BsiSeverity]::Low)      { return 0 }
        ([BsiSeverity]::Info)     { return 0 }
    }
    return 0
}
