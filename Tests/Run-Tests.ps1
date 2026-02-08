<#
.SYNOPSIS
    Runs all Pester tests for SqlSizer-MSSQL module.
    
.DESCRIPTION
    Executes unit tests and optionally integration tests with code coverage.
    
.PARAMETER CodeCoverage
    Enable code coverage analysis.
    
.PARAMETER OutputPath
    Path for test results output.
    
.PARAMETER Integration
    Include integration tests (requires SQL Server connection).
    
.PARAMETER DataSize
    Data size for integration tests: Tiny, Small, Medium, Large, XLarge, Custom.
    
.PARAMETER Server
    SQL Server instance for integration tests (default: .)
    
.PARAMETER SkipDataSetup
    Skip database initialization for integration tests (use existing data).
    
.EXAMPLE
    .\Run-Tests.ps1
    
.EXAMPLE
    .\Run-Tests.ps1 -CodeCoverage -OutputPath .\TestResults
    
.EXAMPLE
    .\Run-Tests.ps1 -Integration -DataSize Small
    
.EXAMPLE
    .\Run-Tests.ps1 -Integration -DataSize Medium -Server "localhost\SQLEXPRESS"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$CodeCoverage,
    
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".\Tests\Results",
    
    [Parameter(Mandatory = $false)]
    [switch]$Integration,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet('Tiny', 'Small', 'Medium', 'Large', 'XLarge', 'Custom')]
    [string]$DataSize = 'Small',
    
    [Parameter(Mandatory = $false)]
    [string]$Server = '.',
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipDataSetup
)

# Ensure output directory exists
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host " SqlSizer-MSSQL Test Suite" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
if ($Integration) {
    Write-Host " Mode: Unit + Integration Tests" -ForegroundColor White
}
else {
    Write-Host " Mode: Unit Tests Only" -ForegroundColor White
    Write-Host " (Use -Integration for integration tests)" -ForegroundColor DarkGray
}
Write-Host ""

# Import Pester
Import-Module Pester -MinimumVersion 5.0.0 -ErrorAction Stop

# Create Pester configuration
$config = New-PesterConfiguration

# Set test paths based on whether integration tests are included
if ($Integration) {
    Write-Host "Including integration tests (DataSize: $DataSize, Server: $Server)" -ForegroundColor Yellow
    
    # Set environment variables for integration tests
    $env:SQLSIZER_TEST_DATASIZE = $DataSize
    $env:SQLSIZER_TEST_SERVER = $Server
    $env:SQLSIZER_TEST_SKIPDATASETUP = if ($SkipDataSetup) { '1' } else { '0' }
    
    # Run both unit and integration tests
    $config.Run.Path = @(
        '.\Tests\TraversalHelpers.Tests.ps1',
        '.\Tests\QueryBuilders.Tests.ps1',
        '.\Tests\ValidationHelpers.Tests.ps1',
        '.\Tests\Find-Subset.Integration.Tests.ps1'
    )
}
else {
    # Run only unit tests (exclude integration tests)
    $config.Run.Path = @(
        '.\Tests\TraversalHelpers.Tests.ps1',
        '.\Tests\QueryBuilders.Tests.ps1',
        '.\Tests\ValidationHelpers.Tests.ps1'
    )
}

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
