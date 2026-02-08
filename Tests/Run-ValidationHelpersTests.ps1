<#
.SYNOPSIS
    Wrapper script to run ValidationHelpers tests with proper module loading.
    
.DESCRIPTION
    Loads the SqlSizer-MSSQL module first (which loads types), then runs Pester.
    This works around PowerShell class scoping issues in Pester.
#>

$ErrorActionPreference = 'Stop'

# Get module path
$modulePath = Split-Path -Parent $PSScriptRoot

# Import module FIRST with Global scope - this loads the types globally
Write-Host "Loading SqlSizer-MSSQL module..." -ForegroundColor Cyan
Import-Module "$modulePath\SqlSizer-MSSQL\SqlSizer-MSSQL" -Force -Global

Write-Host "Running ValidationHelpers tests..." -ForegroundColor Cyan

# Run Pester
$result = Invoke-Pester -Path "$PSScriptRoot\ValidationHelpers.Tests.ps1" -Output Detailed -PassThru

# Exit with appropriate code
exit $result.FailedCount
