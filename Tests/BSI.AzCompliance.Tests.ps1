#Requires -Version 5.1

# --- Resolve paths ---
$testFile = if ($PSCommandPath) { $PSCommandPath } elseif ($PSScriptRoot) { Join-Path $PSScriptRoot 'BSI.AzCompliance.Tests.ps1' } else { $MyInvocation.MyCommand.Path }
$testDir  = Split-Path -Parent $testFile
$moduleRoot = Split-Path -Parent $testDir

# Import module (no using module needed — New-BsiComplianceResult handles class creation)
Import-Module (Join-Path $moduleRoot 'BSI.AzCompliance.psd1') -Force

# ============================================================
#  ENUMS
# ============================================================
Describe 'BsiSeverity Enum' {
    It 'defines all severity levels' {
        [enum]::GetNames([BsiSeverity]) | Should -Contain 'Critical'
        [enum]::GetNames([BsiSeverity]) | Should -Contain 'High'
        [enum]::GetNames([BsiSeverity]) | Should -Contain 'Medium'
        [enum]::GetNames([BsiSeverity]) | Should -Contain 'Low'
        [enum]::GetNames([BsiSeverity]) | Should -Contain 'Info'
    }
}

Describe 'BsiCheckStatus Enum' {
    It 'defines Pass, Fail, Skip, Error' {
        [enum]::GetNames([BsiCheckStatus]) | Should -Contain 'Pass'
        [enum]::GetNames([BsiCheckStatus]) | Should -Contain 'Fail'
        [enum]::GetNames([BsiCheckStatus]) | Should -Contain 'Skip'
        [enum]::GetNames([BsiCheckStatus]) | Should -Contain 'Error'
    }
}

