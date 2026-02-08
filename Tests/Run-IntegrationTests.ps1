<#
.SYNOPSIS
    Wrapper script to run integration tests with proper module loading.
    
.DESCRIPTION
    Loads the SqlSizer-MSSQL module first (which loads types), then runs Pester.
    This works around PowerShell class scoping issues in Pester.
    
.PARAMETER DataSize
    Size preset: Tiny (~200 rows), Small (~2K), Medium (~20K), Large (~100K), XLarge (~500K)
    
.PARAMETER Server
    SQL Server instance (default: .)
    
.PARAMETER SkipDataSetup
    Skip database initialization (use existing data)
#>
param(
    [ValidateSet('Tiny', 'Small', 'Medium', 'Large', 'XLarge')]
    [string]$DataSize = 'Tiny',
    
    [string]$Server = '.',
    
    [switch]$SkipDataSetup
)

$ErrorActionPreference = 'Stop'

# Get module path
$modulePath = Split-Path -Parent $PSScriptRoot

# Import module FIRST with Global scope - this loads the types globally
Write-Host "Loading SqlSizer-MSSQL module..." -ForegroundColor Cyan
Import-Module "$modulePath\SqlSizer-MSSQL\SqlSizer-MSSQL" -Force -Global

# Set environment variables for the test
$env:SQLSIZER_TEST_DATASIZE = $DataSize
$env:SQLSIZER_TEST_SERVER = $Server
$env:SQLSIZER_TEST_SKIPDATASETUP = if ($SkipDataSetup) { '1' } else { '0' }

Write-Host "Running integration tests with DataSize=$DataSize, Server=$Server" -ForegroundColor Cyan

# Run Pester
$result = Invoke-Pester -Path "$PSScriptRoot\Find-Subset.Integration.Tests.ps1" -Output Detailed -PassThru

# Clean up environment variables
Remove-Item env:SQLSIZER_TEST_DATASIZE -ErrorAction SilentlyContinue
Remove-Item env:SQLSIZER_TEST_SERVER -ErrorAction SilentlyContinue
Remove-Item env:SQLSIZER_TEST_SKIPDATASETUP -ErrorAction SilentlyContinue

# Return result
$result
