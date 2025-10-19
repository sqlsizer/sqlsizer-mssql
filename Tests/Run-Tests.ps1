<#
.SYNOPSIS
    Runs all Pester tests for SqlSizer-MSSQL module.
    
.DESCRIPTION
    Executes all unit tests with code coverage and generates reports.
    
.PARAMETER CodeCoverage
    Enable code coverage analysis.
    
.PARAMETER OutputPath
    Path for test results output.
    
.EXAMPLE
    .\Run-Tests.ps1
    
.EXAMPLE
    .\Run-Tests.ps1 -CodeCoverage -OutputPath .\TestResults
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$CodeCoverage,
    
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".\Tests\Results"
)

# Ensure output directory exists
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host " SqlSizer-MSSQL Test Suite" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

# Import Pester
Import-Module Pester -MinimumVersion 5.0.0 -ErrorAction Stop

# Create Pester configuration
$config = New-PesterConfiguration

# Set test paths
$config.Run.Path = '.\Tests\'
$config.Run.PassThru = $true

# Output settings
$config.Output.Verbosity = 'Detailed'

# Test result settings
$config.TestResult.Enabled = $true
$config.TestResult.OutputPath = Join-Path $OutputPath 'testResults.xml'
$config.TestResult.OutputFormat = 'NUnitXml'

# Code coverage settings
if ($CodeCoverage) {
    $config.CodeCoverage.Enabled = $true
    $config.CodeCoverage.Path = @(
        '.\SqlSizer-MSSQL\Shared\TraversalHelpers.ps1',
        '.\SqlSizer-MSSQL\Shared\QueryBuilders.ps1'
    )
    $config.CodeCoverage.OutputPath = Join-Path $OutputPath 'coverage.xml'
    $config.CodeCoverage.OutputFormat = 'JaCoCo'
}

# Run tests
Write-Host "Running tests..." -ForegroundColor Yellow
$result = Invoke-Pester -Configuration $config

Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host " Test Results Summary" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Total Tests:  " -NoNewline
Write-Host $result.TotalCount -ForegroundColor White
Write-Host "Passed:       " -NoNewline
Write-Host $result.PassedCount -ForegroundColor Green
Write-Host "Failed:       " -NoNewline
Write-Host $result.FailedCount -ForegroundColor $(if ($result.FailedCount -eq 0) { 'Green' } else { 'Red' })
Write-Host "Skipped:      " -NoNewline
Write-Host $result.SkippedCount -ForegroundColor Yellow
Write-Host "Duration:     " -NoNewline
Write-Host "$($result.Duration.TotalSeconds.ToString('F2'))s" -ForegroundColor White

if ($CodeCoverage) {
    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host " Code Coverage" -ForegroundColor Cyan
    Write-Host "=====================================" -ForegroundColor Cyan
    
    $coverage = $result.CodeCoverage
    if ($null -ne $coverage) {
        $coveredPercent = [math]::Round(($coverage.CoveragePercent), 2)
        $coverageColor = if ($coveredPercent -ge 80) { 'Green' } elseif ($coveredPercent -ge 60) { 'Yellow' } else { 'Red' }
        
        Write-Host "Covered:      " -NoNewline
        Write-Host "$coveredPercent%" -ForegroundColor $coverageColor
        Write-Host "Commands:     " -NoNewline
        Write-Host "$($coverage.CommandsExecutedCount) / $($coverage.CommandsAnalyzedCount)" -ForegroundColor White
        
        Write-Host ""
        Write-Host "Coverage report: " -NoNewline
        Write-Host (Join-Path $OutputPath 'coverage.xml') -ForegroundColor Cyan
    }
}

Write-Host ""
Write-Host "Test results: " -NoNewline
Write-Host (Join-Path $OutputPath 'testResults.xml') -ForegroundColor Cyan
Write-Host ""

# Exit with error code if tests failed
if ($result.FailedCount -gt 0) {
    Write-Host "Tests FAILED!" -ForegroundColor Red
    exit 1
} else {
    Write-Host "All tests PASSED!" -ForegroundColor Green
    exit 0
}