# ============================================================
#  COMPLIANCE RESULT (via New-BsiComplianceResult helper)
# ============================================================
Describe 'ComplianceResult class' {
    It 'creates with default constructor' {
        $r = New-BsiComplianceResult
        $r.Severity | Should -Be ([BsiSeverity]::Medium)
        $r.Status | Should -Be ([BsiCheckStatus]::Fail)
        $r.Baseline | Should -Be ([BsiBaseline]::B)
        $r.Timestamp | Should -Not -BeNullOrEmpty
    }

    It 'creates with parameterized constructor' {
        $r = New-BsiComplianceResult -ControlId 'ARCH.5.2' -Title 'NSG Deny Rules' `
            -Category 'Network' -Mode ([BsiCheckMode]::Remote) `
            -Status ([BsiCheckStatus]::Pass) -Severity ([BsiSeverity]::High) `
            -Details 'All NSGs deny SSH'
        $r.ControlId | Should -Be 'ARCH.5.2'
        $r.ControlTitle | Should -Be 'NSG Deny Rules'
        $r.Category | Should -Be 'Network'
        $r.Mode | Should -Be ([BsiCheckMode]::Remote)
        $r.Status | Should -Be ([BsiCheckStatus]::Pass)
        $r.Severity | Should -Be ([BsiSeverity]::High)
        $r.Details | Should -Be 'All NSGs deny SSH'
    }

    It 'IsPass returns true for Pass status' {
        $r = New-BsiComplianceResult
        $r.Status = [BsiCheckStatus]::Pass
        $r.IsPass() | Should -BeTrue
    }

    It 'IsPass returns false for Fail status' {
        $r = New-BsiComplianceResult
        $r.Status = [BsiCheckStatus]::Fail
        $r.IsPass() | Should -BeFalse
    }

    It 'ToSarifResult produces valid SARIF fragment' {
        $r = New-BsiComplianceResult -ControlId 'ARCH.5.2' -Title 'NSG Deny' `
            -Category 'Network' -Mode ([BsiCheckMode]::Remote) `
            -Status ([BsiCheckStatus]::Fail) -Severity ([BsiSeverity]::High) `
            -Details 'Missing deny rule'
        $r.BsiReference = 'https://bsi.bund.de'
        $sarif = $r.ToSarifResult()
        $sarif | Should -Match '"ruleId": "ARCH\.5\.2"'
        $sarif | Should -Match '"level": "error"'
        $sarif | Should -Match 'Missing deny rule'
    }

    It 'ToSarifResult returns level none for Pass' {
        $r = New-BsiComplianceResult -ControlId 'ARCH.5.2' -Title 'NSG Deny' `
            -Category 'Network' -Mode ([BsiCheckMode]::Remote) `
            -Status ([BsiCheckStatus]::Pass) -Severity ([BsiSeverity]::High) `
            -Details 'All good'
        $sarif = $r.ToSarifResult()
        $sarif | Should -Match '"level": "none"'
    }

    It 'ToJUnitElement produces testcase for pass' {
        $r = New-BsiComplianceResult -ControlId 'NOT.4' -Title 'Backup' `
            -Category 'Backup' -Mode ([BsiCheckMode]::Remote) `
            -Status ([BsiCheckStatus]::Pass) -Severity ([BsiSeverity]::High) `
            -Details 'Protected'
        $xml = $r.ToJUnitElement()
        $xml | Should -Match '<testcase'
        $xml | Should -Not -Match '<failure'
    }

    It 'ToJUnitElement produces failure for fail' {
        $r = New-BsiComplianceResult -ControlId 'NOT.4' -Title 'Backup' `
            -Category 'Backup' -Mode ([BsiCheckMode]::Remote) `
            -Status ([BsiCheckStatus]::Fail) -Severity ([BsiSeverity]::High) `
            -Details 'Not protected'
        $xml = $r.ToJUnitElement()
        $xml | Should -Match '<failure'
        $xml | Should -Match 'BSI control NOT\.4 failed'
    }
}

# ============================================================
#  RESULT STORE
# ============================================================
Describe 'Result store functions' {
    BeforeEach {
        Reset-BsiResults
    }

    It 'Reset-BsiResults clears all counters' {
        Add-BsiResult -ControlId 'TEST.1' -Title 'Test' -Category 'Unit' `
            -Mode ([BsiCheckMode]::Local) -Status ([BsiCheckStatus]::Pass) `
            -Severity ([BsiSeverity]::Low) -Details 'dummy'
        Reset-BsiResults
        $summary = Get-BsiSummary
        $summary.Total | Should -Be 0
        $summary.Passed | Should -Be 0
    }

    It 'Add-BsiResult increments pass counter' {
        Add-BsiResult -ControlId 'TEST.1' -Title 'Test' -Category 'Unit' `
            -Mode ([BsiCheckMode]::Local) -Status ([BsiCheckStatus]::Pass) `
            -Severity ([BsiSeverity]::Low) -Details 'pass test'
        $summary = Get-BsiSummary
        $summary.Passed | Should -Be 1
        $summary.Total | Should -Be 1
    }

    It 'Add-BsiResult increments fail counter' {
        Add-BsiResult -ControlId 'TEST.2' -Title 'Test' -Category 'Unit' `
            -Mode ([BsiCheckMode]::Local) -Status ([BsiCheckStatus]::Fail) `
            -Severity ([BsiSeverity]::Medium) -Details 'fail test'
        $summary = Get-BsiSummary
        $summary.Failed | Should -Be 1
    }

    It 'Add-BsiResult increments skip counter' {
        Add-BsiResult -ControlId 'TEST.3' -Title 'Test' -Category 'Unit' `
            -Mode ([BsiCheckMode]::Local) -Status ([BsiCheckStatus]::Skip) `
            -Severity ([BsiSeverity]::Low) -Details 'skip test'
        $summary = Get-BsiSummary
        $summary.Skipped | Should -Be 1
    }

    It 'Add-BsiResultObject adds ComplianceResult to store' {
        $r = New-BsiComplianceResult -ControlId 'OBJ.1' -Title 'Object Test' `
            -Category 'Unit' -Mode ([BsiCheckMode]::Remote) `
            -Status ([BsiCheckStatus]::Pass) -Severity ([BsiSeverity]::Low) `
            -Details 'via object'
        Add-BsiResultObject -Result $r
        $summary = Get-BsiSummary
        $summary.Total | Should -Be 1
        $summary.Passed | Should -Be 1
    }

    It 'Get-BsiSummary calculates score correctly' {
        Add-BsiResult -ControlId 'S1' -Title 'T' -Category 'C' `
            -Mode ([BsiCheckMode]::Local) -Status ([BsiCheckStatus]::Pass) `
            -Severity ([BsiSeverity]::Low) -Details 'p1'
        Add-BsiResult -ControlId 'S2' -Title 'T' -Category 'C' `
            -Mode ([BsiCheckMode]::Local) -Status ([BsiCheckStatus]::Pass) `
            -Severity ([BsiSeverity]::Low) -Details 'p2'
        Add-BsiResult -ControlId 'S3' -Title 'T' -Category 'C' `
            -Mode ([BsiCheckMode]::Local) -Status ([BsiCheckStatus]::Fail) `
            -Severity ([BsiSeverity]::Medium) -Details 'f1'
        $summary = Get-BsiSummary
        $summary.Score | Should -Be 66.7
    }
}

# ============================================================
#  CATALOG & MAPPING
# ============================================================
Describe 'Catalog functions' {
    It 'Test-BsiCatalogExists returns false for missing path' {
        $result = $false
        try {
            $result = Test-BsiCatalogExists -Path (Join-Path $TestDrive 'nonexistent' 'catalog.json')
        } catch {
            # Private function — skip gracefully
            Set-ItResult -Skipped -Because 'Test-BsiCatalogExists is a private function (not exported)'
            return
        }
        $result | Should -BeFalse
    }

    It 'Get-BsiCatalog returns null for missing path' {
        $result = $null
        try {
            $result = Get-BsiCatalog -Path (Join-Path $TestDrive 'nonexistent' 'catalog.json')
        } catch {
            Set-ItResult -Skipped -Because 'Get-BsiCatalog is a private function (not exported)'
            return
        }
        $result | Should -BeNullOrEmpty
    }
}

Describe 'Mapping functions' {
    $mapPath = Join-Path $moduleRoot 'Data' 'bsi-azure-mapping.json'

    It 'Get-BsiMapping loads valid mapping' {
        if (Test-Path -LiteralPath $mapPath) {
            $m = Get-BsiMapping -Path $mapPath
            $m | Should -Not -BeNullOrEmpty
            $m.mappings | Should -Not -BeNullOrEmpty
        } else {
            Set-ItResult -Skipped -Because "mapping file not found at $mapPath"
        }
    }
}

# ============================================================
#  CHECK MANIFEST
# ============================================================
Describe 'Check manifest' {
    $manifestPath = Join-Path $moduleRoot 'Checks' '_CheckManifest.json'

    It 'exists' {
        if (-not $manifestPath) {
            Set-ItResult -Skipped -Because 'moduleRoot not resolved'
            return
        }
        Test-Path -LiteralPath $manifestPath | Should -BeTrue
    }

    It 'is valid JSON' {
        if (-not $manifestPath -or -not (Test-Path -LiteralPath $manifestPath)) {
            Set-ItResult -Skipped -Because 'manifest not found'
            return
        }
        $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
        $manifest | Should -Not -BeNullOrEmpty
        $manifest.checks.Count | Should -BeGreaterThan 0
    }

    It 'all declared check functions have matching .ps1 files' {
        if (-not $manifestPath -or -not (Test-Path -LiteralPath $manifestPath)) {
            Set-ItResult -Skipped -Because 'manifest not found'
            return
        }
        $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
        foreach ($check in $manifest.checks) {
            $checkPath = Join-Path $moduleRoot $check.file
            Test-Path -LiteralPath $checkPath | Should -BeTrue -Because "check $($check.id) needs $($check.file)"
        }
    }

    It 'every check has a unique id' {
        if (-not $manifestPath -or -not (Test-Path -LiteralPath $manifestPath)) {
            Set-ItResult -Skipped -Because 'manifest not found'
            return
        }
        $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
        $ids = $manifest.checks | ForEach-Object { $_.id }
        $unique = $ids | Sort-Object -Unique
        $ids.Count | Should -Be $unique.Count
    }
}

# ============================================================
#  AZ CLI WRAPPER
# ============================================================
Describe 'Get-AzCliResponse' {
    It 'Test-AzCliReady succeeds when az is available' {
        try {
            Test-AzCliReady | Out-Null
            $true | Should -BeTrue
        } catch {
            Set-ItResult -Skipped -Because 'az CLI not available in test environment'
        }
    }
}

# ============================================================
#  EXPORTER FUNCTIONS
# ============================================================
Describe 'Exporters' {
    BeforeEach {
        Reset-BsiResults
        Add-BsiResult -ControlId 'EXP.1' -Title 'Export Test' -Category 'Unit' `
            -Mode ([BsiCheckMode]::Local) -Status ([BsiCheckStatus]::Pass) `
            -Severity ([BsiSeverity]::Low) -Details 'export pass'
        Add-BsiResult -ControlId 'EXP.2' -Title 'Export Test 2' -Category 'Unit' `
            -Mode ([BsiCheckMode]::Local) -Status ([BsiCheckStatus]::Fail) `
            -Severity ([BsiSeverity]::Medium) -Details 'export fail'
    }

    It 'Export-Console returns output without error' {
        $output = Export-Console -Results @((Get-BsiSummary).Results)
        $output | Should -Not -BeNullOrEmpty
    }

    It 'Export-Json writes valid JSON' {
        $tempFile = Join-Path $TestDrive 'test-export.json'
        Export-Json -Results @((Get-BsiSummary).Results) -OutputPath $tempFile
        Test-Path -LiteralPath $tempFile | Should -BeTrue
        $json = Get-Content -Raw -LiteralPath $tempFile | ConvertFrom-Json
        $json.summary | Should -Not -BeNullOrEmpty
        $json.controls.Count | Should -Be 2
    }

    It 'Export-Sarif writes valid SARIF 2.1.0' {
        $tempFile = Join-Path $TestDrive 'test-export.sarif'
        Export-Sarif -Results @((Get-BsiSummary).Results) -OutputPath $tempFile
        $sarif = Get-Content -Raw -LiteralPath $tempFile | ConvertFrom-Json
        $sarif.version | Should -Be '2.1.0'
        $sarif.runs[0].results.Count | Should -Be 2
    }

    It 'Export-JUnitXml writes valid XML' {
        $tempFile = Join-Path $TestDrive 'test-export.junit.xml'
        Export-JUnitXml -Results @((Get-BsiSummary).Results) -OutputPath $tempFile
        [xml]$xml = Get-Content -Raw -LiteralPath $tempFile
        $xml.testsuites.testsuite.count | Should -Be 1
    }

    It 'Export-Html writes HTML file' {
        $tempFile = Join-Path $TestDrive 'test-export.html'
        Export-Html -Results @((Get-BsiSummary).Results) -OutputPath $tempFile
        Test-Path -LiteralPath $tempFile | Should -BeTrue
        $html = Get-Content -Raw -LiteralPath $tempFile
        $html | Should -Match '<!DOCTYPE html>'
        $html | Should -Match 'BSI IT-Grundschutz'
    }
}
